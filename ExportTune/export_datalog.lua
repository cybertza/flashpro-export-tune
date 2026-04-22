--
-- export_datalog.lua — datalog stats + time-series serialiser
-- Depends on: json
--
local json = require("json")

local M = {}

-- ── sensor name lists ─────────────────────────────────────────────────────────

-- Full stats list — every sensor we attempt to include in the per-sensor min/max/mean block
M.SENSORS = {
  -- Engine & airflow
  "RPM","VSS","MAP","BP","TPlate","TPedal","AFM","AFM.v","AFM Hz",
  "IAT","IAT2","ECT","ECT2","IGN","CAM","CAMCMD","EXCAM","PA",
  -- Fuel trims & wideband
  "AF","AF Bank 2","AF.Corr","Wide","Wide.V","AFCMD","AFCMD Bank 2",
  "S.TRIM","L.TRIM","S.TRIM Bank 2","L.TRIM Bank 2","Trim",
  "Fuel Status","Fuel Status Bank 2","Ethanol",
  "INJ","INJ Bank 2","DUTY","DIFP","DIFPCMD","FuelP",
  -- Valve / boost / emissions
  "AIRC","EGR","Purge","VTS","SVS","WG","WGCMD","ACCL",
  -- Knock
  "K.Level","K.Retard","K.Retard.1","K.Retard.2","K.Retard.3","K.Retard.4",
  "K.Control","Ign.Limit","K.Count","K.Count.1","K.Count.2","K.Count.3",
  -- Vehicle dynamics
  "Gear","G.Lat","G.Long","G.Z","Yaw",
  "ABS.LF","ABS.RF","ABS.LR","ABS.RR",
  "Clutch.Pos","Brake.Press","Steer Ang","Steer Trq",
  -- Traction control
  "TC.V","TC.ECUSlip","TC.R","TC.LF","TC.RF","TC.LR","TC.RR",
  "TC.Slip","TC.Turn","TC.OverSlip","TC.Out",
  -- Torque & AIRC management
  "Trq Req","Act Trq","trq_max","airc_max","airc_red","airc_prot","airc_comp",
  -- Electrical & thermal
  "BAT","Oil.Press","CVT.Temp","Cat.T","Fuel Used","BC Duty",
}

-- Time-series list — channels included in the ts[][] array
M.TS_SENSORS = {
  -- Core engine
  "RPM","VSS","MAP","TPlate","TPedal","AFM.v","AFM","IAT","ECT","IGN",
  "CAM","CAMCMD","EXCAM",
  -- Fuel trims & wideband
  "AF","AF Bank 2","AF.Corr","Wide","AFCMD",
  "S.TRIM","L.TRIM","S.TRIM Bank 2","L.TRIM Bank 2","Fuel Status","Ethanol",
  "INJ","DUTY","FuelP","DIFP",
  -- Valve / boost / emissions
  "EGR","WG","AIRC","Purge","VTS",
  -- Knock (overall + per-cylinder)
  "K.Level","K.Retard","K.Retard.1","K.Retard.2","K.Retard.3","K.Retard.4",
  "K.Control","Ign.Limit","K.Count",
  -- Vehicle dynamics
  "Gear","G.Lat","G.Long","G.Z","Yaw",
  "ABS.LF","ABS.RF","ABS.LR","ABS.RR",
  "Clutch.Pos","Brake.Press","Steer Ang",
  -- Traction control
  "TC.V","TC.Slip","TC.Out","TC.ECUSlip",
  -- Torque
  "Trq Req","Act Trq",
  -- Electrical & thermal
  "BAT","Oil.Press","CVT.Temp","Cat.T","Fuel Used",
}

-- ── helpers ───────────────────────────────────────────────────────────────────

function M.safe_sensor(name)
  local ok, s = pcall(function() return SensorList[name] end)
  return ok and s or nil
end

function M.stats(dl, sensor)
  local fc = dl:framecount()
  if fc == 0 then return nil end
  local step = math.max(1, math.floor(fc/2000))
  local mn,mx,sum,cnt = math.huge,-math.huge,0,0
  for f=1,fc,step do
    local ok, raw = pcall(function() return dl:value(sensor,f) end)
    local n = ok and tonumber(raw) or nil
    if n then
      if n<mn then mn=n end
      if n>mx then mx=n end
      sum=sum+n; cnt=cnt+1
    end
  end
  if cnt==0 then return nil end
  return {min=mn, max=mx, mean=sum/cnt}
end

-- ── sample count dialog ───────────────────────────────────────────────────────

function M.ask_sample_count()
  local input = InputQuery("ExportTune — Time-Series Resolution",
    "Samples per log for the time-series export?\n\n" ..
    "Higher = more detail, larger file.\n\n" ..
    "  200   ~1 sample / 6 s   (very coarse)\n" ..
    "  2000  ~1 sample / 0.6 s (recommended)\n" ..
    "  5000  ~1 sample / 0.2 s (detailed)\n" ..
    "  0     skip time-series\n\n" ..
    "Enter number:", "2000")
  if input == nil then return nil end
  local n = math.floor(tonumber(input) or 2000)
  return math.max(0, n)
end

-- ── datalog serialiser ────────────────────────────────────────────────────────

local function dump_datalogs(verbose, max_samples)
  local count = DatalogManager:count()
  local dl_parts = {}
  for d=1,count do
    local dl    = DatalogManager:datalog(d)
    local fname = dl:filename() or ("log "..d)
    local fc    = dl:framecount()
    local len   = dl:length()
    if verbose then
      print(string.format("  Log %d/%d: %s", d, count, fname))
      print(string.format("    Frames: %d  Duration: %.1fs", fc, tonumber(len) or 0))
    end
    -- per-sensor stats
    local sp = {}
    local found = 0
    for _,sn in ipairs(M.SENSORS) do
      local s = M.safe_sensor(sn)
      if s then
        local st = M.stats(dl, s)
        if st then
          found = found + 1
          sp[#sp+1] = json.esc(sn) .. ':{"min":' .. string.format("%.3f",st.min) ..
            ',"max":' .. string.format("%.3f",st.max) ..
            ',"mean":' .. string.format("%.3f",st.mean) .. '}'
          if verbose and (sn=="RPM" or sn=="S.TRIM" or sn=="L.TRIM" or
                          sn=="AF"  or sn=="Wide"   or sn=="MAP"    or
                          sn=="IAT" or sn=="ECT"    or sn=="IGN"    or
                          sn=="K.Retard") then
            print(string.format("    %-10s  min=%8.2f  max=%8.2f  mean=%8.2f",
              sn, st.min, st.max, st.mean))
          end
        end
      end
    end
    if verbose then print(string.format("    Sensors: %d/%d", found, #M.SENSORS)) end
    -- time-series
    local n_samples = (max_samples and max_samples > 0) and max_samples or 0
    local step = n_samples > 0 and math.max(1, math.floor(fc / n_samples)) or (fc + 1)
    local ts_names, ts_objs = {}, {}
    for _,sn in ipairs(M.TS_SENSORS) do
      local s = M.safe_sensor(sn)
      if s then
        ts_names[#ts_names+1] = sn
        ts_objs[#ts_objs+1]   = s
      end
    end
    local ts = {}
    for f=1,fc,step do
      local ok_t, tv = pcall(function() return dl:timestamp(f) end)
      local row = {ok_t and json.num(tv) or "null"}
      for _,s in ipairs(ts_objs) do
        local ok_v, rv = pcall(function() return dl:value(s,f) end)
        row[#row+1] = ok_v and json.num(rv) or "null"
      end
      ts[#ts+1] = '[' .. table.concat(row,',') .. ']'
    end
    local col_list = {'"time_s"'}
    for _,sn in ipairs(ts_names) do col_list[#col_list+1] = json.esc(sn) end
    if verbose then
      print(string.format("    Time-series: %d samples  step=%d  channels=%d",
        #ts, step, #ts_names))
    end
    dl_parts[#dl_parts+1] = '{"file":' .. json.esc(fname) ..
      ',"frames":' .. fc ..
      ',"length_s":' .. json.num(len) ..
      ',"sensors":{' .. table.concat(sp,',') .. '}' ..
      ',"ts_cols":[' .. table.concat(col_list,',') .. ']' ..
      ',"ts":[' .. table.concat(ts,',') .. ']}'
  end
  return '"count":' .. count .. ',"logs":[' .. table.concat(dl_parts,',') .. ']'
end

function M.write_datalog(f, verbose, max_samples)
  local dl_count = DatalogManager:count()
  print(string.format("Datalogs loaded: %d", dl_count))
  if dl_count == 0 then
    print("  (none) -- Datalog menu -> Open -> select .fpdl, then re-run")
  end
  -- accumulate per-log counts for the summary
  local total_frames, total_samples = 0, 0
  local orig_dump = dump_datalogs
  -- wrap to capture counts: intercept print lines for sample/frame info
  local ok, dljson = pcall(dump_datalogs, verbose, max_samples)
  if ok then
    f:write('"datalog":{' .. dljson .. '}\n')
    -- extract frame/sample totals from already-loaded datalogs
    for d=1,dl_count do
      local dl = DatalogManager:datalog(d)
      local fc = dl:framecount()
      total_frames = total_frames + fc
      local n_s = (max_samples and max_samples > 0)
        and math.min(max_samples, fc) or 0
      total_samples = total_samples + n_s
    end
  else
    f:write('"datalog":{"error":' .. json.esc(tostring(dljson)) .. '}\n')
    print("  ERROR: " .. tostring(dljson))
  end
  return {logs=dl_count, frames=total_frames, samples=total_samples}
end

return M
