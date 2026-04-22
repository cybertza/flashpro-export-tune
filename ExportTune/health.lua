--
-- health.lua — quick health check (console + ShowMessage)
-- Depends on: export_cal (for print_cal_summary), export_datalog (for safe_sensor, stats)
--
local export_cal = require("export_cal")
local dl_mod     = require("export_datalog")

local M = {}

-- Sensors shown in the health-check console summary
local HEALTH_SENSORS = {
  "RPM","S.TRIM","L.TRIM","AF","Wide","MAP","IAT","ECT","K.Retard","K.Level",
  "K.Retard.1","K.Retard.2","K.Retard.3","K.Retard.4","IGN","FuelP","BAT",
}

-- Warning thresholds — produces inline flags next to the stat line
local WARNINGS = {
  ["S.TRIM"] = function(st)
    if math.abs(st.mean) > 10 then return "!! STFT mean > 10% — check AFM calibration" end
    if math.abs(st.mean) > 5  then return "* STFT mean > 5% — AFM may need correction" end
  end,
  ["L.TRIM"] = function(st)
    if math.abs(st.mean) > 15 then return "!! LTFT mean > 15% — approaching ECU limit" end
    if math.abs(st.mean) > 8  then return "* LTFT mean > 8% — consider AFM correction" end
  end,
  ["Wide"] = function(st)
    if st.min < 11.0 then return "!! Lean excursion below 11.0 AFR at WOT!" end
  end,
  ["K.Retard"] = function(st)
    if st.max > 3.0 then return "!! Knock retard > 3° — check fuel/timing" end
    if st.max > 1.0 then return "* Knock detected — monitor closely" end
  end,
  ["K.Level"] = function(st)
    if st.max > 50 then return "!! High knock level — investigate" end
  end,
  ["ECT"] = function(st)
    if st.max > 105 then return "!! Coolant temp > 105°C — cooling concern" end
  end,
  ["IAT"] = function(st)
    if st.max > 60 then return "* Intake air temp > 60°C — heat soak?" end
  end,
}

function M.run()
  local lines = {}
  local flags = {}
  local function p(s) lines[#lines+1] = tostring(s) end

  -- Capture print() so print_cal_summary output goes into lines[] not the Plugin Interface window
  local orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    lines[#lines+1] = table.concat(parts, '\t')
  end

  p("============================================================")
  p("  Quick Health Check")
  p("============================================================")
  p("")

  -- calibration summary (its print() calls are now captured above)
  export_cal.print_cal_summary()
  print = orig_print   -- restore before datalog work
  p("")

  -- datalog stats
  local dl_count = DatalogManager:count()
  p(string.format("Datalogs loaded: %d", dl_count))

  if dl_count > 0 then
    for d=1,dl_count do
      local dl    = DatalogManager:datalog(d)
      local fname = dl:filename() or ("log "..d)
      local fc    = dl:framecount()
      p(string.format("\nLog %d: %s  (%d frames)", d, fname, fc))

      for _,sn in ipairs(HEALTH_SENSORS) do
        local s = dl_mod.safe_sensor(sn)
        if s then
          local st = dl_mod.stats(dl, s)
          if st then
            local line = string.format("  %-12s  min=%8.2f  max=%8.2f  mean=%8.2f",
              sn, st.min, st.max, st.mean)
            local warn_fn = WARNINGS[sn]
            local warn = warn_fn and warn_fn(st)
            if warn then
              line = line .. "   " .. warn
              flags[#flags+1] = warn
            end
            p(line)
          end
        end
      end
    end
  else
    p("  (none) — open a .fpdl via Datalog menu, then re-run")
  end

  p("")
  if #flags > 0 then
    p("  !! WARNINGS (" .. #flags .. ") !!")
    for _,f in ipairs(flags) do p("    " .. f) end
  else
    p("  No warnings detected.")
  end
  p("")
  p("  Health check complete — no file written.")
  p("============================================================")

  -- ShowMessage with first 60 lines (avoid print() — it opens Plugin Interface window)
  local MAX = 60
  local preview = {}
  for i=1, math.min(#lines, MAX) do preview[i] = lines[i] end
  if #lines > MAX then
    preview[#preview+1] = "... (" .. (#lines-MAX) .. " more lines)"
  end
  ShowMessage("ExportTune — Health Check\n\n" .. table.concat(preview,'\n'))
end

return M
