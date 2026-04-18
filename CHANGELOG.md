# Changelog

## v4.0 (2026-04-18)
- Replaced 6 separate menu entries with a single `main()` that shows an `InputQuery` dialog menu
- Dialog shows current calibration filename and datalog count as context before you choose
- Action 6 (Apply Import) requires typing `YES` in a second confirmation dialog
- `ShowMessage` popup on export completion and on import errors
- Added `OnDatalogOpen`, `OnCalibrationOpen`, `OnCalibrationNew` event callbacks
- `OnCalibrationOpen/New` invalidates the name→index cache automatically
- `setvalue` argument order corrected to `(value, index)` per official API docs

## v3.0 (2026-04-17)
- Added `preview_import` and `import_changes` entry points
- Built-in lightweight JSON parser (no external dependencies)
- Import supports Parameter, Table1D and Table2D changes
- Readonly tables automatically skipped during import
- Fallback output path now tries Windows Downloads folder via `io.popen`
- Updated GitHub URL to https://github.com/cybertza/flashpro-export-tune
- `Calibration:update()` called automatically after successful import

## v2.0 (2026-04-17)
- Added four separate menu entries: Full Export, Calibration Only, Datalog Only, Health Check
- All `SensorList[]` lookups wrapped in `pcall` — no crash if sensor not in datalog
- All `dl:value()` calls wrapped in `pcall` — graceful handling of missing frames
- Per-table progress logging every 10 tables with name and type
- Key fuel parameter summary printed to console after calibration export
- Verbose sensor stats in console (RPM, S.TRIM, L.TRIM, AF, MAP, ECT, IGN, K.Retard)
- Output filename varies by entry point (`tune_export`, `tune_export_cal`, `tune_export_datalog`)
- Added `plugin` and `export_version` fields to JSON output
- Added README, LICENSE, CHANGELOG

## v1.0 (2026-04-17)
- Initial release
- Full calibration export (Parameters, 1D/2D/3D tables)
- Datalog stats (min/max/mean, 200-sample time-series)
- DTC export
- Output written to calibration file directory
