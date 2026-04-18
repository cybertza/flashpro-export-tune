--
-- ExportTune v3.0 - Hondata FlashPro Plugin
-- Exports calibration tables, datalog stats and DTCs to JSON.
-- Imports a change-set JSON to apply targeted calibration edits.
--
-- GitHub: https://github.com/cybertza/flashpro-export-tune
-- License: MIT
--

local Constants = require("constants")

local VERSION = "4.1"

-- ── output path ───────────────────────────────────────────────────────────────

local function get_cal_dir()
  if Calibration:loaded() then
    local cal = Calibration:filename()
    local dir = cal:match("^(.+)\\[^\\]+$") or cal:match("^(.+)/[^/]+$")
    if dir then return dir end
  end
  return nil
end

local function get_downloads_dir()
  -- Try to resolve %USERPROFILE%\Downloads via a shell echo
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
  -- last resort: plugin directory (always writable)
  return "C:\\Users\\Public\\Documents\\" .. suffix .. ".json"
end

-- ── JSON helpers ──────────────────────────────────────────────────────────────

local function esc(s)
  if s == nil then return "null" end
  s = tostring(s)
  s = s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')
  return '"' .. s .. '"'
end

local function num(v)
  if v == nil then return "null" end
  local n = tonumber(v)
  if not n or n ~= n or n == math.huge or n == -math.huge then return "null" end
  return tostring(n)
end

-- Minimal JSON parser — handles only the subset ExportTune writes/reads
-- (objects, arrays, strings, numbers, true/false, null)
local json = {}

local function skip_ws(s, i)
  while i <= #s and s:sub(i,i):match('%s') do i = i+1 end
  return i
end

local function parse_value(s, i)  -- forward declare
  i = skip_ws(s, i)
  local c = s:sub(i,i)
  if c == '"' then
    local j = i+1
    local r = {}
    while j <= #s do
      local ch = s:sub(j,j)
      if ch == '\\' then
        local nx = s:sub(j+1,j+1)
        if     nx == '"'  then r[#r+1]='"'  j=j+2
        elseif nx == '\\' then r[#r+1]='\\' j=j+2
        elseif nx == 'n'  then r[#r+1]='\n' j=j+2
        elseif nx == 'r'  then r[#r+1]='\r' j=j+2
        else r[#r+1]=nx; j=j+2 end
      elseif ch == '"' then
        return table.concat(r), j+1
      else
        r[#r+1]=ch; j=j+1
      end
    end
    error("unterminated string at "..i)
  elseif c == '[' then
    local arr = {}
    i = i+1
    i = skip_ws(s,i)
    if s:sub(i,i) == ']' then return arr, i+1 end
    while true do
      local v; v,i = parse_value(s,i)
      arr[#arr+1] = v
      i = skip_ws(s,i)
      local d = s:sub(i,i)
      if d == ']' then return arr, i+1
      elseif d == ',' then i=i+1
      else error("expected , or ] at "..i) end
    end
  elseif c == '{' then
    local obj = {}
    i = i+1
    i = skip_ws(s,i)
    if s:sub(i,i) == '}' then return obj, i+1 end
    while true do
      i = skip_ws(s,i)
      local k; k,i = parse_value(s,i)
      i = skip_ws(s,i)
      if s:sub(i,i) ~= ':' then error("expected : at "..i) end
      i = i+1
      local v; v,i = parse_value(s,i)
      obj[k] = v
      i = skip_ws(s,i)
      local d = s:sub(i,i)
      if d == '}' then return obj, i+1
      elseif d == ',' then i=i+1
      else error("expected , or } at "..i) end
    end
  elseif s:sub(i,i+3) == 'true'  then return true,  i+4
  elseif s:sub(i,i+4) == 'false' then return false, i+5
  elseif s:sub(i,i+3) == 'null'  then return nil,   i+4
  else
    local n_str = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', i)
    if n_str then return tonumber(n_str), i + #n_str end
    error("unexpected char '"..c.."' at "..i)
  end
end

function json.decode(s)
  local ok, result, _ = pcall(parse_value, s, 1)
  if ok then return result end
  return nil, result  -- result is the error message
end

-- ── calibration table serialisers ─────────────────────────────────────────────

local function dump_parameter(t)
  return '{"kind":"Parameter","value":' .. num(t:value()) .. '}'
end

local function dump_index(t)
  local v = {}
  for i = 1, t:length() do v[i] = num(t:value(i)) end
  return '{"kind":"Index","values":[' .. table.concat(v,',') .. ']}'
end

local function dump_1d(t)
  local idx = t:index(1)
  local ax, vals = {}, {}
  for i = 1, idx:length() do
    ax[i]   = num(idx:value(i))
    vals[i] = num(t:value(i))
  end
  return '{"kind":"Table1D",' ..
    '"axis_name":' .. esc(idx:name()) .. ',' ..
    '"axis_unit":' .. esc(Constants.UnitName[idx:unit()]) .. ',' ..
    '"axis":['  .. table.concat(ax,',')   .. '],' ..
    '"values":[' .. table.concat(vals,',') .. ']}'
end

local function dump_2d(t)
  local i1, i2 = t:index(1), t:index(2)
  local ax1, ax2 = {}, {}
  for i = 1, i1:length() do ax1[i] = num(i1:value(i)) end
  for i = 1, i2:length() do ax2[i] = num(i2:value(i)) end
  local rows = {}
  for r = 1, i2:length() do
    local cells = {}
    for c = 1, i1:length() do cells[c] = num(t:value(c,r)) end
    rows[r] = '[' .. table.concat(cells,',') .. ']'
  end
  return '{"kind":"Table2D",' ..
    '"col_name":' .. esc(i1:name()) .. ',"col_unit":' .. esc(Constants.UnitName[i1:unit()]) .. ',' ..
    '"col_axis":[' .. table.concat(ax1,',') .. '],' ..
    '"row_name":' .. esc(i2:name()) .. ',"row_unit":' .. esc(Constants.UnitName[i2:unit()]) .. ',' ..
    '"row_axis":[' .. table.concat(ax2,',') .. '],' ..
    '"rows":['  .. table.concat(rows,',') .. ']}'
end

local function dump_3d(t)
  local i1,i2,i3 = t:index(1),t:index(2),t:index(3)
  local ax1,ax2,ax3 = {},{},{}
  for i=1,i1:length() do ax1[i]=num(i1:value(i)) end
  for i=1,i2:length() do ax2[i]=num(i2:value(i)) end
  for i=1,i3:length() do ax3[i]=num(i3:value(i)) end
  local pages={}
  for p=1,i3:length() do
    local rows={}
    for r=1,i2:length() do
      local cells={}
      for c=1,i1:length() do cells[c]=num(t:value(c,r,p)) end
      rows[r]='['..table.concat(cells,',')..']'
    end
    pages[p]='['..table.concat(rows,',')..']'
  end
  return '{"kind":"Table3D",' ..
    '"ax1_name":' ..esc(i1:name())..',"ax1_unit":'..esc(Constants.UnitName[i1:unit()])..',"ax1":['..table.concat(ax1,',')..'],' ..
    '"ax2_name":' ..esc(i2:name())..',"ax2_unit":'..esc(Constants.UnitName[i2:unit()])..',"ax2":['..table.concat(ax2,',')..'],' ..
    '"ax3_name":' ..esc(i3:name())..',"ax3_unit":'..esc(Constants.UnitName[i3:unit()])..',"ax3":['..table.concat(ax3,',')..'],' ..
    '"pages":['..table.concat(pages,',')..']}'
end

local function kind_label(k)
  if     k == Constants.TableKind.Parameter then return "Param"
  elseif k == Constants.TableKind.Index     then return "Index"
  elseif k == Constants.TableKind.Table1D   then return "1D"
  elseif k == Constants.TableKind.Table2D   then return "2D"
  elseif k == Constants.TableKind.Table3D   then return "3D"
  else return "?" end
end

local function dump_table(t)
  local k = t:kind()
  local ok, body = pcall(function()
    if     k == Constants.TableKind.Parameter then return dump_parameter(t)
    elseif k == Constants.TableKind.Index     then return dump_index(t)
    elseif k == Constants.TableKind.Table1D   then return dump_1d(t)
    elseif k == Constants.TableKind.Table2D   then return dump_2d(t)
    elseif k == Constants.TableKind.Table3D   then return dump_3d(t)
    else return '"unsupported"' end
  end)
  if not ok then body = '"error"' end
  local unit = "null"
  local uok, uv = pcall(function() return t:unit() end)
  if uok and uv ~= nil then unit = esc(Constants.UnitName[uv]) end
  return '{"name":' ..esc(t:name())..',"unit":'..unit..
    ',"readonly":'..tostring(t:readonly())..',"data":'..body..'}'
end

-- ── datalog helpers ───────────────────────────────────────────────────────────

local SENSORS = {
  "RPM","VSS","MAP","BP","TPlate","TPedal","AFM","AFM.v",
  "IAT","ECT","IGN","CAM","CAMCMD",
  "AF","AF.Corr","Wide","AFCMD",
  "S.TRIM","L.TRIM","K.Level","K.Retard",
  "INJ","DUTY","FuelP","BAT","Fuel Used"
}

local TS_SENSORS = {"RPM","AF","ECT","S.TRIM","L.TRIM","MAP","TPlate","IGN","AFM.v","K.Retard"}

local function safe_sensor(name)
  local ok, s = pcall(function() return SensorList[name] end)
  return ok and s or nil
end

local function stats(dl, sensor)
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

local function dump_datalogs(verbose)
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
    local sp = {}
    local found = 0
    for _,sn in ipairs(SENSORS) do
      local s = safe_sensor(sn)
      if s then
        local st = stats(dl, s)
        if st then
          found = found + 1
          sp[#sp+1] = esc(sn) .. ':{"min":' .. string.format("%.3f",st.min) ..
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
    if verbose then print(string.format("    Sensors: %d/%d", found, #SENSORS)) end
    local step = math.max(1, math.floor(fc/200))
    local ss   = {}
    for _,sn in ipairs(TS_SENSORS) do ss[#ss+1] = safe_sensor(sn) end
    local ts = {}
    for f=1,fc,step do
      local ok_t, tv = pcall(function() return dl:timestamp(f) end)
      local row = {ok_t and num(tv) or "null"}
      for _,s in ipairs(ss) do
        if s then
          local ok_v, rv = pcall(function() return dl:value(s,f) end)
          row[#row+1] = ok_v and num(rv) or "null"
        else
          row[#row+1] = "null"
        end
      end
      ts[#ts+1] = '[' .. table.concat(row,',') .. ']'
    end
    if verbose then print("    Time-series: " .. #ts .. " samples") end
    dl_parts[#dl_parts+1] = '{"file":' .. esc(fname) ..
      ',"frames":' .. fc ..
      ',"length_s":' .. num(len) ..
      ',"sensors":{' .. table.concat(sp,',') .. '}' ..
      ',"ts_cols":["time_s","RPM","AF","ECT","S.TRIM","L.TRIM","MAP","TPlate","IGN","AFM.v","K.Retard"]' ..
      ',"ts":[' .. table.concat(ts,',') .. ']}'
  end
  return '"count":' .. count .. ',"logs":[' .. table.concat(dl_parts,',') .. ']'
end

-- ── DTCs ──────────────────────────────────────────────────────────────────────

local function dump_dtcs()
  local p = {}
  for i=1,ErrorCodeList:count() do
    local c = ErrorCodeList:code(i)
    p[#p+1] = '{"code":' .. esc(c:code()) .. ',"desc":' .. esc(c:description()) .. '}'
  end
  return '[' .. table.concat(p,',') .. ']'
end

-- ── key parameter summary ─────────────────────────────────────────────────────

local KEY_PARAMS = {
  "Injector size",
  "Overall fuel trim",
  "AFM enabled",
  "Active fuel tuning enabled",
  "Use speed/density (MAP) fuel tables",
  "Closed loop",
  "Open loop",
  "Closed loop target lambda",
  "Short term fuel trim maximum",
  "Short term fuel trim minimum",
  "Long term fuel trim maximum",
  "Long term fuel trim minimum",
}

local function print_cal_summary()
  if not Calibration:loaded() then return end
  print("  ---- Key Calibration Parameters ----")
  local count = Calibration:tablecount()
  for idx=1,count do
    local t = Calibration:table(idx)
    local ok_n, nm = pcall(function() return t:name() end)
    if ok_n and nm then
      for _,kp in ipairs(KEY_PARAMS) do
        if nm == kp then
          local ok_k, kv = pcall(function() return t:kind() end)
          if ok_k and kv == Constants.TableKind.Parameter then
            local ok_v, vv = pcall(function() return t:value() end)
            if ok_v then
              print(string.format("  %-45s = %s", nm, tostring(vv)))
            end
          end
          break
        end
      end
    end
  end
  print("  ------------------------------------")
end

-- ── import / write-back ───────────────────────────────────────────────────────

-- Build a name→table index lookup (cached for the session)
local cal_index_cache = nil

local function build_cal_index()
  if cal_index_cache then return cal_index_cache end
  local idx = {}
  if not Calibration:loaded() then return idx end
  local count = Calibration:tablecount()
  for i=1,count do
    local t = Calibration:table(i)
    local ok, nm = pcall(function() return t:name() end)
    if ok and nm then idx[nm] = i end
  end
  cal_index_cache = idx
  return idx
end

local function apply_change(t, change, dry_run)
  local name = change["name"] or "?"
  local kind = change["kind"] or ""

  if kind == "Parameter" then
    local new_val = tonumber(change["value"])
    if not new_val then
      print("  ERROR [" .. name .. "] missing or non-numeric 'value'")
      return false
    end
    local ok_old, old_val = pcall(function() return t:value() end)
    local old_str = ok_old and tostring(old_val) or "?"
    print(string.format("  %s  %-45s  %s  ->  %s",
      dry_run and "PREVIEW" or "SET    ", name, old_str, tostring(new_val)))
    if not dry_run then
      local ok, err = pcall(function() t:setvalue(new_val) end)
      if not ok then
        print("    ERROR applying: " .. tostring(err))
        return false
      end
    end
    return true

  elseif kind == "Table1D" then
    local new_vals = change["values"]
    if type(new_vals) ~= "table" then
      print("  ERROR [" .. name .. "] 'values' array required for Table1D")
      return false
    end
    local idx1 = t:index(1)
    local len  = idx1:length()
    if #new_vals ~= len then
      print(string.format("  ERROR [%s] values length %d != table length %d",
        name, #new_vals, len))
      return false
    end
    print(string.format("  %s  %-45s  (%d values)",
      dry_run and "PREVIEW" or "SET    ", name, len))
    for i=1,len do
      local nv = tonumber(new_vals[i])
      if not nv then
        print("    ERROR: non-numeric value at index " .. i)
        return false
      end
      local ok_old, ov = pcall(function() return t:value(i) end)
      local old_str = ok_old and string.format("%.4f", ov) or "?"
      print(string.format("    [%2d] %s -> %.4f", i, old_str, nv))
      if not dry_run then
        -- setvalue argument order: (value, index)
        local ok, err = pcall(function() t:setvalue(nv, i) end)
        if not ok then
          print("    ERROR applying index " .. i .. ": " .. tostring(err))
          return false
        end
      end
    end
    return true

  elseif kind == "Table2D" then
    local new_rows = change["rows"]
    if type(new_rows) ~= "table" then
      print("  ERROR [" .. name .. "] 'rows' array required for Table2D")
      return false
    end
    local i1 = t:index(1)
    local i2 = t:index(2)
    local cols = i1:length()
    local rows = i2:length()
    print(string.format("  %s  %-45s  (%dx%d)",
      dry_run and "PREVIEW" or "SET    ", name, cols, rows))
    if #new_rows ~= rows then
      print(string.format("  ERROR [%s] row count %d != %d", name, #new_rows, rows))
      return false
    end
    for r=1,rows do
      local row = new_rows[r]
      if type(row) ~= "table" or #row ~= cols then
        print(string.format("  ERROR [%s] row %d has %d cols, expected %d",
          name, r, type(row)=="table" and #row or 0, cols))
        return false
      end
      for c=1,cols do
        local nv = tonumber(row[c])
        if not nv then
          print(string.format("  ERROR [%s] non-numeric at row %d col %d", name, r, c))
          return false
        end
        if not dry_run then
          -- setvalue argument order: (value, col, row)
          local ok, err = pcall(function() t:setvalue(nv, c, r) end)
          if not ok then
            print(string.format("  ERROR at [%d,%d]: %s", c, r, tostring(err)))
            return false
          end
        end
      end
    end
    return true

  else
    print("  SKIP  [unsupported kind '" .. kind .. "'] " .. name)
    return false
  end
end

local function run_import(dry_run)
  local dir = get_cal_dir()
  if not dir then
    print("ERROR: No calibration loaded — cannot locate import file")
    return
  end

  local import_file = dir .. "\\tune_import.json"
  print("Import file : " .. import_file)

  local fh = io.open(import_file, "r")
  if not fh then
    print("ERROR: File not found: " .. import_file)
    print("")
    print("Create tune_import.json in the same folder as your calibration.")
    print("Ask an AI to generate it based on your tune_export.json.")
    print("See README for the expected format.")
    return
  end

  local raw = fh:read('*a')
  fh:close()

  local data, err = json.decode(raw)
  if not data then
    print("ERROR: Could not parse tune_import.json: " .. tostring(err))
    return
  end

  local changes = data["changes"]
  if type(changes) ~= "table" or #changes == 0 then
    print("ERROR: 'changes' array is missing or empty in tune_import.json")
    return
  end

  local desc = data["description"] or "(no description)"
  print(string.format("Description : %s", desc))
  print(string.format("Changes     : %d", #changes))
  if dry_run then
    print("Mode        : DRY RUN (preview only - no changes applied)")
  else
    print("Mode        : LIVE (changes will be written to calibration)")
  end
  print("")

  local cal_idx = build_cal_index()
  local applied, skipped, errors = 0, 0, 0

  for _,change in ipairs(changes) do
    local name = change["name"]
    if not name then
      print("  ERROR: change entry missing 'name' field")
      errors = errors + 1
    else
      local tbl_idx = cal_idx[name]
      if not tbl_idx then
        print("  NOT FOUND  " .. name)
        errors = errors + 1
      else
        local t = Calibration:table(tbl_idx)
        local ok = apply_change(t, change, dry_run)
        if ok then applied = applied + 1 else skipped = skipped + 1 end
      end
    end
  end

  print("")
  print(string.format("  Applied: %d   Skipped: %d   Errors: %d",
    applied, skipped, errors))

  if not dry_run and applied > 0 then
    print("")
    print("  Saving calibration...")
    local ok, err2 = pcall(function() Calibration:update() end)
    if ok then
      print("  Calibration saved successfully.")
    else
      print("  ERROR saving: " .. tostring(err2))
    end
  end
end

-- ── write helpers ─────────────────────────────────────────────────────────────

local function write_header(f)
  f:write('{\n')
  f:write('"export_version":' .. esc(VERSION) .. ',\n')
  f:write('"plugin":"ExportTune",\n')
  f:write('"github":"https://github.com/cybertza/flashpro-export-tune",\n')
  f:write('"timestamp":' .. esc(os.date("%Y-%m-%d %H:%M:%S")) .. ',\n')
end

local function write_calibration(f, verbose)
  if not Calibration:loaded() then
    print("WARNING: No calibration loaded")
    f:write('"calibration_file":null,"table_count":0,"tables":[],\n')
    return
  end
  local cal_file = Calibration:filename()
  local count    = Calibration:tablecount()
  print("Calibration : " .. cal_file)
  print(string.format("Tables      : %d", count))
  print("")
  f:write('"calibration_file":' .. esc(cal_file) .. ',\n')
  f:write('"table_count":' .. count .. ',\n')
  f:write('"tables":[\n')
  local n_param,n_1d,n_2d,n_3d,n_err = 0,0,0,0,0
  for idx=1,count do
    local t = Calibration:table(idx)
    local ok_n, nm = pcall(function() return t:name() end)
    local tname    = ok_n and (nm or "") or ""
    local ok_k, kv = pcall(function() return t:kind() end)
    local ttype    = ok_k and kind_label(kv) or "?"
    local ok, result = pcall(dump_table, t)
    if ok then
      f:write(result)
      if ok_k then
        if     kv == Constants.TableKind.Parameter then n_param = n_param+1
        elseif kv == Constants.TableKind.Table1D   then n_1d    = n_1d+1
        elseif kv == Constants.TableKind.Table2D   then n_2d    = n_2d+1
        elseif kv == Constants.TableKind.Table3D   then n_3d    = n_3d+1
        end
      end
    else
      f:write('{"name":"error","data":null}')
      n_err = n_err+1
    end
    if idx < count then f:write(',\n') else f:write('\n') end
    if verbose and (idx % 10 == 0 or idx == count) then
      print(string.format("  [%3d%%] %d/%d  (%s) %s",
        math.floor(idx/count*100), idx, count, ttype, tname))
      f:flush()
    elseif not verbose and (idx % 50 == 0 or idx == count) then
      print(string.format("  tables: %d/%d", idx, count))
      f:flush()
    end
  end
  f:write('],\n')
  print("")
  print(string.format("  Types: %d Param  %d 1D  %d 2D  %d 3D  %d errors",
    n_param, n_1d, n_2d, n_3d, n_err))
  print("")
  print_cal_summary()
end

local function write_dtcs(f)
  print("Writing DTCs...")
  local dtc_json  = dump_dtcs()
  local dtc_count = 0
  for _ in dtc_json:gmatch('"code":') do dtc_count = dtc_count+1 end
  f:write('"dtcs":' .. dtc_json .. ',\n')
  print(string.format("  DTCs: %d", dtc_count))
  print("")
end

local function write_datalog(f, verbose)
  local dl_count = DatalogManager:count()
  print(string.format("Datalogs loaded: %d", dl_count))
  if dl_count == 0 then
    print("  (none) -- Datalog menu -> Open -> select .fpdl, then re-run")
  end
  local ok, dljson = pcall(dump_datalogs, verbose)
  if ok then
    f:write('"datalog":{' .. dljson .. '}\n')
  else
    f:write('"datalog":{"error":' .. esc(tostring(dljson)) .. '}\n')
    print("  ERROR: " .. tostring(dljson))
  end
end

local function banner(title)
  print("============================================================")
  print("  ExportTune v" .. VERSION .. "  [EXPERIMENTAL]  --  " .. title)
  print("  github.com/cybertza/flashpro-export-tune")
  print("  Not affiliated with or endorsed by Hondata Inc.")
  print("============================================================")
end

local function done(path)
  print("")
  print("============================================================")
  print("  DONE  -->  " .. path)
  print("============================================================")
  ShowMessage("ExportTune: Export complete!\n\n" .. path)
end

-- ── action implementations ────────────────────────────────────────────────────

local function do_full_export()
  banner("Full Export")
  local OUT = get_out_file("tune_export")
  print("Output: " .. OUT .. "\n")
  local f = io.open(OUT, "w")
  if not f then
    ShowMessage("ERROR: Cannot write to:\n" .. OUT)
    return
  end
  write_header(f)
  write_calibration(f, true)
  write_dtcs(f)
  write_datalog(f, true)
  f:write('}\n')
  f:close()
  done(OUT)
end

local function do_export_cal()
  banner("Export Calibration Only")
  local OUT = get_out_file("tune_export_cal")
  print("Output: " .. OUT .. "\n")
  local f = io.open(OUT, "w")
  if not f then ShowMessage("ERROR: Cannot write to:\n" .. OUT); return end
  write_header(f)
  write_calibration(f, true)
  write_dtcs(f)
  f:write('"datalog":{"count":0,"logs":[]}\n}\n')
  f:close()
  done(OUT)
end

local function do_export_datalog()
  banner("Export Datalog Only")
  local OUT = get_out_file("tune_export_datalog")
  print("Output: " .. OUT .. "\n")
  local f = io.open(OUT, "w")
  if not f then ShowMessage("ERROR: Cannot write to:\n" .. OUT); return end
  write_header(f)
  if Calibration:loaded() then
    f:write('"calibration_file":' .. esc(Calibration:filename()) .. ',\n')
  else
    f:write('"calibration_file":null,\n')
  end
  f:write('"table_count":0,"tables":[],\n')
  write_dtcs(f)
  write_datalog(f, true)
  f:write('}\n')
  f:close()
  done(OUT)
end

local function do_health_check()
  banner("Quick Health Check")
  print("")
  print_cal_summary()
  print("")
  local dl_count = DatalogManager:count()
  print(string.format("Datalogs loaded: %d", dl_count))
  if dl_count > 0 then
    for d=1,dl_count do
      local dl    = DatalogManager:datalog(d)
      local fname = dl:filename() or ("log "..d)
      local fc    = dl:framecount()
      print(string.format("\nLog %d: %s  (%d frames)", d, fname, fc))
      for _,sn in ipairs({"RPM","S.TRIM","L.TRIM","AF","Wide","MAP","IAT","ECT","K.Retard","K.Level"}) do
        local s = safe_sensor(sn)
        if s then
          local st = stats(dl, s)
          if st then
            print(string.format("  %-10s  min=%8.2f  max=%8.2f  mean=%8.2f",
              sn, st.min, st.max, st.mean))
          end
        end
      end
    end
  end
  print("")
  print("  Health check complete (no file written)")
  print("============================================================")
end

local function do_preview_import()
  banner("Preview Import (dry run)")
  print("")

  -- capture print() output into a buffer while run_import executes
  local buf = {}
  local orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    local line = table.concat(parts, '\t')
    orig_print(line)       -- still goes to console
    buf[#buf+1] = line
  end

  run_import(true)

  print = orig_print       -- restore

  print("")
  print("  DRY RUN complete  (calibration unchanged)")
  print("============================================================")

  -- trim to 60 lines so the dialog stays readable
  local MAX_LINES = 60
  local truncated = #buf > MAX_LINES
  if truncated then
    local kept = {}
    for i = 1, MAX_LINES do kept[i] = buf[i] end
    kept[#kept+1] = "... (" .. (#buf - MAX_LINES) .. " more lines — see console)"
    buf = kept
  end

  ShowMessage("ExportTune — Import Preview (dry run)\n" ..
    "No changes applied.\n\n" ..
    table.concat(buf, '\n'))
end

local function do_import_changes()
  banner("Import Changes  [EXPERIMENTAL]")
  print("")
  print("  !! WRITE OPERATION -- calibration will be modified !!")
  print("  Ensure you have a backup of your .fpcal file.")
  print("")
  run_import(false)
  print("")
  print("  Import complete")
  print("============================================================")
end

-- ── main entry point — dialog menu ────────────────────────────────────────────

function main()
  local cal_name = Calibration:loaded()
    and Calibration:filename():match("[^\\]+$") or "(no calibration)"
  local dl_count = DatalogManager:count()

  local prompt = string.format(
    "ExportTune v%s  [EXPERIMENTAL]\n" ..
    "github.com/cybertza/flashpro-export-tune\n\n" ..
    "Calibration : %s\n" ..
    "Datalogs    : %d loaded\n\n" ..
    "Select action:\n" ..
    "  1 = Full Export  (calibration + datalog + DTCs)\n" ..
    "  2 = Calibration Only\n" ..
    "  3 = Datalog Only\n" ..
    "  4 = Health Check  (console, no file)\n" ..
    "  5 = Preview Import  (dry run tune_import.json)\n" ..
    "  6 = Apply Import  (WRITES to calibration)\n\n" ..
    "Enter number (or cancel to abort):",
    VERSION, cal_name, dl_count)

  local choice = InputQuery("ExportTune", prompt, "1")

  if     choice == "1" then do_full_export()
  elseif choice == "2" then do_export_cal()
  elseif choice == "3" then do_export_datalog()
  elseif choice == "4" then do_health_check()
  elseif choice == "5" then do_preview_import()
  elseif choice == "6" then
    local confirm = InputQuery("ExportTune – Confirm Write",
      "!! This will MODIFY your calibration !!\n\n" ..
      "Ensure you have a backup of:\n" .. (Calibration:loaded() and Calibration:filename() or "your .fpcal file") .. "\n\n" ..
      "AI-generated changes must be reviewed by a\n" ..
      "qualified tuner before driving the vehicle.\n\n" ..
      "Type YES to continue:", "")
    if confirm == "YES" then
      do_import_changes()
    else
      print("Import cancelled.")
      ShowMessage("Import cancelled — calibration unchanged.")
    end
  elseif choice == nil then
    print("Cancelled.")
  else
    ShowMessage("Invalid choice '" .. tostring(choice) .. "' — enter 1 to 6.")
  end
end

-- ── event callbacks ───────────────────────────────────────────────────────────

-- Auto-export datalog stats whenever a new datalog is opened
function OnDatalogOpen(datalog)
  local fname = datalog:filename() or "datalog"
  print("[ExportTune] Datalog opened: " .. fname)
  print("[ExportTune] Run ExportTune from the Plugins menu to export with the new datalog.")
end

-- Invalidate the calibration name→index cache when cal changes
function OnCalibrationOpen(calibration)
  cal_index_cache = nil
  print("[ExportTune] Calibration opened — index cache cleared.")
end

function OnCalibrationNew(calibration)
  cal_index_cache = nil
end

return { main = main }
