# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Hondata FlashPro Lua plugin (`ExportTune/main.lua`) that exports calibration tables, datalogs and DTCs to JSON for AI analysis, plus a companion Python analysis tool (`tools/tune_analyzer.py`).

## Deploy after every edit

**FlashPro caches plugin Lua at startup.** After editing `main.lua`, copy it to the live folder and restart FlashPro:
reloading the plugin also seems to work.

```
# From repo root (Windows cmd):
deploy.bat

# From bash:
cp ExportTune/*.lua "$LOCALAPPDATA/Hondata/FlashPro/Plugins/ExportTune/"
cp ExportTune/info.xml "$LOCALAPPDATA/Hondata/FlashPro/Plugins/ExportTune/info.xml"
```

Live plugin folder: `C:\Users\<you>\AppData\Local\Hondata\FlashPro\Plugins\ExportTune\`

## Version scheme

`VERSION` in `main.lua` follows `yymmdd.rev` (e.g. `260421.1`). Increment `.rev` for same-day releases. Update it for every commit that touches `main.lua`.

## Architecture

### Plugin (`ExportTune/`)

Modular Lua plugin. Entry point is `main()` in `main.lua`. Presents an `InputQuery` dialog menu (options 1–8). Each concern lives in its own file — all files are deployed together.

| File | Responsibility |
|------|----------------|
| `main.lua` | Entry point, menu, event callbacks, path/banner helpers |
| `json.lua` | `esc()`, `num()`, `json.decode()` — no FlashPro API deps |
| `export_cal.lua` | Calibration + DTC serialisers, key-param summary |
| `export_datalog.lua` | Sensor lists, stats, time-series export |
| `import.lua` | `run()`, `apply_change()`, name→index cache |
| `health.lua` | Health check with threshold warnings |
| `probe.lua` | **Option 8** — systematic API surface test (VCL, dialogs, utilities, Device, ECU) |
| `debug.lua` | Global dump, VCL introspection, clipboard helper |

**Key globals provided by FlashPro:**
- `Calibration` — `.loaded()`, `.filename()`, `.table(i)`, `.tablecount()`, `.update()`
- `DatalogManager` — `.count()`, `.datalog(i)`
- `SensorList` — `.count()`, `.sensor(i)`, and `SensorList["RPM"]` via `MT.__index`
- `ErrorCodeList` — `.count()`, `.code(i)`
- `Constants` — from `require("constants")` — provides `Constants.TableKind.*` and `Constants.UnitName[]`
- VCL constructors available: `TEdit`, `TPanel`, `TButton`, `TRadioButton`, `TCheckBox`, `TGroupBox`, `TText` (callable via `MT.__call`)
- **Not yet confirmed:** `TForm`, `TMemo`, `TListBox`, `TComboBox`, `TClipboard` — run option 8 (API Probe) to test

**`package.path` includes the plugin folder** — so any `.lua` file deployed alongside `main.lua` is loadable with `require("modulename")`.

**utilities module:** `require("utilities")` loads `Scripts/utilities.lua` and injects `table_print`, `read_calibration_table`, `read_calibration_tablename` as globals. Called in `main.lua` for the side-effect.

**Clipboard:** Use `io.popen('clip', 'w')` — see `debug.copy_to_clip()`.

**Data flow for export:**
1. `write_header()` → version/timestamp preamble
2. `export_cal.write_calibration()` → iterates `Calibration:table(i)`, dispatches per kind
3. `export_cal.write_dtcs()` → iterates `ErrorCodeList`
4. `export_dl.write_datalog()` → per log: stats (subsampled), then time-series at user resolution

**Import flow:** `import_mod.run(dry_run, cal_dir)` reads `tune_import.json`, decodes JSON, calls `apply_change()` per entry. Supports `Parameter`, `Table1D`, `Table2D`, `Table3D`. Cache cleared by event callbacks.

### Analyzer (`tools/tune_analyzer.py`)

Standalone Python/Tkinter GUI. Reads `tune_export.json`, extracts the `AFM flow` 1D table and time-series frames, bins S.TRIM by AFM voltage, and recommends corrected AFM flow values.

Requires: `pip install matplotlib numpy`

Run: `python tools/tune_analyzer.py`

Key functions: `load_export()` → `get_afm_table()` → `parse_timeseries()` → `analyze()` → `build_import()`. The `parse_timeseries()` function handles a FlashPro Lua sparse-table bug where nil-returning sensors are silently dropped, making rows shorter than `ts_cols`.

## JSON output format

`tune_export.json` structure:
```
export_version, plugin, timestamp, calibration_file, table_count,
tables[]  →  { name, unit, readonly, data: { kind, ...kind-specific fields } }
dtcs[]    →  { code, desc }
datalog   →  { count, logs[]: { file, frames, length_s, sensors{}, ts_cols[], ts[][] } }
```

Table `kind` values: `Parameter`, `Index`, `Table1D`, `Table2D`, `Table3D`

`tune_import.json` accepted kinds: `Parameter`, `Table1D`, `Table2D` only.

## Debug option (menu option 7)

Useful probe targets:
- `globals` — full `_G` scan
- `*` — dump all known interesting globals with methods
- `dialogs` — test `InputQuery`, `InputBox`, `MessageDlg` availability
- `clipboard` — test `clip.exe`, `Clipboard` global, PowerShell clipboard read
- `call:TEdit` — instantiate a VCL component and inspect its metatable

All debug output is: printed to console in full + copied to clipboard via `clip.exe` + shown in `ShowMessage` (first 80 lines).
