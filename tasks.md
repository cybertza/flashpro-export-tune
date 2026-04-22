# Task Backlog

Two work-streams: the **Lua plugin** (`ExportTune/`) and the **Python tools** (`tools/`).  
They share the same JSON contract (`tune_export.json` / `tune_import.json`).

---

## Stream A — ExportTune Lua Plugin

### A1 — Modularise main.lua into sub-files  `[prerequisite for everything else]`

`package.path` includes the plugin folder, so `require("modulename")` works for  
sibling `.lua` files. Splitting the 1 250-line monolith makes each feature independently  
editable and testable.

**Proposed file split:**

| File | Contents extracted from main.lua |
|------|----------------------------------|
| `json.lua` | `esc`, `num`, `json.decode` (no FlashPro API deps) |
| `export_cal.lua` | `dump_parameter/index/1d/2d/3d`, `dump_table`, `write_calibration`, `write_dtcs`, `print_cal_summary`, `KEY_PARAMS` |
| `export_datalog.lua` | `SENSORS`, `TS_SENSORS`, `safe_sensor`, `stats`, `ask_sample_count`, `dump_datalogs`, `write_datalog` |
| `import.lua` | `build_cal_index`, `apply_change`, `run_import` |
| `health.lua` | `do_health_check` |
| `debug.lua` | `copy_to_clip`, `INTERESTING_GLOBALS`, `dump_global_val`, `dump_global`, `do_debug` |
| `main.lua` | `get_cal_dir`, `get_downloads_dir`, `get_out_file`, `banner`, `done`, action wrappers, `main()`, callbacks |

**Also update `deploy.bat`:**
```bat
xcopy /Y /I "%SRC%\*.lua" "%DST%\" >nul
```

---

### A2 — Add Table3D import support

`apply_change` currently skips `Table3D` kinds.  
Boost and traction-control maps are 3D; without this, AI-generated changes to them  
cannot be applied.

- Add `elseif kind == "Table3D"` branch in `apply_change` (in `import.lua` after split)
- Validate `pages` array: `#pages == ax3:length()`, each page `rows × cols`
- Call `t:setvalue(val, col, row, page)`
- Update `tune_import.json` format docs in `README.md`

---

### A3 — Per-cell (partial) table import

Currently `Table1D` and `Table2D` imports require the full array.  
AI often only wants to change a handful of cells (e.g. knock retard at a specific RPM/load).

- Accept an optional `"cells"` array instead of `"values"` / `"rows"`:
  ```json
  { "name": "Ignition Low", "kind": "Table2D",
    "cells": [ {"col":3,"row":5,"value":28.0}, ... ] }
  ```
- Validate each index is within bounds before writing
- Mix with full-table replace is not required — one format per change entry is enough

---

### A4 — Export device & ECU metadata

Currently the JSON has no information about the connected FlashPro device or ECU state.  
Useful for AI context and for diagnosing support requests.

- Add a `"device"` block to the export header:
  ```json
  "device": {
    "name": "...", "connected": true, "hardware": "...",
    "serial": "...", "vinlocked": false,
    "obdii_voltage": 12.4, "ignition_on": true
  }
  ```
- Write in `write_header()` (or a new `write_device()`)
- Wrap every `Device.*` and `ECU.*` call in `pcall` (device may not be connected)

---

### A5 — Export calibration table categories

All 300+ tables are currently exported as a flat list.  
Python and AI tools have to guess groupings from table names.

- Add a `"category"` field to each table entry using a name-prefix lookup:
  ```lua
  local CATEGORIES = {
    ["Injector"] = "fuel", ["AFM"] = "fuel", ["Fuel"] = "fuel",
    ["Ignition"] = "ignition", ["Cam"] = "cam",
    ["Idle"] = "idle", ["Rev"] = "limits",
    ["WOT"] = "fuel", ["Lean"] = "fuel",
    ["Boost"] = "boost", ["TC"] = "boost",
    ["AIRC"] = "torque", ["Trq"] = "torque",
    ["Knock"] = "knock", ["K."] = "knock",
  }
  ```
- Adds one string field per table entry; keeps the export backwards-compatible

---

### A6 — Export histogram data per sensor

Currently only `min` / `max` / `mean` are exported per sensor.  
Histograms allow the Python tool to do binning without the full time-series.

- After computing `stats`, do a second pass building a 20-bucket histogram
- Add `"hist": {"bins":[...], "counts":[...]}` inside each sensor stats object
- Bucket boundaries derived from `sensor:min()` / `sensor:max()`
- Make bucket count configurable (default 20) or ask via `InputQuery`

---

### A7 — Health check enhancements

`do_health_check` currently only prints to console.

- Show result in a `ShowMessage` dialog (truncated to 60 lines, full in console)
- Flag warning conditions inline:
  - `|S.TRIM mean| > 5 %` → warn "AFM may need correction"
  - `K.Retard max > 3°` → warn "Knock detected"
  - `Wide min < 11.0` → warn "Dangerously lean WOT excursion"
  - `ECT max > 105°C` → warn "Cooling system concern"
- Return a structured result table so future Python bridge can consume it

---

## Stream B — Python Tools (`tools/`)

### B1 — Knock analysis tab

The most safety-critical analysis missing from the current tool.

- New tab: **Knock**
- Load `K.Retard`, `K.Level`, `K.Retard.1–.4` from time-series
- Scatter: K.Retard vs RPM, coloured by cylinder (1–4 + overall)
- Heatmap: bin K.Retard mean into RPM × Load (MAP) grid — overlay on IGN map shape
- Highlight cells with mean retard > 1° in red, > 3° in orange
- Export: generate `tune_import.json` with IGN table reduced by the mean retard at  
  each RPM/load cell (conservative, opt-in with a checkbox)

---

### B2 — Fuel trim health overview

Companion to the existing AFM analyzer; broader picture.

- New tab: **Fuel Health**
- Panel 1: `S.TRIM` and `L.TRIM` distributions (histogram) with ±5% / ±10% reference lines
- Panel 2: `S.TRIM` mean binned into RPM × MAP grid — shows where the car is running rich/lean
- Panel 3: wideband `Wide` vs `AFCMD` scatter — shows closed-loop tracking accuracy
- Flags: if `|L.TRIM mean| > 8%` suggest AFM correction; if `|L.TRIM| > 15%` warn ECU limit approaching

---

### B3 — Ignition table visualiser

No current table visualisation beyond AFM flow.

- New tab: **Ignition**
- Load `Ignition Low` (or first Table2D named "Ignition*") from `tables[]`
- Render as a 2D heatmap: RPM (X) × Load (Y), colour = degrees
- Overlay datalog density: shade cells by how many time-series frames hit that RPM/load bin
- Tooltip: hover shows RPM, load, timing value, frame count
- No import generation needed for this tab (read-only visualisation)

---

### B4 — Before / after diff viewer

Currently there is no way to compare two exports.

- File menu: **Open Reference Export** (loads a second `tune_export.json`)
- New tab: **Diff**
- List all tables present in both exports
- For Parameter tables: show old → new value, highlight changed
- For 1D/2D tables: show max delta, colour cells that changed
- Export: auto-generate `tune_import.json` from the diff (only changed tables)
- Useful for reviewing what an AI actually changed before applying

---

### B5 — Multi-log support

The analyzer currently assumes a single export file with one log.

- **File > Open Export** can load any `tune_export.json`
- If `datalog.count > 1`, show a log selector dropdown in the toolbar
- All tabs filter their time-series to the selected log
- Summary tab: show stats side-by-side for all logs in the file

---

### B6 — Sensor range anomaly detection

No automated flagging of out-of-range datalog values.

- Add a **Sensor Sanity** report (can live in the Health tab or a new tab)
- Define expected physical ranges per sensor:
  ```python
  EXPECTED = {
    "ECT":   (−10, 120),   # °C
    "IAT":   (−20, 70),
    "MAP":   (0.0, 3.5),   # Bar (allow boost)
    "BAT":   (10.5, 15.5), # V
    "Wide":  (10.0, 18.0), # AFR
    "RPM":   (0, 10000),
    "FuelP": (20, 120),    # PSI
  }
  ```
- Flag any sensor whose `min` or `max` falls outside the expected range
- Show as a colour-coded table (green/yellow/red)

---

### B7 — Export summary report (text / clipboard)

Users frequently copy-paste tune data into AI chat prompts.

- **File > Copy Summary to Clipboard**
- Generates a compact human-readable text block:
  - Key parameters (injector size, closed loop state, fuel trim limits)
  - Sensor stats for the 10 most important sensors
  - Any anomalies from B6
  - AFM correction recommendations if available
- Plain text, suitable for pasting into ChatGPT / Claude prompt

---

## Stream C — Bridge (JSON Contract)

These are format changes that require coordinated updates to both the Lua plugin  
and the Python tool.

### C1 — Add `"category"` field to table entries  *(depends on A5)*

Python tool uses `category` to filter which tables to show in each analysis tab.  
No structural change; just an additive field.

### C2 — Add `"device"` block  *(depends on A4)*

Python tool can show device/ECU status in a status bar or info panel.  
Additive; old exports without the field degrade gracefully.

### C3 — Add `"hist"` to sensor stats  *(depends on A6)*

Python tool uses pre-computed histogram buckets for faster rendering when  
time-series is not loaded or was skipped.  
Additive; tool falls back to computing its own histogram from `ts` rows if absent.

### C4 — Standardise `tune_import.json` for partial cell edits  *(depends on A3)*

Python tool must generate the `"cells"` format when only a subset of cells changes  
(e.g. B1 knock correction only touches cells where mean retard > threshold).
