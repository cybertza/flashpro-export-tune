--
-- ExportTune — Hondata FlashPro Plugin
-- Exports calibration tables, datalog stats and DTCs to JSON for AI analysis.
-- Imports a change-set JSON to apply targeted calibration edits.
--
-- GitHub: https://github.com/cybertza/flashpro-export-tune
-- License: MIT
--

local VERSION = "260421.2"

-- ── package path + module cache setup ────────────────────────────────────────
-- Must run before any require() of our own sibling modules.
-- FlashPro adds Scripts/ to package.path (so constants/utilities work), but
-- the plugin folder may not be included — we add it explicitly.
-- We also clear our module cache so that plugin reload picks up fresh files
-- rather than stale cached versions from the previous load.

local function setup_modules()
  -- os.getenv is not available in the FlashPro sandbox; use io.popen to resolve %LOCALAPPDATA%
  local appdata = nil
  local ok, h = pcall(io.popen, 'echo %LOCALAPPDATA%')
  if ok and h then
    local line = h:read('*l')
    h:close()
    if line and line ~= '' and line ~= '%LOCALAPPDATA%' then
      appdata = line:gsub('%s+$', '')
    end
  end

  if appdata then
    local plugin_dir = appdata .. "\\Hondata\\FlashPro\\Plugins\\ExportTune"
    local entry = plugin_dir .. "\\?.lua"
    if not package.path:find(entry, 1, true) then
      package.path = package.path .. ";" .. entry
    end
  end

  -- clear our own module cache so reloads get fresh files
  -- package.loaded may be nil in the FlashPro sandbox; guard before accessing
  if package.loaded then
    for _, m in ipairs({"json","export_cal","export_datalog","import","health","probe","dbgtools","gui_test","gui_main"}) do
      package.loaded[m] = nil
    end
  end
end

setup_modules()

-- ── load all modules — errors surface in main() rather than killing the plugin
local Constants, export_cal, export_dl, import_mod, health_mod, probe_mod, dbg, gui_test, gui_main
local _modules_ok, _modules_err = pcall(function()
  Constants  = require("constants")
  require("utilities")  -- side-effect: injects table_print, read_calibration_table etc.
  export_cal = require("export_cal")
  export_dl  = require("export_datalog")
  import_mod = require("import")
  health_mod = require("health")
  probe_mod  = require("probe")
  dbg        = require("dbgtools")
  gui_test   = require("gui_test")
  gui_main   = require("gui_main")
end)

-- ── output path helpers ───────────────────────────────────────────────────────

local function get_cal_dir()
  if Calibration:loaded() then
    local cal = Calibration:filename()
    local dir = cal:match("^(.+)\\[^\\]+$") or cal:match("^(.+)/[^/]+$")
    if dir then return dir end
  end
  return nil
end

local function get_downloads_dir()
  local ok, result = pcall(function()
    local h = io.popen('echo %USERPROFILE%')
    if h then
      local line = h:read('*l')
      h:close()
      if line and line ~= '' and line ~= '%USERPROFILE%' then
        return line:gsub('%s+$','') .. '\\Downloads'
      end
    end
  end)
  return (ok and result) or nil
end

local function get_out_file(suffix)
  suffix = suffix or "tune_export"
  local dir = get_cal_dir() or get_downloads_dir()
  if dir then return dir .. "\\" .. suffix .. ".json" end
  return "C:\\Users\\Public\\Documents\\" .. suffix .. ".json"
end

-- ── console helpers ───────────────────────────────────────────────────────────

local function banner(title)
  local cal = Calibration:loaded()
    and ("  Cal: " .. (Calibration:filename():match("[^\\]+$") or "loaded")) or ""
  print("============================================================")
  print("  ExportTune v" .. VERSION .. "  --  " .. title)
  print("  github.com/cybertza/flashpro-export-tune" .. cal)
  print("  Not affiliated with or endorsed by Hondata Inc.")
  print("============================================================")
end

local function done(path, cal_info, dtc_count, dl_info)
  local summary = {}
  if cal_info then
    summary[#summary+1] = string.format(
      "Tables : %d  (%d Param  %d 1D  %d 2D  %d 3D%s)",
      cal_info.total, cal_info.params, cal_info.t1d, cal_info.t2d, cal_info.t3d,
      cal_info.errors > 0 and "  "..cal_info.errors.." err" or "")
  end
  if dtc_count then
    summary[#summary+1] = string.format("DTCs   : %d", dtc_count)
  end
  if dl_info then
    if dl_info.logs > 0 then
      summary[#summary+1] = string.format(
        "Datalog: %d log(s)  %d frames  %d samples",
        dl_info.logs, dl_info.frames, dl_info.samples)
    else
      summary[#summary+1] = "Datalog: none loaded"
    end
  end
  local summary_str = #summary > 0 and ("\n" .. table.concat(summary, "\n")) or ""
  print("")
  print("============================================================")
  print("  DONE  -->  " .. path)
  if #summary > 0 then
    for _, l in ipairs(summary) do print("  " .. l) end
  end
  print("============================================================")
  ShowMessage("ExportTune: Export complete!\n\n" .. path .. summary_str)
end

-- ── write header ─────────────────────────────────────────────────────────────

local function write_header(f)
  f:write('{\n')
  f:write('"export_version":"' .. VERSION .. '",\n')
  f:write('"plugin":"ExportTune",\n')
  f:write('"github":"https://github.com/cybertza/flashpro-export-tune",\n')
  f:write('"timestamp":"' .. os.date("%Y-%m-%d %H:%M:%S") .. '",\n')
end

-- ── action implementations ────────────────────────────────────────────────────

local function do_full_export()
  banner("Full Export")
  local max_samples = export_dl.ask_sample_count()
  if max_samples == nil then print("Cancelled."); return end
  local OUT = get_out_file("tune_export")
  print("Output: " .. OUT .. "\n")
  local f = io.open(OUT, "w")
  if not f then ShowMessage("ERROR: Cannot write to:\n" .. OUT); return end
  write_header(f)
  local cal_info  = export_cal.write_calibration(f, true)
  local dtc_count = export_cal.write_dtcs(f)
  local dl_info   = export_dl.write_datalog(f, true, max_samples)
  f:write('}\n')
  f:close()
  done(OUT, cal_info, dtc_count, dl_info)
end

local function do_export_cal()
  banner("Export Calibration Only")
  local OUT = get_out_file("tune_export_cal")
  print("Output: " .. OUT .. "\n")
  local f = io.open(OUT, "w")
  if not f then ShowMessage("ERROR: Cannot write to:\n" .. OUT); return end
  write_header(f)
  local cal_info  = export_cal.write_calibration(f, true)
  local dtc_count = export_cal.write_dtcs(f)
  f:write('"datalog":{"count":0,"logs":[]}\n}\n')
  f:close()
  done(OUT, cal_info, dtc_count, nil)
end

local function do_export_datalog()
  banner("Export Datalog Only")
  local max_samples = export_dl.ask_sample_count()
  if max_samples == nil then print("Cancelled."); return end
  local OUT = get_out_file("tune_export_datalog")
  print("Output: " .. OUT .. "\n")
  local f = io.open(OUT, "w")
  if not f then ShowMessage("ERROR: Cannot write to:\n" .. OUT); return end
  write_header(f)
  if Calibration:loaded() then
    f:write('"calibration_file":"' .. Calibration:filename():gsub('\\','\\\\') .. '",\n')
  else
    f:write('"calibration_file":null,\n')
  end
  f:write('"table_count":0,"tables":[],\n')
  local dtc_count = export_cal.write_dtcs(f)
  local dl_info   = export_dl.write_datalog(f, true, max_samples)
  f:write('}\n')
  f:close()
  done(OUT, nil, dtc_count, dl_info)
end

local function do_health_check()
  health_mod.run()
end

local function do_preview_import()
  banner("Preview Import (dry run)")
  print("")
  local buf = {}
  local orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    local line = table.concat(parts, '\t')
    orig_print(line)
    buf[#buf+1] = line
  end

  import_mod.run(true, get_cal_dir())

  print = orig_print
  print("")
  print("  DRY RUN complete  (calibration unchanged)")
  print("============================================================")

  local MAX_LINES = 60
  if #buf > MAX_LINES then
    local kept = {}
    for i = 1, MAX_LINES do kept[i] = buf[i] end
    kept[#kept+1] = "... (" .. (#buf - MAX_LINES) .. " more lines — see console)"
    buf = kept
  end
  ShowMessage("ExportTune — Import Preview (dry run)\nNo changes applied.\n\n" ..
    table.concat(buf, '\n'))
end

local function do_import_changes()
  banner("Import Changes  [EXPERIMENTAL]")
  print("")
  print("  !! WRITE OPERATION — calibration will be modified !!")
  print("  Ensure you have a backup of your .fpcal file.")
  print("")
  import_mod.run(false, get_cal_dir())
  print("")
  print("  Import complete")
  print("============================================================")
end

local function do_debug()
  banner("Debug: Global Dump")
  dbg.run()
end

local function do_probe()
  -- no banner() here — banner calls print() which opens Plugin Interface window
  probe_mod.run(function(text) dbg.copy_to_clip(text) end)
end

local function do_gui_main()
  gui_main.run(
    get_cal_dir,
    -- export dispatcher
    function(mode)
      if     mode == "full" then do_full_export()
      elseif mode == "cal"  then do_export_cal()
      elseif mode == "dl"   then do_export_datalog()
      end
    end,
    -- import dispatcher
    function(dry_run, cal_dir) import_mod.run(dry_run, cal_dir) end,
    -- health dispatcher
    function() health_mod.run() end,
    -- tools
    {
      probe    = function() probe_mod.run(function(t) dbg.copy_to_clip(t) end) end,
      debug    = function() dbg.run() end,
      gui_test = function() gui_test.run() end,
    }
  )
end

-- ── text menu (called by "Open Menu" button in GUI) ──────────────────────────

function show_menu()
  local cal_name = Calibration:loaded()
    and Calibration:filename():match("[^\\]+$") or "(no calibration)"
  local dl_count = DatalogManager:count()

  local prompt = string.format(
    "ExportTune v%s\n" ..
    "github.com/cybertza/flashpro-export-tune\n\n" ..
    "Cal      : %s\n" ..
    "Datalogs : %d loaded\n\n" ..
    "  1 = Full Export  (cal + datalog + DTCs)\n" ..
    "  2 = Calibration Only\n" ..
    "  3 = Datalog Only\n" ..
    "  4 = Health Check\n" ..
    "  5 = Preview Import  (dry run)\n" ..
    "  6 = Apply Import  (WRITES to calibration)\n" ..
    "  7 = Debug dump\n" ..
    "  8 = API Probe\n" ..
    "  9 = GUI Test\n\n" ..
    "Enter number:",
    VERSION, cal_name, dl_count)

  local choice = InputQuery("ExportTune", prompt, "1")

  if     choice == "1" then do_full_export()
  elseif choice == "2" then do_export_cal()
  elseif choice == "3" then do_export_datalog()
  elseif choice == "4" then do_health_check()
  elseif choice == "5" then do_preview_import()
  elseif choice == "6" then
    local cal_path = Calibration:loaded() and Calibration:filename() or "your .fpcal file"
    local confirm = InputQuery("ExportTune - Confirm Write",
      "!! This will MODIFY your calibration !!\n\n" ..
      "Ensure you have a backup of:\n" ..
      cal_path .. "\n\n" ..
      "AI-generated changes must be reviewed by a\n" ..
      "qualified tuner before driving the vehicle.\n\n" ..
      "---\n" ..
      "ExportTune is free and open source.\n" ..
      "If this saved you time, or you charged a customer\n" ..
      "for a tune using it — please consider a small\n" ..
      "donation to support further development:\n" ..
      "github.com/sponsors/cybertza\n" ..
      "We trust you. That's why there is no paywall. :)\n" ..
      "---\n\n" ..
      "Type YES to continue:", "")
    if confirm == "YES" then
      do_import_changes()
    else
      print("Import cancelled.")
      ShowMessage("Import cancelled - calibration unchanged.")
    end
  elseif choice == "7" then do_debug()
  elseif choice == "8" then do_probe()
  elseif choice == "9" then gui_test.run()
  end
end

-- ── main entry point — auto-launches GUI ─────────────────────────────────────

function main()
  if not _modules_ok then
    local msg = "ExportTune: Module load failed.\n\n" ..
      tostring(_modules_err) .. "\n\n" ..
      "package.path:\n" .. package.path
    print(msg)
    ShowMessage(msg)
    return
  end
  do_gui_main()
end

-- ── event callbacks ───────────────────────────────────────────────────────────

function OnDatalogOpen(datalog)
  -- no print() — opening Plugin Interface window from a callback can crash FlashPro
end

function OnCalibrationOpen(calibration)
  if import_mod then import_mod.clear_cache() end
end

function OnCalibrationNew(calibration)
  if import_mod then import_mod.clear_cache() end
end

return { main = main }
