# FlashPro LUA API — Discovery Notes

Compiled from reverse-engineering the Scripts directory at  
`%LOCALAPPDATA%\Hondata\FlashPro\Scripts\`,  
from runtime behaviour in `ExportTune/main.lua`,  
and from **live probe results** run on FlashPro 4.6.6.0 build 5835 (32-bit) on 2026-04-21.  
Probe-confirmed entries are marked ✓. Unconfirmed entries are unmarked.

---

## 1. Lua Environment ✓ probe-confirmed

- **Lua version:** 5.4 ✓
- **`package.path`** ✓ — contains `C:\Users\...\Hondata\FlashPro\Scripts\?.lua` plus the  
  ExportTune plugin dir (added by our `setup_modules()` at startup). Sibling `.lua` files  
  placed in the plugin folder are loadable via `require("modulename")`.
- **`io.open`** ✓ writable to arbitrary paths (tested with `C:\Users\Public\Documents\`)
- **`io.popen`** ✓ — `clip.exe` write and PowerShell read both work
- **`os.date`** ✓, **`os.time`** (untested but expected), **`math.*`** ✓, **`string.*`** ✓, **`table.*`** ✓
- **`os.getenv`** ✗ nil — not exposed in sandbox. Use `io.popen('echo %VAR%')` instead.
- **`dofile`** ✗ nil — dynamic file loading blocked
- **`loadfile`** ✗ nil — blocked
- **`load`** ✗ nil — blocked
- **`utf8`** ✓ standard library available
- **`package.loaded`** ✗ nil — module cache not exposed; can't clear it for hot-reload
- **`package.path`** ✓ read/write — can append entries at startup
- **`debug` library** — `require("debug")` returns the standard Lua debug library.  
  **Never name a plugin module `debug`** (or `io`, `os`, `math`, `string`, `table`, `package`,  
  `coroutine`, `utf8`) — it will silently return the builtin instead of your file.
- No external LuaRocks packages.

---

## 2. Plugin Sandboxing — Dialog API ✓ probe-confirmed

**Available dialogs (complete list):**

| Function | Returns | Notes |
|----------|---------|-------|
| `InputQuery(caption, prompt, default)` ✓ | string or nil (cancel) | Only multi-purpose dialog |
| `ShowMessage(text)` ✓ | void | Display only |

**All other dialogs MISSING (probe-confirmed):**  
`InputBox`, `MessageDlg`, `MessageDlgPos`, `MessageDlgPosHelp`, `QuestionDlg`,  
`TaskMessageDlg`, `TaskMessageDlgPos`, `CreateMessageDialog`, `SelectDirectory`,  
`PromptForFileName` — all nil.

**VCL constructors — instantiable but zero methods (probe-confirmed):**

| Class | Status |
|-------|--------|
| `TEdit` ✓ | instantiates, **0 methods** |
| `TPanel` ✓ | instantiates, **0 methods** |
| `TButton` ✓ | instantiates, **0 methods** |
| `TRadioButton` ✓ | instantiates, **0 methods** |
| `TCheckBox` ✓ | instantiates, **0 methods** |
| `TGroupBox` ✓ | instantiates, **0 methods** |
| `TText` ✓ | instantiates, **0 methods** |
| `TLabel` ✗ | MISSING |
| `TBitBtn` ✗ | MISSING |
| `TForm` ✗ | MISSING |
| `TMemo` ✗ | MISSING |
| `TListBox` ✗ | MISSING |
| `TComboBox` ✗ | MISSING |
| `TStringList` ✗ | MISSING |
| `TTimer` ✗ | MISSING |
| `TImage` ✗ | MISSING |
| `TScrollBox` ✗ | MISSING |
| `TPageControl` ✗ | MISSING |
| `TTabSheet` ✗ | MISSING |
| `TTrackBar` ✗ | MISSING |
| `TProgressBar` ✗ | MISSING |
| `TSpinEdit` ✗ | MISSING |
| `TColorButton` ✗ | MISSING |

**`MT.__index` is a FUNCTION** (confirmed probe 2026-04-21) — not a table.  
Properties are accessible AND settable via the `__index`/`__newindex` metamethods.  
Confirmed readable properties per class:

| Class | Readable properties |
|-------|---------------------|
| TEdit | Text, Width, Height |
| TPanel | Caption, Width, Height, Color |
| TButton | Caption, Width, Height, Color |
| TRadioButton | Caption, Width, Height |
| TCheckBox | Caption, Width, Height |
| TGroupBox | Caption, Width, Height, Color |
| TText | Text, Width, Height |

**Controls created with `nil` owner ARE displayed** in the Plugin Interface "Plugin" tab  
automatically. FlashPro hosts any VCL component created during plugin execution in the  
plugin's allocated GUI panel. Controls persist until plugin reloads (GC'd on unload).

**Still unknown (needs testing):**
- Can `Left` / `Top` be set for positioning?
- Can `Parent` be set to nest controls (e.g. TButton inside TPanel)?
- Can `OnClick` be set to a Lua function for button events?
- Can `Text` / `Caption` be set (write), not just read?

**Two tabs in Plugin Interface:**
- `ExportTune` tab — console/print() output area (FlashPro-owned TMemo)
- `Plugin` tab — auto-hosted VCL controls created with nil owner

**Design implication:** A real UI panel IS buildable using TPanel, TButton, TGroupBox,  
TEdit, TText, TCheckBox. The critical unknowns are positioning and event handling.

**`print()` behaviour — critical:**  
Every `print()` call opens the **Plugin Interface** window. Closing that window  
**deregisters all plugins** until FlashPro is restarted. Rules:
- ✓ Use `print()` freely during export operations (options 1–3) — the user expects console output
- ✗ Never call `print()` from event callbacks (`OnCalibrationOpen`, `OnDatalogOpen`)
- ✗ Never call `print()` from options 4/8 (health check, probe) — use ShowMessage + clipboard

**Clipboard:**  
- Write: `io.popen('clip', 'w')` ✓  
- Read: `io.popen('powershell -NoProfile -Command "Get-Clipboard"')` ✓

---

## 3. Calibration API (`Calibration`) ✓ probe-confirmed

```lua
Calibration:loaded()            -- bool ✓
Calibration:filename()          -- string, full path to .fpcal ✓
Calibration:tablecount()        -- integer ✓
Calibration:table(i)            -- table object (1-based index) ✓
Calibration:table(name)         -- table object by string name ✓ CONFIRMED
                                --   e.g. Calibration:table("Short term fuel trim maximum")
                                --   returns nil if name not found
Calibration:update()            -- save calibration to disk ✓
```

**`Calibration:table(string)` is confirmed working.** This eliminates the need to build  
a name→index cache for the import system. Use it for direct lookups by name.

### Table Object Methods

```lua
t:name()                        -- string, display name
t:kind()                        -- integer, see TableKind enum
t:unit()                        -- integer, see Unit enum
t:type()                        -- integer, see Type enum
t:readonly()                    -- bool
t:length()                      -- row count (rows for 2D, values for 1D)
t:size()                        -- total element count
t:value(...)                    -- get value; args: (), (i), (col,row), (col,row,page)
t:setvalue(val, ...)            -- set value; same index args as value()
t:index(dim)                    -- axis object for dimension 1/2/3
```

### Axis (Index) Object Methods

```lua
ax:name()                       -- string, axis label e.g. "RPM", "MAP load"
ax:unit()                       -- integer, Unit enum
ax:type()                       -- integer, Type enum
ax:length()                     -- number of breakpoints
ax:value(i)                     -- breakpoint value at 1-based index i
```

### setvalue Argument Order (confirmed working)

| Kind | Call |
|------|------|
| Parameter | `t:setvalue(val)` |
| Table1D | `t:setvalue(val, i)` |
| Table2D | `t:setvalue(val, col, row)` |
| Table3D | `t:setvalue(val, col, row, page)` |

---

## 4. DatalogManager API

```lua
DatalogManager:count()          -- number of loaded datalogs
DatalogManager:datalog(i)       -- datalog object (1-based)
```

### Datalog Object

```lua
dl:filename()                   -- string, full path to .fpdl
dl:framecount()                 -- total sample frames
dl:length()                     -- duration in seconds
dl:sensorcount()                -- sensors recorded in this log
dl:timestamp(frame)             -- time in seconds for frame number
dl:framenumber(time_s)          -- frame index at given time
dl:value(sensor_obj, frame)     -- float; sensor_obj comes from SensorList
```

---

## 5. SensorList API

```lua
SensorList:count()              -- total available sensors
SensorList:sensor(i)            -- sensor by 1-based index
SensorList["RPM"]               -- sensor by name (MT __index lookup)
SensorList[0]                   -- sensor by 0-based index (alternative)
```

### Sensor Object

```lua
s:name()                        -- string identifier
s:unit()                        -- Unit enum
s:type()                        -- Type enum
s:min()                         -- minimum physical value
s:max()                         -- maximum physical value
s:live()                        -- bool, has live ECU data
```

**Caution:** A sensor may exist in `SensorList` but return `nil` for frames in a given  
datalog if it was not recorded. Wrap all `dl:value()` calls in `pcall`.

---

## 6. ErrorCodeList API

```lua
ErrorCodeList:count()           -- number of active DTCs
ErrorCodeList:code(i)           -- DTC object (1-based)
```

### DTC Object

```lua
dtc:code()                      -- string e.g. "P0420"
dtc:description()               -- string, human-readable
```

---

## 7. Event Callbacks

FlashPro calls these global functions automatically if defined:

| Callback | Trigger |
|----------|---------|
| `OnCalibrationOpen()` | User opens a .fpcal file |
| `OnCalibrationNew()` | New/blank calibration created |
| `OnDatalogOpen()` | User opens a .fpdl file |

Use to invalidate caches (e.g. `cal_index_cache = nil`).

---

## 8. Constants Module (`require("constants")`)

### TableKind Enum

| Name | Value | Shape |
|------|-------|-------|
| `Parameter` | 0 | single scalar |
| `Index` | 1 | 1D array, no interpolation |
| `Table1D` | 2 | 1D lookup with X-axis |
| `Table2D` | 3 | 2D map, col × row |
| `Table3D` | 4 | 3D cube, col × row × page |

Access: `Constants.TableKind.Table2D` → `3`, `Constants.TableKindName[3]` → `"Table2D"`.

### Type Enum (0–27)

`AirFuelRatio` `Angle` `Boolean` `Current` `FuelStatus` `LinearSpeed` `Number`  
`Percent` `Pressure` `RotationSpeed` `Temperature` `Time` `Voltage` `Raw`  
`Binary` `Resistance` `Analog` `Volume` `MassFlow` `Mass` `VolumeFuel`  
`Consumption` `Torque` `Distance` `Force` `Acceleration` `RotationChange` `Frequency`

### Unit Enum (0–45) — key entries

| ID | Name | Symbol |
|----|------|--------|
| 0 | AirFuel | afr |
| 1 | Lambda | λ |
| 3 | Percent | % |
| 7 | PSI | psi |
| 10 | KPA | kPa |
| 12 | TempC | °C |
| 13 | TempF | °F |
| 14 | MS | ms |
| 15 | RPM | rpm |
| 18 | Volt | V |
| 25 | GSecond | g/s |
| 34 | Torque_NM | Nm |
| 42 | G | g |

Full list in `constants.lua`. Access: `Constants.UnitName[unit_id]` → name string,  
`Constants.UnitUnit[unit_id]` → symbol string.

---

## 9. Known Sensor Names (68 total)

### Engine & Airflow
`RPM` `VSS` `MAP` `BP` `TPlate` `TPedal` `AFM` `AFM.v` `AFM Hz`
`IAT` `IAT2` `ECT` `ECT2` `IGN` `CAM` `CAMCMD` `EXCAM` `PA`

### Fuel Trims & Wideband
`AF` `AF Bank 2` `AF.Corr` `Wide` `Wide.V` `AFCMD` `AFCMD Bank 2`
`S.TRIM` `L.TRIM` `S.TRIM Bank 2` `L.TRIM Bank 2` `Trim`
`Fuel Status` `Fuel Status Bank 2` `Ethanol`
`INJ` `INJ Bank 2` `DUTY` `DIFP` `DIFPCMD` `FuelP`

### Valve / Boost / Emissions
`AIRC` `EGR` `Purge` `VTS` `SVS` `WG` `WGCMD` `ACCL`

### Knock (overall + per-cylinder)
`K.Level` `K.Retard` `K.Retard.1` `K.Retard.2` `K.Retard.3` `K.Retard.4`
`K.Control` `Ign.Limit` `K.Count` `K.Count.1` `K.Count.2` `K.Count.3`

### Vehicle Dynamics
`Gear` `G.Lat` `G.Long` `G.Z` `Yaw`
`ABS.LF` `ABS.RF` `ABS.LR` `ABS.RR`
`Clutch.Pos` `Brake.Press` `Steer Ang` `Steer Trq`

### Traction Control
`TC.V` `TC.ECUSlip` `TC.R` `TC.LF` `TC.RF` `TC.LR` `TC.RR`
`TC.Slip` `TC.Turn` `TC.OverSlip` `TC.Out`

### Torque & AIRC Management
`Trq Req` `Act Trq` `trq_max` `airc_max` `airc_red` `airc_prot` `airc_comp`

### Electrical & Thermal
`BAT` `Oil.Press` `CVT.Temp` `Cat.T` `Fuel Used` `BC Duty`

---

## 10. Known Calibration Table Names (selected)

### Fuel System Parameters
`Injector size` `Overall fuel trim` `AFM enabled` `Active fuel tuning enabled`
`Use speed/density (MAP) fuel tables` `Closed loop` `Open loop`
`Closed loop target lambda`
`Short term fuel trim maximum` / `minimum`
`Long term fuel trim maximum` / `minimum`

### Fuel Tables
`AFM flow` (1D — AFM voltage → g/s)
`WOT lambda adjustment high` / `low` (2D)
`Lean best torque` (2D)

### Ignition
`Ignition Low` (2D)

### Cam / VTC
`Cam angle low speed` (2D)

### Boost / TC
`TC max boost(IAT2)` (3D)

### Idle
`Idle speed (normal)` (1D)
`Idle speed ECT index (normal)` (Index)

### Speed Limiter
`Speed limiter speed` (Parameter)

---

## 11. Multi-File Plugin Architecture — Confirmed Viable

`package.path` includes the plugin folder. Each `.lua` file placed alongside `main.lua`  
in `Plugins/ExportTune/` is loadable with `require("modulename")`.

`deploy.bat` must be updated to copy all `.lua` files:

```bat
xcopy /Y /I "%SRC%\*.lua" "%DST%\" >nul
```

### Proposed Module Split

| File | Responsibility |
|------|----------------|
| `main.lua` | Entry point, `main()` menu, event callbacks, version constant |
| `json.lua` | `esc()`, `num()`, `json.decode()` — no FlashPro API dependencies |
| `export_cal.lua` | `dump_parameter/index/1d/2d/3d`, `write_calibration`, `write_dtcs`, key-params |
| `export_datalog.lua` | `SENSORS`, `TS_SENSORS`, `stats()`, `dump_datalogs`, `write_datalog`, sample dialog |
| `import.lua` | `build_cal_index`, `apply_change`, `run_import` |
| `health.lua` | `do_health_check`, `print_cal_summary` |
| `debug.lua` | `do_debug`, `dump_global`, `INTERESTING_GLOBALS`, `copy_to_clip` |

Each module returns a table of its public functions. `main.lua` composes them:

```lua
local json         = require("json")
local export_cal   = require("export_cal")
local export_dl    = require("export_datalog")
local import_mod   = require("import")
local health       = require("health")
local dbg          = require("debug")
```

---

## 12. Sparse-Table Bug (Datalog Time-Series)

When `dl:value()` returns `nil` for a sensor in a given frame, Lua's table serialiser  
silently drops the element, making that row shorter than `ts_cols` declares.  
Current mitigation: every cell is wrapped in `pcall` and emits `"null"` on failure.  
The Python analyzer also cross-checks `ts_cols` against sensors that have stats entries.

---

## 13. Application / Device / ECU Objects ✓ probe-confirmed

```lua
-- All fields below confirmed on FlashPro 4.6.6.0 build 5835 (32-bit), 2026-04-21

Application.app          -- "FlashPro" ✓
Application.version      -- "4.6.6.0" ✓
Application.build        -- 5835 ✓
Application.compiledate  -- "Thursday, April 2, 2026 4:19 PM" ✓
Application.bit64        -- false (32-bit binary, even on 64-bit OS) ✓
Application.os           -- "Windows 11 Professional (build 26200), 64-bit" ✓
Application.locale       -- "en" ✓

Device.name              -- "FlashPro" ✓
Device.connected()       -- true ✓  (device was connected during test)
Device.obdiivoltage()    -- 0.0 ✓   (ignition off)
Device.hardware()        -- 1 ✓
Device.serial()          -- 23284 ✓
Device.vinlocked()       -- true ✓
Device.datalogcount()    -- 0 ✓
Device.isdatalogging     -- NOTE: returns as callable userdata, not plain function
Device.isrecording       -- NOTE: same — call as Device:isdatalogging() not Device.isdatalogging()

ECU.ignitionon()         -- false ✓  (ignition was off during test)
ECU.recoverymode()       -- false ✓
```

## 14. utilities Module ✓ probe-confirmed

`require("utilities")` loads `Scripts/utilities.lua` and injects these as **globals**:

```lua
table_print(tbl, indent)                    -- ✓ function
read_table_indexes(table, idx_count)        -- ✓ function
read_calibration_table(table)               -- ✓ function  returns Lua table with .kind .unit etc.
read_calibration_tablename(name)            -- ✓ function  confirmed: kind=0 unit=Percent for "Short term fuel trim maximum"
```

The module also returns a table with the same functions, but the globals are the reliable interface.

## 15. Sandbox Rules Summary (confirmed 2026-04-21)

| Feature | Status |
|---------|--------|
| `InputQuery` | ✓ available |
| `ShowMessage` | ✓ available |
| All other dialogs | ✗ missing |
| VCL constructors (TEdit etc.) | ✓ instantiable but 0 methods — not useful |
| TForm / TMemo / TListBox / TComboBox | ✗ missing |
| `print()` | ⚠ opens Plugin Interface window — closing it deregisters plugins |
| `io.open` | ✓ read + write |
| `io.popen` | ✓ clip.exe + PowerShell |
| `os.date` | ✓ |
| `os.getenv` | ✗ nil |
| `dofile` / `loadfile` / `load` | ✗ all nil |
| `utf8` | ✓ |
| `package.path` | ✓ read/write |
| `package.loaded` | ✗ nil |
| `Calibration:table(string)` | ✓ name-based lookup works |
| `utilities` globals | ✓ all 4 injected |
| `require("debug")` | ⚠ returns Lua builtin — rename your module |
