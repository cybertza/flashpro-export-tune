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
cp ExportTune/main.lua "$LOCALAPPDATA/Hondata/FlashPro/Plugins/ExportTune/main.lua"
cp ExportTune/info.xml "$LOCALAPPDATA/Hondata/FlashPro/Plugins/ExportTune/info.xml"
```

Live plugin folder: `C:\Users\<you>\AppData\Local\Hondata\FlashPro\Plugins\ExportTune\`

## Version scheme

`VERSION` in `main.lua` follows `yymmdd.rev` (e.g. `260421.1`). Increment `.rev` for same-day releases. Update it for every commit that touches `main.lua`.

## Architecture

### Plugin (`ExportTune/main.lua`)

Single-file Lua plugin. Entry point is `main()`, called by FlashPro when the user clicks the plugin menu item. Presents an `InputQuery` dialog menu (options 1–7).

**Key globals provided by FlashPro:**
- `Calibration` — `.loaded()`, `.filename()`, `.table(i)`, `.tablecount()`, `.update()`
- `DatalogManager` — `.count()`, `.datalog(i)`
- `SensorList` — `.count()`, `.sensor(i)`, and `SensorList["RPM"]` via `MT.__index`
- `ErrorCodeList` — `.count()`, `.code(i)`
- `Constants` — from `require("constants")` — provides `Constants.TableKind.*` and `Constants.UnitName[]`
- VCL constructors available: `TEdit`, `TPanel`, `TButton`, `TRadioButton`, `TCheckBox`, `TGroupBox`, `TText` (callable via `MT.__call`)
- **Not available:** `TForm`, `TMemo`, `TListBox`, `TComboBox`, `TClipboard`, `Clipboard`, `utilities`

**Clipboard:** No VCL clipboard API is exposed. Use `io.popen('clip', 'w')` to write to the Windows clipboard — see `copy_to_clip()`.

**No external Lua libraries.** The plugin includes its own minimal JSON parser (`json.decode`) since FlashPro provides no JSON built-in.

**Data flow for export:**
1. `write_header()` → version/timestamp preamble
2. `write_calibration()` → iterates `Calibration:table(i)` for all tables, dispatches to `dump_parameter/dump_index/dump_1d/dump_2d/dump_3d`
3. `write_dtcs()` → iterates `ErrorCodeList`
4. `write_datalog()` → for each loaded log: stats via `stats()` (subsampled), then time-series at user-chosen resolution via `dump_datalogs(verbose, max_samples)`

**Time-series resolution** is asked via `InputQuery` at export time (default 2000 samples). The step is `math.floor(framecount / max_samples)`. `ts_cols` is built dynamically from whichever `TS_SENSORS` are present in the log.

**Import flow:** `run_import(dry_run)` reads `tune_import.json` from the calibration directory, decodes with `json.decode`, then calls `apply_change()` per entry. `build_cal_index()` caches a name→table-index map (invalidated by `OnCalibrationOpen/New`).

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
