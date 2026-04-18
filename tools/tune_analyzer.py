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
            afm_v = float(row[col['AFM.v']]) if 'AFM.v' in col else None
            strim = float(row[col['S.TRIM']]) if 'S.TRIM' in col else None
            ect   = float(row[col['ECT']])   if 'ECT'   in col else None
            rpm   = float(row[col['RPM']])   if 'RPM'   in col else None
            ltrim = float(row[col['L.TRIM']]) if 'L.TRIM' in col else 0.0
            if None in (afm_v, strim, ect, rpm):
                continue
            frames.append({'afm_v': afm_v, 'strim': strim,
                           'ect': ect, 'rpm': rpm, 'ltrim': ltrim})
        except (IndexError, TypeError, ValueError):
            continue
    return frames


def analyze(frames, voltage_axis, flow_values, min_ect=70.0, min_samples=5):
    """
    Bin frames by AFM voltage index, compute mean S.TRIM per bin,
    and calculate corrected AFM flow values.
    Returns (results_list, scatter_flow, scatter_strim).
    """
    n = len(voltage_axis)
    bins = [[] for _ in range(n)]
    scatter_flow, scatter_strim = [], []

    for fr in frames:
        if fr['ect'] < min_ect or fr['afm_v'] <= 0:
            continue
        idx = int(np.searchsorted(voltage_axis, fr['afm_v'], side='right')) - 1
        idx = max(0, min(n - 1, idx))
        bins[idx].append(fr['strim'])
        scatter_flow.append(float(np.interp(fr['afm_v'], voltage_axis, flow_values)))
        scatter_strim.append(fr['strim'])

    results = []
    for i in range(n):
        cur = flow_values[i]
        if len(bins[i]) >= min_samples:
            mean_st = float(np.mean(bins[i]))
            rec = max(0.0, cur * (1.0 + mean_st / 100.0))
            results.append({
                'index': i + 1, 'voltage': voltage_axis[i],
                'current': cur, 'mean_strim': mean_st,
                'samples': len(bins[i]), 'recommended': rec, 'changed': True,
            })
        else:
            results.append({
                'index': i + 1, 'voltage': voltage_axis[i],
                'current': cur, 'mean_strim': None,
                'samples': len(bins[i]), 'recommended': cur, 'changed': False,
            })

    # Enforce monotonicity on recommended values
    rec = [r['recommended'] for r in results]
    for i in range(1, len(rec)):
        if rec[i] < rec[i - 1]:
            rec[i] = rec[i - 1]
    for i, r in enumerate(results):
        r['recommended'] = round(rec[i], 4)

    return results, scatter_flow, scatter_strim


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
        self.results      = []
        self.scatter_flow = []
        self.scatter_strim = []

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
        ]:
            tk.Label(f, text=label, bg=BG, fg=FG).pack(side='left', padx=(8, 2))
            v = tk.StringVar(value=default)
            setattr(self, var_name, v)
            tk.Entry(f, textvariable=v, width=width, bg='#3b3b3b',
                     fg=FG, insertbackground=FG, relief='flat').pack(side='left')

        tk.Button(f, text='Recalculate', command=self._recalculate,
                  bg=GREEN, fg='white', relief='flat', padx=8, pady=4
                  ).pack(side='left', padx=10)

    def _build_notebook(self):
        nb = ttk.Notebook(self)
        nb.pack(fill='both', expand=True, padx=8, pady=(0, 4))

        self.tab_scatter = tk.Frame(nb, bg=BG2)
        self.tab_afm     = tk.Frame(nb, bg=BG2)
        self.tab_detail  = tk.Frame(nb, bg=BG2)

        nb.add(self.tab_scatter, text='  S.TRIM vs AFM Flow  ')
        nb.add(self.tab_afm,     text='  AFM Table: Current vs Recommended  ')
        nb.add(self.tab_detail,  text='  Correction Details  ')

        self._build_scatter_tab()
        self._build_afm_tab()
        self._build_detail_tab()

    def _build_scatter_tab(self):
        fig, ax = dark_fig(figsize=(11, 5))
        ax.set_xlabel('AFM Flow (g/s)')
        ax.set_ylabel('S.TRIM (%)')
        ax.axhline(0,  color='#888888', linestyle='--', linewidth=0.8)
        ax.axhline(5,  color=ORANGE,    linestyle=':',  linewidth=0.7, alpha=0.6)
        ax.axhline(-5, color=ORANGE,    linestyle=':',  linewidth=0.7, alpha=0.6)
        fig.tight_layout(pad=1.5)
        self._embed(fig, self.tab_scatter)
        self.ax_scatter = ax
        self.fig_scatter = fig

    def _build_afm_tab(self):
        fig, ax = dark_fig(figsize=(11, 5))
        ax.set_xlabel('AFM Voltage (V)')
        ax.set_ylabel('Airflow (g/s)')
        fig.tight_layout(pad=1.5)
        self._embed(fig, self.tab_afm)
        self.ax_afm = ax
        self.fig_afm = fig

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

    def _recalculate(self):
        if not self.frames or self.voltage_axis is None:
            return
        try:
            min_ect     = float(self.min_ect_var.get())
            min_samples = int(self.min_samples_var.get())
        except ValueError:
            messagebox.showerror('Error', 'Invalid filter values.')
            return

        self.results, self.scatter_flow, self.scatter_strim = analyze(
            self.frames, self.voltage_axis, self.flow_values, min_ect, min_samples
        )
        self._draw_scatter()
        self._draw_afm()
        self._fill_tree()

        warm = sum(1 for fr in self.frames if fr['ect'] >= min_ect)
        changed = sum(1 for r in self.results if r['changed'])
        self.status_lbl.config(
            text=f'{len(self.frames)} frames total | {warm} warm (ECT≥{min_ect}°C) | '
                 f'{changed}/{len(self.results)} bins corrected'
        )

    def _draw_scatter(self):
        ax = self.ax_scatter
        ax.clear()
        ax.set_facecolor(BG)
        ax.set_xlabel('AFM Flow (g/s)', color=FG)
        ax.set_ylabel('S.TRIM (%)', color=FG)
        ax.tick_params(colors=FG)
        ax.grid(color=GRID, linewidth=0.4, linestyle='--')
        for sp in ax.spines.values(): sp.set_color(GRID)
        ax.axhline(0,  color='#888888', linestyle='--', linewidth=0.8)
        ax.axhline(5,  color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7, label='±5% threshold')
        ax.axhline(-5, color=ORANGE, linestyle=':', linewidth=0.7, alpha=0.7)

        if self.scatter_flow:
            ax.scatter(self.scatter_flow, self.scatter_strim,
                       alpha=0.15, s=6, color=BLUE, zorder=2, label='Frames (warm)')

        x = [r['current'] for r in self.results if r['mean_strim'] is not None]
        y = [r['mean_strim'] for r in self.results if r['mean_strim'] is not None]
        if x:
            ax.plot(x, y, 'o-', color=RED, linewidth=2, markersize=5,
                    zorder=3, label='Mean S.TRIM per bin')

        ax.legend(facecolor='#3b3b3b', labelcolor=FG, framealpha=0.8)
        self.fig_scatter.tight_layout(pad=1.5)
        self.fig_scatter._canvas.draw()

    def _draw_afm(self):
        ax = self.ax_afm
        ax.clear()
        ax.set_facecolor(BG)
        ax.set_xlabel('AFM Voltage (V)', color=FG)
        ax.set_ylabel('Airflow (g/s)', color=FG)
        ax.tick_params(colors=FG)
        ax.grid(color=GRID, linewidth=0.4, linestyle='--')
        for sp in ax.spines.values(): sp.set_color(GRID)

        v   = [r['voltage']     for r in self.results]
        cur = [r['current']     for r in self.results]
        rec = [r['recommended'] for r in self.results]

        ax.plot(v, cur, 'o-',  color=BLUE, linewidth=2, markersize=4, label='Current')
        ax.plot(v, rec, 's--', color=RED,  linewidth=2, markersize=4, label='Recommended')
        ax.fill_between(v, cur, rec, alpha=0.12, color=RED)

        ax.legend(facecolor='#3b3b3b', labelcolor=FG, framealpha=0.8)
        self.fig_afm.tight_layout(pad=1.5)
        self.fig_afm._canvas.draw()

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
