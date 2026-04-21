# Copilot Instructions — ExportTune

## What this is

A Hondata FlashPro Lua plugin + Python analysis tool. The plugin (`ExportTune/main.lua`) runs inside FlashPro's sandboxed Lua environment. The analyzer (`tools/tune_analyzer.py`) is a standalone Python/Tkinter GUI.

## After editing main.lua

Run `deploy.bat` (Windows) or copy manually to `%LOCALAPPDATA%\Hondata\FlashPro\Plugins\ExportTune\`, then restart FlashPro. The plugin is cached at startup.

## Lua environment constraints

FlashPro exposes a restricted Lua 5.x environment. Available globals:
- `Calibration`, `DatalogManager`, `SensorList`, `ErrorCodeList`
- `Constants` via `require("constants")` — table kinds and unit name map
- `ShowMessage(str)`, `InputQuery(title, prompt, default)` — only dialog functions available
- `io.open`, `io.popen`, `os.date`, `os.time` — standard Lua I/O works
- VCL constructors: `TEdit`, `TPanel`, `TButton`, `TRadioButton`, `TCheckBox`, `TGroupBox`, `TText`
- **No:** `TForm`, `TMemo`, `TListBox`, `TComboBox`, clipboard globals, `require("utilities")`
- **Clipboard:** use `io.popen('clip', 'w')` to write to Windows clipboard

No external Lua libraries. The plugin has its own minimal JSON parser.

## Version

`VERSION` in `main.lua` uses `yymmdd.rev` scheme. Update for every change.

## Plugin entry point

`main()` is called by FlashPro. It shows an `InputQuery` menu (1–7). Export options ask for time-series sample count before writing (`ask_sample_count()`).

## Import safety

`tune_import.json` writes back to the calibration. Always use option 5 (preview) before option 6 (apply). Only `Parameter`, `Table1D`, `Table2D` kinds are supported for import.
