#!/usr/bin/env python3
"""
FlashPro Tune Analyzer v1.0
Analyzes S.TRIM vs AFM flow from ExportTune JSON exports.
Calculates recommended AFM flow table corrections and exports tune_import.json.

Requirements: pip install matplotlib numpy
"""

import json
import os
import numpy as np
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk


# ── Analysis ───────────────────────────────────────────────────────────────────

def load_export(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def get_afm_table(export):
    """Return (voltage_axis, flow_values) from the AFM flow table."""
    for t in export.get('tables', []):
        if t.get('name') == 'AFM flow' and t['data']['kind'] == 'Table1D':
            return t['data']['axis'], t['data']['values']
    return None, None


def parse_timeseries(log):
    """
    Parse time series rows into list of frame dicts.

    The plugin has a Lua sparse-table bug: sensors that return nil get skipped,
    making rows shorter than ts_cols. We reconstruct the actual column order by
    intersecting ts_cols with what appears in the sensor stats block.
    """
    ts_cols = log.get('ts_cols', [])
    rows    = log.get('ts', [])
    stats   = log.get('sensors', {})

    if not rows:
        return []

    n_actual = len(rows[0])

    if n_actual == len(ts_cols):
        actual_cols = ts_cols
    else:
        # Rebuild: keep time_s plus any ts_col that has stats data
        # (sensors with no data were skipped by the Lua bug)
        actual_cols = ['time_s']
        for col in ts_cols[1:]:
            if col in stats:
                actual_cols.append(col)
        actual_cols = actual_cols[:n_actual]

    col = {name: i for i, name in enumerate(actual_cols)}

    frames = []
    for row in rows:
        try:
            time_s = float(row[col['time_s']]) if 'time_s' in col else None
            afm_v = float(row[col['AFM.v']]) if 'AFM.v' in col else None
            strim = float(row[col['S.TRIM']]) if 'S.TRIM' in col else None
            ect   = float(row[col['ECT']])   if 'ECT'   in col else None
            rpm   = float(row[col['RPM']])   if 'RPM'   in col else None
            ltrim = float(row[col['L.TRIM']]) if 'L.TRIM' in col else 0.0
            if None in (afm_v, strim, ect, rpm):
                continue
            frames.append({'time_s': time_s, 'afm_v': afm_v, 'strim': strim,
                           'ect': ect, 'rpm': rpm, 'ltrim': ltrim})
        except (IndexError, TypeError, ValueError):
            continue
    return frames


def analyze(frames, voltage_axis, flow_values, min_ect=70.0, min_samples=5,
            enforce_monotonic=False, max_ect=999.0, min_rpm=0.0, max_rpm=99999.0):
    """
    Bin frames by AFM voltage index, compute mean S.TRIM per bin,
    and calculate corrected AFM flow values.
    Returns (results_list, scatter_flow, scatter_afmv, scatter_strim).
    """
    n = len(voltage_axis)
    bins = [[] for _ in range(n)]
    scatter_flow, scatter_afmv, scatter_strim = [], [], []

    for fr in frames:
        if fr['ect'] < min_ect or fr['ect'] > max_ect or fr['afm_v'] <= 0:
            continue
        if fr['rpm'] < min_rpm or fr['rpm'] > max_rpm:
            continue
        idx = int(np.searchsorted(voltage_axis, fr['afm_v'], side='right')) - 1
        idx = max(0, min(n - 1, idx))
        bins[idx].append(fr['strim'])
        scatter_flow.append(float(np.interp(fr['afm_v'], voltage_axis, flow_values)))
        scatter_afmv.append(fr['afm_v'])
        scatter_strim.append(fr['strim'])

    results = []
    for i in range(n):
        cur = flow_values[i]
        if len(bins[i]) >= min_samples:
            mean_st = float(np.mean(bins[i]))
            sd_st   = float(np.std(bins[i], ddof=1)) if len(bins[i]) > 1 else 0.0
            rec = max(0.0, cur * (1.0 + mean_st / 100.0))
            results.append({
                'index': i + 1, 'voltage': voltage_axis[i],
                'current': cur, 'mean_strim': mean_st, 'sd_strim': sd_st,
                'samples': len(bins[i]), 'recommended': rec, 'changed': True,
            })
        else:
            results.append({
                'index': i + 1, 'voltage': voltage_axis[i],
                'current': cur, 'mean_strim': None, 'sd_strim': None,
                'samples': len(bins[i]), 'recommended': cur, 'changed': False,
            })

    # Optionally enforce monotonicity on recommended values
    if enforce_monotonic:
        rec = [r['recommended'] for r in results]
        for i in range(1, len(rec)):
            if rec[i] < rec[i - 1]:
                rec[i] = rec[i - 1]
        for i, r in enumerate(results):
            r['recommended'] = round(rec[i], 4)
    else:
        for r in results:
            r['recommended'] = round(r['recommended'], 4)

    return results, scatter_flow, scatter_afmv, scatter_strim


def build_import(results, description='AFM flow correction from S.TRIM analysis'):
    return {
        'description': description,
        'changes': [{
            'name': 'AFM flow',
            'kind': 'Table1D',
            'values': [r['recommended'] for r in results],
        }]
    }


# ── GUI ────────────────────────────────────────────────────────────────────────

BG      = '#2b2b2b'
BG2     = '#1e1e1e'
FG      = '#dddddd'
BLUE    = '#4a9eda'
RED     = '#ff6b6b'
GREEN   = '#5aaa5a'
ORANGE  = '#da7a4a'
GRID    = '#444444'


def dark_fig(rows=1, cols=1, **kw):
    fig = Figure(facecolor=BG2, **kw)
    axes = []
    for i in range(rows * cols):
        ax = fig.add_subplot(rows, cols, i + 1, facecolor=BG)
        ax.tick_params(colors=FG)
        ax.xaxis.label.set_color(FG)
        ax.yaxis.label.set_color(FG)
        for sp in ax.spines.values():
            sp.set_color(GRID)
        ax.grid(color=GRID, linewidth=0.4, linestyle='--')
        axes.append(ax)
    return fig, axes[0] if rows * cols == 1 else axes


class TuneAnalyzer(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('FlashPro Tune Analyzer')
        self.geometry('1280x820')
        self.configure(bg=BG)

        self.export_path  = None
        self.export_data  = None
        self.voltage_axis = None
        self.flow_values  = None
        self.frames       = []
        self.results       = []
        self.scatter_flow  = []
        self.scatter_afmv  = []
        self.scatter_strim = []
        self.scatter_flipped = False
        self.ts_frames        = []   # all frames with time_s for time-series view
        self.scatter_xmode    = tk.StringVar(value='voltage')  # 'flow' | 'voltage'
        self.show_mean_var     = tk.BooleanVar(value=True)
        self.show_sd_var       = tk.BooleanVar(value=False)
        self.show_change_pct_var = tk.BooleanVar(value=False)
        self.enforce_mono_var  = tk.BooleanVar(value=False)
        self.max_ect_var      = tk.StringVar(value='999')
        self._scatter_tooltip  = None  # annotation handle

        self._style()
        self._build_top()
        self._build_notebook()
        self._build_bottom()

    def _style(self):
        s = ttk.Style()
        s.theme_use('clam')
        s.configure('TNotebook',        background=BG,  borderwidth=0)
        s.configure('TNotebook.Tab',    background=BG,  foreground=FG,   padding=[12, 4])
        s.map('TNotebook.Tab', background=[('selected', BG2)])
        s.configure('Treeview',         background=BG2, foreground=FG,   fieldbackground=BG2, rowheight=22)
        s.configure('Treeview.Heading', background=BG,  foreground=FG)
        s.configure('TScrollbar',       background=BG,  troughcolor=BG2)

    def _build_top(self):
        bar = tk.Frame(self, bg=BG, pady=8, padx=10)
        bar.pack(fill='x')

        tk.Button(bar, text='Open tune_export.json', command=self._open,
                  bg=BLUE, fg='white', relief='flat', padx=10, pady=4
                  ).pack(side='left')

        self.file_lbl = tk.Label(bar, text='No file loaded', bg=BG, fg='#888888')
        self.file_lbl.pack(side='left', padx=12)

        # Filters on the right
        f = tk.Frame(bar, bg=BG)
        f.pack(side='right')

        for label, var_name, default, width in [
            ('Min ECT (°C):',  'min_ect_var',     '70', 5),
            ('Min samples:',   'min_samples_var',  '5', 4),
            ('Min RPM:',       'min_rpm_var',      '0', 6),
            ('Max RPM:',       'max_rpm_var',  '99999', 6),
        ]:
            tk.Label(f, text=label, bg=BG, fg=FG).pack(side='left', padx=(8, 2))
            v = tk.StringVar(value=default)
            setattr(self, var_name, v)
            tk.Entry(f, textvariable=v, width=width, bg='#3b3b3b',
                     fg=FG, insertbackground=FG, relief='flat').pack(side='left')

        # ECT preset buttons
        tk.Frame(f, bg='#555555', width=1).pack(side='left', fill='y', padx=(12, 6))
        tk.Label(f, text='ECT:', bg=BG, fg=FG).pack(side='left')
        self.ect_preset_btns = {}
        for label, preset in [('Cold', 'cold'), ('Warm', 'warm'), ('All', 'all')]:
            b = tk.Button(f, text=label, command=lambda p=preset: self._set_ect_preset(p),
                          bg='#3b3b3b', fg=FG, relief='flat', padx=6, pady=2)
            b.pack(side='left', padx=2)
            self.ect_preset_btns[preset] = b
        self._highlight_ect_btn('warm')

        tk.Frame(f, bg='#555555', width=1).pack(side='left', fill='y', padx=(8, 6))
        tk.Checkbutton(f, text='Enforce monotonic AFM', variable=self.enforce_mono_var,
                       bg=BG, fg=FG, selectcolor='#3b3b3b', activebackground=BG,
                       activeforeground=FG
                       ).pack(side='left', padx=(0, 0))

        tk.Button(f, text='Recalculate', command=self._recalculate,
                  bg=GREEN, fg='white', relief='flat', padx=8, pady=4
                  ).pack(side='left', padx=10)

    def _build_notebook(self):
        nb = ttk.Notebook(self)
        nb.pack(fill='both', expand=True, padx=8, pady=(0, 4))
        self._notebook = nb

        self.tab_scatter  = tk.Frame(nb, bg=BG2)
        self.tab_afm      = tk.Frame(nb, bg=BG2)
        self.tab_detail   = tk.Frame(nb, bg=BG2)
        self.tab_timeseries = tk.Frame(nb, bg=BG2)

        nb.add(self.tab_scatter,    text='  S.TRIM vs AFM Voltage  ')
        nb.add(self.tab_afm,        text='  AFM Table: Current vs Recommended  ')
        nb.add(self.tab_detail,     text='  Correction Details  ')
        nb.add(self.tab_timeseries, text='  Time Series  ')

        self._build_scatter_tab()
        self._build_afm_tab()
        self._build_detail_tab()
        self._build_timeseries_tab()

        nb.bind('<<NotebookTabChanged>>', self._on_tab_change)

    def _build_scatter_tab(self):
        ctrl = tk.Frame(self.tab_scatter, bg=BG2)
        ctrl.pack(fill='x', padx=6, pady=4)

        tk.Label(ctrl, text='X axis:', bg=BG2, fg=FG).pack(side='left', padx=(0, 4))
        for label, val in [('AFM Flow (g/s)', 'flow'), ('AFM Voltage (V)', 'voltage')]:
            tk.Radiobutton(ctrl, text=label, variable=self.scatter_xmode, value=val,
                           bg=BG2, fg=FG, selectcolor='#3b3b3b', activebackground=BG2,
                           activeforeground=FG, command=self._draw_scatter
                           ).pack(side='left', padx=2)

        tk.Frame(ctrl, bg='#555555', width=1).pack(side='left', fill='y', padx=8)

        tk.Checkbutton(ctrl, text='Show Mean', variable=self.show_mean_var,
                       bg=BG2, fg=FG, selectcolor='#3b3b3b', activebackground=BG2,
                       activeforeground=FG, command=self._draw_scatter
                       ).pack(side='left', padx=2)
        tk.Checkbutton(ctrl, text='Show SD', variable=self.show_sd_var,
                       bg=BG2, fg=FG, selectcolor='#3b3b3b', activebackground=BG2,
                       activeforeground=FG, command=self._draw_scatter
                       ).pack(side='left', padx=2)
        tk.Checkbutton(ctrl, text='Show Change %', variable=self.show_change_pct_var,
                       bg=BG2, fg=FG, selectcolor='#3b3b3b', activebackground=BG2,
                       activeforeground=FG, command=self._draw_scatter
                       ).pack(side='left', padx=2)

        tk.Frame(ctrl, bg='#555555', width=1).pack(side='left', fill='y', padx=8)

        tk.Button(ctrl, text='Flip Axes', command=self._toggle_scatter_axes,
                  bg='#3b3b3b', fg=FG, relief='flat', padx=8, pady=2
                  ).pack(side='left')
        self.flip_lbl = tk.Label(ctrl, text='', bg=BG2, fg='#888888')
        self.flip_lbl.pack(side='left', padx=8)

        fig, (ax, ax_pct) = dark_fig(rows=2, cols=1, figsize=(11, 6))
        fig.tight_layout(pad=1.5)
        self._embed(fig, self.tab_scatter)
        self.ax_scatter     = ax
        self.ax_scatter_pct = ax_pct
        self.fig_scatter    = fig
        self._update_flip_label()

        # Hover tooltip
        fig._canvas.mpl_connect('motion_notify_event', self._on_scatter_hover)

    def _build_afm_tab(self):
        fig, (ax_top, ax_bot) = dark_fig(rows=2, cols=1, figsize=(11, 6))
        ax_top.set_ylabel('Airflow (g/s)')
        ax_bot.set_xlabel('AFM Voltage (V)')
        ax_bot.set_ylabel('Change (%)')
        ax_bot.axhline(0, color='#888888', linestyle='--', linewidth=0.8)
        fig.tight_layout(pad=1.5)
        self._embed(fig, self.tab_afm)
        self.ax_afm     = ax_top
        self.ax_afm_pct = ax_bot
        self.fig_afm    = fig

    def _build_detail_tab(self):
        cols = ('Idx', 'Voltage (V)', 'Current (g/s)', 'Mean S.TRIM (%)',
                'Samples', 'Recommended (g/s)', 'Change (%)')
        self.tree = ttk.Treeview(self.tab_detail, columns=cols,
                                  show='headings', selectmode='browse')
        widths = (40, 100, 120, 130, 80, 150, 90)
        for c, w in zip(cols, widths):
            self.tree.heading(c, text=c)
            self.tree.column(c, width=w, anchor='center')

        vsb = ttk.Scrollbar(self.tab_detail, orient='vertical',
                             command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side='left', fill='both', expand=True)
        vsb.pack(side='right', fill='y')

        self.tree.tag_configure('changed',   background='#1a2e1a', foreground='#88dd88')
        self.tree.tag_configure('unchanged', background=BG2,       foreground='#888888')

    def _build_timeseries_tab(self):
        ctrl = tk.Frame(self.tab_timeseries, bg=BG2)
        ctrl.pack(fill='x', padx=6, pady=4)

        tk.Label(ctrl, text='RPM band:', bg=BG2, fg=FG).pack(side='left', padx=(0, 4))
        self.ts_rpm_lo_var = tk.StringVar(value='1200')
        self.ts_rpm_hi_var = tk.StringVar(value='1800')
        for var in (self.ts_rpm_lo_var, self.ts_rpm_hi_var):
            tk.Entry(ctrl, textvariable=var, width=6, bg='#3b3b3b',
                     fg=FG, insertbackground=FG, relief='flat').pack(side='left', padx=2)
        tk.Button(ctrl, text='Update', command=self._draw_timeseries,
                  bg='#3b3b3b', fg=FG, relief='flat', padx=6, pady=2
                  ).pack(side='left', padx=6)

        fig, (ax_rpm, ax_st) = dark_fig(rows=2, cols=1, figsize=(11, 6))
        ax_rpm.set_ylabel('RPM', color=FG)
        ax_st.set_ylabel('S.TRIM (%)', color=FG)
        ax_st.set_xlabel('Time (s)', color=FG)
        fig.tight_layout(pad=1.5)
        self._embed(fig, self.tab_timeseries)
        self.ax_ts_rpm = ax_rpm
        self.ax_ts_st  = ax_st
        self.fig_ts    = fig

    def _draw_timeseries(self):
        if not self.frames:
            return

        try:
            rpm_lo = float(self.ts_rpm_lo_var.get())
            rpm_hi = float(self.ts_rpm_hi_var.get())
        except ValueError:
            rpm_lo, rpm_hi = 1200.0, 1800.0

        # Only frames that have a valid time_s
        tframes = [f for f in self.frames if f.get('time_s') is not None]
        if not tframes:
            return

        times = [f['time_s'] for f in tframes]
        rpms  = [f['rpm']    for f in tframes]
        strims = [f['strim'] for f in tframes]

        ax_rpm = self.ax_ts_rpm
        ax_st  = self.ax_ts_st
        for ax in (ax_rpm, ax_st):
            ax.clear()
            ax.set_facecolor(BG)
            ax.tick_params(colors=FG)
            ax.grid(color=GRID, linewidth=0.4, linestyle='--')
            for sp in ax.spines.values(): sp.set_color(GRID)

        # RPM plot — shade the 1200-1800 band
        ax_rpm.plot(times, rpms, color=BLUE, linewidth=0.8, alpha=0.9, label='RPM')
        ax_rpm.axhspan(rpm_lo, rpm_hi, color=ORANGE, alpha=0.12, label=f'{rpm_lo:.0f}–{rpm_hi:.0f} RPM')
        ax_rpm.axhline(rpm_lo, color=ORANGE, linewidth=0.7, linestyle=':')
        ax_rpm.axhline(rpm_hi, color=ORANGE, linewidth=0.7, linestyle=':')
        ax_rpm.set_ylabel('RPM', color=FG)
        ax_rpm.legend(facecolor='#3b3b3b', labelcolor=FG, framealpha=0.8)

        # S.TRIM plot — colour points in/out of RPM band
        in_band  = [(t, s) for t, s, r in zip(times, strims, rpms) if rpm_lo <= r <= rpm_hi]
        out_band = [(t, s) for t, s, r in zip(times, strims, rpms) if not (rpm_lo <= r <= rpm_hi)]

        ax_st.axhline(0,  color='#888888', linestyle='--', linewidth=0.8)
        ax_st.axhline(5,  color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7)
        ax_st.axhline(-5, color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7)

        if out_band:
            ox, oy = zip(*out_band)
            ax_st.scatter(ox, oy, s=3, alpha=0.2, color=BLUE, zorder=2, label='Outside band')
        if in_band:
            ix, iy = zip(*in_band)
            ax_st.scatter(ix, iy, s=5, alpha=0.6, color=RED, zorder=3,
                          label=f'In {rpm_lo:.0f}–{rpm_hi:.0f} RPM band')

        ax_st.set_ylabel('S.TRIM (%)', color=FG)
        ax_st.set_xlabel('Time (s)', color=FG)
        ax_st.legend(facecolor='#3b3b3b', labelcolor=FG, framealpha=0.8)

        self.fig_ts.tight_layout(pad=1.5)
        self.fig_ts._canvas.draw_idle()

    def _build_bottom(self):
        bar = tk.Frame(self, bg=BG, pady=6, padx=10)
        bar.pack(fill='x', side='bottom')

        self.status_lbl = tk.Label(bar, text='Open a tune_export.json to begin',
                                    bg=BG, fg='#888888')
        self.status_lbl.pack(side='left')

        tk.Button(bar, text='Export tune_import.json', command=self._export,
                  bg=ORANGE, fg='white', relief='flat', padx=12, pady=4
                  ).pack(side='right')

    def _embed(self, fig, parent):
        canvas = FigureCanvasTkAgg(fig, master=parent)
        canvas.draw()
        canvas.get_tk_widget().pack(fill='both', expand=True)
        tb = NavigationToolbar2Tk(canvas, parent)
        tb.config(bg=BG)
        tb.update()
        # Store canvas on fig for later redraws
        fig._canvas = canvas

    def _open(self):
        path = filedialog.askopenfilename(
            title='Open tune_export.json',
            filetypes=[('JSON', '*.json'), ('All', '*.*')],
        )
        if not path:
            return
        try:
            self.export_data  = load_export(path)
            self.export_path  = path
            self.voltage_axis, self.flow_values = get_afm_table(self.export_data)
            if self.voltage_axis is None:
                messagebox.showerror('Error', 'AFM flow table not found in export.')
                return
            logs = self.export_data.get('datalog', {}).get('logs', [])
            self.frames = []
            for log in logs:
                self.frames.extend(parse_timeseries(log))
            cal = (self.export_data.get('calibration_file') or 'unknown').split('\\')[-1]
            self.file_lbl.config(text=f'{os.path.basename(path)}  |  cal: {cal}')
            self._recalculate()
        except Exception as e:
            messagebox.showerror('Load error', str(e))

    def _set_ect_preset(self, preset):
        if preset == 'cold':
            self.min_ect_var.set('0')
            self.max_ect_var.set('70')
        elif preset == 'warm':
            self.min_ect_var.set('70')
            self.max_ect_var.set('999')
        else:  # all
            self.min_ect_var.set('0')
            self.max_ect_var.set('999')
        self._highlight_ect_btn(preset)
        self._recalculate()

    def _highlight_ect_btn(self, active):
        for key, btn in self.ect_preset_btns.items():
            btn.config(bg=BLUE if key == active else '#3b3b3b')

    def _on_tab_change(self, _event):
        tab = self._notebook.index(self._notebook.select())
        if tab == 0:
            self.fig_scatter._canvas.draw()
        elif tab == 1:
            self.fig_afm._canvas.draw()
        elif tab == 3:
            self.fig_ts._canvas.draw()

    def _recalculate(self):
        if not self.frames or self.voltage_axis is None:
            return
        try:
            min_ect     = float(self.min_ect_var.get())
            max_ect     = float(self.max_ect_var.get())
            min_samples = int(self.min_samples_var.get())
            min_rpm     = float(self.min_rpm_var.get())
            max_rpm     = float(self.max_rpm_var.get())
        except ValueError:
            messagebox.showerror('Error', 'Invalid filter values.')
            return

        self.results, self.scatter_flow, self.scatter_afmv, self.scatter_strim = analyze(
            self.frames, self.voltage_axis, self.flow_values, min_ect, min_samples,
            enforce_monotonic=self.enforce_mono_var.get(), max_ect=max_ect,
            min_rpm=min_rpm, max_rpm=max_rpm,
        )
        self._draw_scatter()
        self._draw_afm()
        self._fill_tree()
        self._draw_timeseries()

        total = len(self.frames)
        filtered = len(self.scatter_afmv)
        changed = sum(1 for r in self.results if r['changed'])
        ect_desc = f'ECT {min_ect}–{max_ect}°C' if max_ect < 999 else f'ECT≥{min_ect}°C'
        self.status_lbl.config(
            text=f'{total} frames total | {filtered} in filter ({ect_desc}) | '
                 f'{changed}/{len(self.results)} bins corrected'
        )

    def _update_flip_label(self):
        xmode   = self.scatter_xmode.get()
        flipped = self.scatter_flipped
        x_label = 'S.TRIM (%)' if flipped else ('AFM Voltage (V)' if xmode == 'voltage' else 'AFM Flow (g/s)')
        y_label = ('AFM Voltage (V)' if xmode == 'voltage' else 'AFM Flow (g/s)') if flipped else 'S.TRIM (%)'
        self.flip_lbl.config(text=f'X: {x_label}  |  Y: {y_label}')

    def _toggle_scatter_axes(self):
        self.scatter_flipped = not self.scatter_flipped
        self._update_flip_label()
        self._draw_scatter()

    def _draw_scatter(self):
        ax      = self.ax_scatter
        ax_pct  = self.ax_scatter_pct
        show_pct = self.show_change_pct_var.get()

        # Toggle bottom panel visibility
        ax_pct.set_visible(show_pct)

        # Resize via gridspec
        gs = self.fig_scatter.add_gridspec(2, 1,
            height_ratios=[3, 1] if show_pct else [1, 0],
            hspace=0.35)
        ax.set_subplotspec(gs[0])
        ax_pct.set_subplotspec(gs[1])

        ax.clear()
        ax.set_facecolor(BG)
        ax.tick_params(colors=FG)
        ax.grid(color=GRID, linewidth=0.4, linestyle='--')
        for sp in ax.spines.values(): sp.set_color(GRID)

        flipped  = self.scatter_flipped
        xmode    = self.scatter_xmode.get()   # 'flow' | 'voltage'
        show_mean = self.show_mean_var.get()
        show_sd   = self.show_sd_var.get()

        # Choose raw scatter x values based on xmode
        raw_x_vals = self.scatter_afmv if xmode == 'voltage' else self.scatter_flow
        x_label_base = 'AFM Voltage (V)' if xmode == 'voltage' else 'AFM Flow (g/s)'

        if flipped:
            x_label, y_label = 'S.TRIM (%)', x_label_base
            ax.axvline(0,  color='#888888', linestyle='--', linewidth=0.8)
            ax.axvline(5,  color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7, label='\u00b15% threshold')
            ax.axvline(-5, color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7)
        else:
            x_label, y_label = x_label_base, 'S.TRIM (%)'
            ax.axhline(0,  color='#888888', linestyle='--', linewidth=0.8)
            ax.axhline(5,  color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7, label='\u00b15% threshold')
            ax.axhline(-5, color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7)

        ax.set_xlabel(x_label, color=FG)
        ax.set_ylabel(y_label, color=FG)

        # Raw scatter points
        if raw_x_vals:
            xs = self.scatter_strim if flipped else raw_x_vals
            ys = raw_x_vals         if flipped else self.scatter_strim
            ax.scatter(xs, ys, alpha=0.15, s=6, color=BLUE, zorder=2, label='Frames (warm)')

        # Per-bin x values (voltage or flow)
        bin_x_key = 'voltage' if xmode == 'voltage' else 'current'
        valid = [r for r in self.results if r['mean_strim'] is not None]

        if valid and show_mean:
            bx = [r['mean_strim'] if flipped else r[bin_x_key] for r in valid]
            by = [r[bin_x_key]    if flipped else r['mean_strim'] for r in valid]
            ax.plot(bx, by, 'o-', color=RED, linewidth=2, markersize=5,
                    zorder=4, label='Mean S.TRIM per bin')

        if valid and show_sd:
            bx  = [r['mean_strim'] if flipped else r[bin_x_key] for r in valid]
            bsd = [r['sd_strim'] for r in valid]
            by  = [r[bin_x_key]  if flipped else r['mean_strim'] for r in valid]
            if flipped:
                # SD is on the x-axis
                ax.fill_betweenx(
                    by,
                    [x - s for x, s in zip(bx, bsd)],
                    [x + s for x, s in zip(bx, bsd)],
                    alpha=0.20, color=RED, zorder=3, label='\u00b11 SD'
                )
            else:
                ax.fill_between(
                    bx,
                    [y - s for y, s in zip(by, bsd)],
                    [y + s for y, s in zip(by, bsd)],
                    alpha=0.20, color=RED, zorder=3, label='\u00b11 SD'
                )

        ax.legend(facecolor='#3b3b3b', labelcolor=FG, framealpha=0.8)

        # ── Change % panel ────────────────────────────────────────────────
        if show_pct:
            ax_pct.clear()
            ax_pct.set_facecolor(BG)
            ax_pct.tick_params(colors=FG)
            ax_pct.grid(color=GRID, linewidth=0.4, linestyle='--')
            for sp in ax_pct.spines.values(): sp.set_color(GRID)
            ax_pct.axhline(0, color='#888888', linestyle='--', linewidth=0.8)

            xmode    = self.scatter_xmode.get()
            bin_x_key = 'voltage' if xmode == 'voltage' else 'current'
            valid = [r for r in self.results if r['changed']]
            if valid:
                bx  = [r[bin_x_key] for r in valid]
                pct = [(r['recommended'] - r['current']) / max(r['current'], 1e-6) * 100
                       for r in valid]
                colours = [GREEN if p >= 0 else RED for p in pct]
                bar_w = (max(bx) - min(bx)) / len(bx) * 0.6 if len(bx) > 1 else 0.04
                ax_pct.bar(bx, pct, width=bar_w, color=colours, alpha=0.85, zorder=3)
                for x, p in zip(bx, pct):
                    ax_pct.text(x, p + (0.15 if p >= 0 else -0.15),
                                f'{p:+.1f}', ha='center',
                                va='bottom' if p >= 0 else 'top',
                                fontsize=6, color=FG, alpha=0.8)

            xlabel = 'AFM Voltage (V)' if xmode == 'voltage' else 'AFM Flow (g/s)'
            ax_pct.set_xlabel(xlabel, color=FG)
            ax_pct.set_ylabel('Change (%)', color=FG)

        self.fig_scatter.tight_layout(pad=1.5)
        self.fig_scatter._canvas.draw_idle()
        self._update_flip_label()

    def _on_scatter_hover(self, event):
        ax = self.ax_scatter
        if event.inaxes != ax or not self.scatter_afmv:
            if self._scatter_tooltip:
                self._scatter_tooltip.set_visible(False)
                self.fig_scatter._canvas.draw_idle()
            return

        flipped = self.scatter_flipped
        xmode   = self.scatter_xmode.get()
        raw_xs  = self.scatter_afmv if xmode == 'voltage' else self.scatter_flow
        xs = self.scatter_strim if flipped else raw_xs
        ys = raw_xs if flipped else self.scatter_strim

        # Find nearest point
        dists = [(event.xdata - x) ** 2 + (event.ydata - y) ** 2
                 for x, y in zip(xs, ys)]
        idx = int(np.argmin(dists))
        dist = dists[idx] ** 0.5
        # Only show if within reasonable pixel distance
        xlim = ax.get_xlim(); ylim = ax.get_ylim()
        thresh = ((xlim[1]-xlim[0])*0.03)**2 + ((ylim[1]-ylim[0])*0.03)**2
        if dists[idx] > thresh:
            if self._scatter_tooltip:
                self._scatter_tooltip.set_visible(False)
                self.fig_scatter._canvas.draw_idle()
            return

        afmv  = self.scatter_afmv[idx]
        flow  = self.scatter_flow[idx]
        strim = self.scatter_strim[idx]
        tip   = f'AFM.v: {afmv:.3f} V\nFlow: {flow:.1f} g/s\nS.TRIM: {strim:+.1f}%'

        if self._scatter_tooltip is None:
            self._scatter_tooltip = ax.annotate(
                tip, xy=(xs[idx], ys[idx]),
                xytext=(12, 12), textcoords='offset points',
                bbox=dict(boxstyle='round,pad=0.4', facecolor='#3b3b3b', edgecolor=GRID, alpha=0.9),
                color=FG, fontsize=8, zorder=10
            )
        else:
            self._scatter_tooltip.set_text(tip)
            self._scatter_tooltip.xy = (xs[idx], ys[idx])
            self._scatter_tooltip.set_visible(True)
        self.fig_scatter._canvas.draw_idle()

    def _draw_afm(self):
        ax  = self.ax_afm
        ax2 = self.ax_afm_pct
        for a in (ax, ax2):
            a.clear()
            a.set_facecolor(BG)
            a.tick_params(colors=FG)
            a.grid(color=GRID, linewidth=0.4, linestyle='--')
            for sp in a.spines.values(): sp.set_color(GRID)

        ax.set_ylabel('Airflow (g/s)', color=FG)
        ax2.set_xlabel('AFM Voltage (V)', color=FG)
        ax2.set_ylabel('Change (%)', color=FG)
        ax2.axhline(0, color='#888888', linestyle='--', linewidth=0.8)

        v   = [r['voltage']     for r in self.results]
        cur = [r['current']     for r in self.results]
        rec = [r['recommended'] for r in self.results]
        pct = [(r - c) / max(c, 1e-6) * 100 for c, r in zip(cur, rec)]

        ax.plot(v, cur, 'o-',  color=BLUE, linewidth=2, markersize=4, label='Current')
        ax.plot(v, rec, 's--', color=RED,  linewidth=2, markersize=4, label='Recommended')
        ax.fill_between(v, cur, rec, alpha=0.15, color=RED)
        ax.legend(facecolor='#3b3b3b', labelcolor=FG, framealpha=0.8)

        # Colour bars: green = positive correction, red = negative
        colours = [GREEN if p >= 0 else RED for p in pct]
        ax2.bar(v, pct, width=0.04, color=colours, alpha=0.8, zorder=3)
        # Annotate bins with enough samples
        for r, p in zip(self.results, pct):
            if r['changed']:
                ax2.text(r['voltage'], p + (0.3 if p >= 0 else -0.3),
                         f"{p:+.1f}", ha='center', va='bottom' if p >= 0 else 'top',
                         fontsize=6, color=FG, alpha=0.8)

        self.fig_afm.tight_layout(pad=1.5)
        self.fig_afm._canvas.draw_idle()

    def _fill_tree(self):
        for item in self.tree.get_children():
            self.tree.delete(item)

        for r in self.results:
            if r['changed']:
                pct = (r['recommended'] - r['current']) / max(r['current'], 1e-6) * 100
                self.tree.insert('', 'end', tags=('changed',), values=(
                    r['index'],
                    f"{r['voltage']:.4f}",
                    f"{r['current']:.4f}",
                    f"{r['mean_strim']:+.2f}",
                    r['samples'],
                    f"{r['recommended']:.4f}",
                    f"{pct:+.1f}%",
                ))
            else:
                self.tree.insert('', 'end', tags=('unchanged',), values=(
                    r['index'],
                    f"{r['voltage']:.4f}",
                    f"{r['current']:.4f}",
                    '-',
                    r['samples'],
                    f"{r['recommended']:.4f}",
                    '-',
                ))

    def _export(self):
        if not self.results:
            messagebox.showwarning('No data', 'Load and analyse a file first.')
            return
        initial = str(Path(self.export_path).parent) if self.export_path else '.'
        path = filedialog.asksaveasfilename(
            title='Save tune_import.json',
            initialdir=initial,
            initialfile='tune_import.json',
            defaultextension='.json',
            filetypes=[('JSON', '*.json')],
        )
        if not path:
            return
        data = build_import(self.results)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
        changed = sum(1 for r in self.results if r['changed'])
        messagebox.showinfo('Saved',
            f'tune_import.json saved.\n{changed} AFM flow values corrected.\n\n'
            f'Load it in FlashPro via ExportTune option 5 (preview) then option 6 (apply).')


if __name__ == '__main__':
    app = TuneAnalyzer()
    app.mainloop()
