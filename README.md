# ExportTune — Hondata FlashPro AI Analysis Plugin

> **GitHub:** https://github.com/cybertza/flashpro-export-tune

A FlashPro plugin that exports your full calibration, datalog statistics and DTCs to a structured JSON file, making it straightforward to analyse your tune with AI assistants (Claude, ChatGPT, etc.) or custom tooling.

There is currently no open tool that bridges Hondata FlashPro calibrations and AI analysis. This plugin fills that gap.

---

## ⚠ Experimental — Read Before Use

**This plugin is experimental and community-developed. It is not affiliated with, endorsed by, or supported by Hondata Inc.**

- **Export functions** (read-only) carry no risk to your calibration and are safe to use at any time.
- **Import functions** (`import_changes`, `preview_import`) **write data back to your calibration.** Always run `preview_import` first. Always back up your `.fpcal` file before running `import_changes`. A bad import can produce an unsafe tune.
- AI-generated tune changes are suggestions only. **They must be reviewed by a qualified tuner before being applied to a car that will be driven.** An incorrect calibration can cause engine damage or create dangerous driving conditions.
- No warranty is provided. Use entirely at your own risk.

---

## Legal & Terms of Service

Hondata FlashPro includes an official plugin system with a documented Lua API. This plugin uses only that public API — it does not patch, reverse-engineer or bypass any part of the FlashPro software.

That said:

- **Check Hondata's current Terms of Service** before use. Hondata's ToS is available at [hondata.com](https://www.hondata.com). If their terms prohibit third-party plugins that write calibration data, do not use the import functions.
- This plugin **does not transmit any data** to external servers. All processing is local.
- Exporting your own calibration data is your right as the calibration owner. The export functions simply read and reformat data you already have access to in FlashPro.
- If you are a professional tuner, confirm that use of AI-assisted analysis tools is consistent with any warranties or agreements you have with your customers.

The authors of this plugin take no responsibility for engine damage, failed emissions tests, voided warranties, or any other consequences arising from its use.

---

## What it does

- Exports **all calibration tables** (Parameters, 1D/2D/3D maps) with axis labels, units and values
- Exports **datalog statistics** (min/max/mean per sensor) and a 200-sample time-series
- Exports **DTCs** (active fault codes)
- Prints a **key parameter summary** directly in the FlashPro console so you can see critical fuel settings at a glance
- Six separate menu entries for different workflows (see Usage below)

---

## Supported vehicles

Any Honda/Acura supported by Hondata FlashPro, including:

| Platform | Engine | Notes |
|----------|--------|-------|
| EP3/FN2 Civic Type R | K20Z4 | NA VTEC |
| FK2/FK8 Civic Type R | K20C1 | Turbocharged |
| Civic Si (8th gen) | K20Z3 | NA |
| Accord / TSX | K24 variants | |
| S2000 (with FlashPro) | F20C/F22C | |

If FlashPro supports it, the plugin will export it.

---

## Installation

1. Download or clone this repository
2. Copy the `ExportTune` folder into your FlashPro plugins directory:
   ```
   C:\Users\<you>\AppData\Local\Hondata\FlashPro\Plugins\ExportTune\
   ```
   The folder must contain both `info.xml` and `main.lua`.
3. Restart FlashPro — the plugin appears under the **Plugins** menu

---

## Usage

### Before running

- Load your calibration file (`.fpcal`) in FlashPro
- Optionally open a datalog: **Datalog → Open** → select your `.fpdl` file
  - Without a datalog loaded, calibration and DTC data is still exported

### Menu entries

| Menu item | What it does | Output file |
|-----------|-------------|-------------|
| **ExportTune** | Full export: calibration + datalog + DTCs | `tune_export.json` |
| **export_cal** | Calibration + DTCs only (faster, no datalog) | `tune_export_cal.json` |
| **export_datalog** | Datalog stats only (no table dump) | `tune_export_datalog.json` |
| **health_check** | Key parameters + sensor stats to console only | _(console only)_ |
| **preview_import** | Dry-run: shows what `tune_import.json` would change | _(console only)_ |
| **import_changes** | Applies `tune_import.json` changes to the calibration | _(modifies cal)_ |

Output files are written to the **same folder as your calibration file**.

---

## Output format

```json
{
  "export_version": "2.0",
  "plugin": "ExportTune",
  "timestamp": "2026-04-17 22:00:00",
  "calibration_file": "C:\\...\\MyTune.fpcal",
  "table_count": 300,
  "tables": [
    {
      "name": "Short term fuel trim maximum",
      "unit": "Percent",
      "readonly": false,
      "data": { "kind": "Parameter", "value": 25.0 }
    },
    {
      "name": "AFM flow",
      "unit": null,
      "readonly": false,
      "data": {
        "kind": "Table1D",
        "axis_name": "AFM voltage index",
        "axis_unit": "Volt",
        "axis": [0.0, 0.35, 0.43, ...],
        "values": [0.0, 0.13, 0.27, ...]
      }
    },
    {
      "name": "WOT lambda adjustment high",
      "unit": null,
      "readonly": false,
      "data": {
        "kind": "Table2D",
        "col_name": "MAP load",
        "col_unit": "Bar",
        "col_axis": [0.118, 0.204, ...],
        "row_name": "RPM",
        "row_unit": "RPM",
        "row_axis": [1000.0, 2000.0, ...],
        "rows": [[0.895, 0.895, ...], ...]
      }
    }
  ],
  "dtcs": [
    { "code": "P0420", "desc": "Catalyst efficiency below threshold" }
  ],
  "datalog": {
    "count": 1,
    "logs": [
      {
        "file": "C:\\...\\datalog0001.fpdl",
        "frames": 501231,
        "length_s": 2598.7,
        "sensors": {
          "RPM":   { "min": 863.0,  "max": 8465.0, "mean": 2949.25 },
          "S.TRIM":{ "min": -16.41, "max": 25.0,   "mean": 1.31    },
          "L.TRIM":{ "min": 0.0,    "max": 0.0,    "mean": 0.0     },
          "AF":    { "min": 13.2,   "max": 15.1,   "mean": 14.63   }
        },
        "ts_cols": ["time_s","RPM","AF","ECT","S.TRIM","L.TRIM","MAP","TPlate","IGN","AFM.v","K.Retard"],
        "ts": [[0.0, 850, 14.7, 85, 0.8, 0.0, 0.95, 12.0, 28.0, 1.42, 0.0], ...]
      }
    ]
  }
}
```

---

## Applying AI-suggested changes (import)

The import system lets an AI assistant generate a `tune_import.json` change-set that you apply directly into FlashPro — no manual table editing required.

### Workflow

```
Export → share with AI → AI returns tune_import.json → Preview → Apply
```

1. Run **ExportTune** to get `tune_export.json`
2. Share it with your AI assistant and describe the problem
3. Ask the AI to generate a `tune_import.json` with the fixes
4. Place `tune_import.json` in the **same folder as your calibration file**
5. Run **preview_import** to verify the changes in the console (no file touched)
6. Run **import_changes** to apply and save

### tune_import.json format

```json
{
  "description": "Fix STFT maximum and AFM flow glitch at index 4",
  "changes": [
    {
      "name": "Short term fuel trim maximum",
      "kind": "Parameter",
      "value": 25.0
    },
    {
      "name": "AFM flow",
      "kind": "Table1D",
      "values": [0.0, 0.0, 0.13, 0.27, 0.41, 0.35, 0.37, 0.61, 0.95, 1.36,
                 1.84, 2.44, 2.99, 3.52, 4.34, 5.24, 5.10, 5.65, 6.21, 7.13,
                 7.82, 7.96, 9.15, 10.54, 10.82, 12.3, 13.03, 13.5, 15.78,
                 16.72, 18.1, 19.73, 19.88, 20.99, 25.57, 26.97, 28.44, 30.93,
                 34.53, 38.44, 39.32, 44.22, 47.22, 53.88, 60.16, 62.51, 74.93,
                 78.26, 86.6, 98.73, 102.46, 108.14, 110.81, 113.5, 132.65,
                 137.58, 143.0, 149.8, 169.6, 219.28, 252.98, 282.37, 322.42, 327.67]
    },
    {
      "name": "WOT lambda adjustment high",
      "kind": "Table2D",
      "rows": [
        [0.895, 0.895, 0.895, ...],
        [0.870, 0.870, 0.860, ...]
      ]
    }
  ]
}
```

**Supported kinds:** `Parameter`, `Table1D`, `Table2D`

For `Table1D` the `values` array must match the existing table length exactly.
For `Table2D` the `rows` array must match rows × cols exactly.
Readonly tables are automatically skipped.

### Example AI prompt for generating an import file

> Here is my tune_export.json. Please generate a tune_import.json that:
> 1. Sets "Short term fuel trim maximum" to 25.0
> 2. Fixes the non-monotonic glitch in "AFM flow" at index 4 (currently 0.08, should interpolate to ~0.41)
>
> Return only the JSON, no explanation.

---

## Using with an AI assistant

Export the JSON then paste it — or describe it — to your AI assistant of choice.

### Example prompts

**Fuel economy diagnosis:**
> I have a Hondata FlashPro export from my Honda FN2 K20Z4. The car is running 17L/100km.
> Here is the tune export JSON: [paste or attach file]
> Please analyse the fuel-related tables and identify what may be causing excessive consumption.

**General tune review:**
> Review this FlashPro calibration export and flag any parameters outside normal ranges for a naturally aspirated K20 with aftermarket intake and throttle body.

**Datalog analysis:**
> My datalog shows S.TRIM mean = +1.31%, L.TRIM = 0%, RPM mean = 2949.
> Active Fuel Tuning is enabled. What does this tell me about how the ECU is managing fueling?

**AFM calibration check:**
> Here is my AFM flow table (voltage → kg/hr). Please check whether the curve is monotonically increasing and flag any anomalies that could cause fueling errors.

**Before/after comparison:**
> I have two exports — before and after an AFM recalibration for a J36 throttle body swap.
> Please compare the AFM flow tables and tell me whether the new calibration looks correct.

---

## Console output explained

When you run the full export, the console shows:

```
============================================================
  ExportTune v2.0  --  Full Export
============================================================
Calibration : C:\...\MyTune.fpcal
Tables      : 300

  [ 10%]  30/300  (Param) Short term fuel trim maximum
  [ 20%]  60/300  (1D)    AFM flow
  ...
  [100%] 300/300  (2D)    Cam angle high rpm

  Types: 142 Param  38 1D  87 2D  33 3D  0 errors

  ---- Key Calibration Parameters ----
  Injector size                             = 310.0
  Overall fuel trim                         = 0.0
  AFM enabled                               = 1.0
  Active fuel tuning enabled                = 1.0
  Closed loop target lambda                 = 0.9961
  Short term fuel trim maximum              = 47.08       <-- flag this if > 25
  Long term fuel trim maximum               = 25.39
  ------------------------------------

Datalogs loaded: 1
  Log 1/1: datalog0005.fpdl
    Frames: 501231  Duration: 2598.7s
    RPM         min=  863.00  max= 8465.00  mean= 2949.25
    S.TRIM      min=  -16.41  max=   25.00  mean=    1.31
    L.TRIM      min=    0.00  max=    0.00  mean=    0.00
    AF          min=   13.20  max=   15.10  mean=   14.63
    Sensors captured: 18/26
    Time-series samples: 201

============================================================
  DONE  -->  C:\...\tune_export.json
============================================================
```

---

## Known limitations

- **FlashPro caches plugin Lua at startup.** If you edit `main.lua`, restart FlashPro to pick up the changes.
- **SensorList is context-dependent.** Sensors not present in the loaded datalog are silently skipped (captured count will be < 26).
- **No write-back.** This plugin is read-only — it cannot modify calibration tables. Use FlashPro's built-in editor for any changes.
- Tested on FlashPro for K-series. Other FlashPro variants (S2000, etc.) may have different table counts or sensor names.

---

## Contributing

Pull requests welcome. Areas that would benefit from contributions:

- **Analysis scripts** — Python/JS scripts that read `tune_export.json` and flag common issues automatically
- **Comparison tool** — diff two exports to show what changed between calibration versions
- **Additional sensor names** — if your platform uses different sensor identifiers, add them to `SENSORS` in `main.lua`
- **Testing on other platforms** — EP3, FK8, S2000 — report any issues

---

## License

MIT License — see [LICENSE](LICENSE)
