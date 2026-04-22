--
-- export_cal.lua — calibration + DTC serialisers
-- Depends on: json, constants (FlashPro built-in)
--
local Constants = require("constants")
local json      = require("json")

local M = {}

-- ── table kind helpers ────────────────────────────────────────────────────────

local function kind_label(k)
  if     k == Constants.TableKind.Parameter then return "Param"
  elseif k == Constants.TableKind.Index     then return "Index"
  elseif k == Constants.TableKind.Table1D   then return "1D"
  elseif k == Constants.TableKind.Table2D   then return "2D"
  elseif k == Constants.TableKind.Table3D   then return "3D"
  else return "?" end
end

-- ── per-kind serialisers ──────────────────────────────────────────────────────

local function dump_parameter(t)
  return '{"kind":"Parameter","value":' .. json.num(t:value()) .. '}'
end

local function dump_index(t)
  local v = {}
  for i = 1, t:length() do v[i] = json.num(t:value(i)) end
  return '{"kind":"Index","values":[' .. table.concat(v,',') .. ']}'
end

local function dump_1d(t)
  local idx = t:index(1)
  local ax, vals = {}, {}
  for i = 1, idx:length() do
    ax[i]   = json.num(idx:value(i))
    vals[i] = json.num(t:value(i))
  end
  return '{"kind":"Table1D",' ..
    '"axis_name":'  .. json.esc(idx:name()) .. ',' ..
    '"axis_unit":'  .. json.esc(Constants.UnitName[idx:unit()]) .. ',' ..
    '"axis":['      .. table.concat(ax,',')   .. '],' ..
    '"values":['    .. table.concat(vals,',') .. ']}'
end

local function dump_2d(t)
  local i1, i2 = t:index(1), t:index(2)
  local ax1, ax2 = {}, {}
  for i = 1, i1:length() do ax1[i] = json.num(i1:value(i)) end
  for i = 1, i2:length() do ax2[i] = json.num(i2:value(i)) end
  local rows = {}
  for r = 1, i2:length() do
    local cells = {}
    for c = 1, i1:length() do cells[c] = json.num(t:value(c,r)) end
    rows[r] = '[' .. table.concat(cells,',') .. ']'
  end
  return '{"kind":"Table2D",' ..
    '"col_name":' .. json.esc(i1:name()) .. ',"col_unit":' .. json.esc(Constants.UnitName[i1:unit()]) .. ',' ..
    '"col_axis":[' .. table.concat(ax1,',') .. '],' ..
    '"row_name":' .. json.esc(i2:name()) .. ',"row_unit":' .. json.esc(Constants.UnitName[i2:unit()]) .. ',' ..
    '"row_axis":[' .. table.concat(ax2,',') .. '],' ..
    '"rows":['    .. table.concat(rows,',') .. ']}'
end

local function dump_3d(t)
  local i1,i2,i3 = t:index(1),t:index(2),t:index(3)
  local ax1,ax2,ax3 = {},{},{}
  for i=1,i1:length() do ax1[i]=json.num(i1:value(i)) end
  for i=1,i2:length() do ax2[i]=json.num(i2:value(i)) end
  for i=1,i3:length() do ax3[i]=json.num(i3:value(i)) end
  local pages={}
  for p=1,i3:length() do
    local rows={}
    for r=1,i2:length() do
      local cells={}
      for c=1,i1:length() do cells[c]=json.num(t:value(c,r,p)) end
      rows[r]='['..table.concat(cells,',')..']'
    end
    pages[p]='['..table.concat(rows,',')..']'
  end
  return '{"kind":"Table3D",' ..
    '"ax1_name":'..json.esc(i1:name())..',"ax1_unit":'..json.esc(Constants.UnitName[i1:unit()])..',"ax1":['..table.concat(ax1,',')..'],' ..
    '"ax2_name":'..json.esc(i2:name())..',"ax2_unit":'..json.esc(Constants.UnitName[i2:unit()])..',"ax2":['..table.concat(ax2,',')..'],' ..
    '"ax3_name":'..json.esc(i3:name())..',"ax3_unit":'..json.esc(Constants.UnitName[i3:unit()])..',"ax3":['..table.concat(ax3,',')..'],' ..
    '"pages":['..table.concat(pages,',')..']}'
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
  if uok and uv ~= nil then unit = json.esc(Constants.UnitName[uv]) end
  return '{"name":'..json.esc(t:name())..',"unit":'..unit..
    ',"readonly":'..tostring(t:readonly())..',"data":'..body..'}'
end

-- ── key parameter console summary ─────────────────────────────────────────────

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

function M.print_cal_summary()
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

-- ── writers ───────────────────────────────────────────────────────────────────

function M.write_calibration(f, verbose)
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
  f:write('"calibration_file":' .. json.esc(cal_file) .. ',\n')
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
  M.print_cal_summary()
  return {total=count, params=n_param, t1d=n_1d, t2d=n_2d, t3d=n_3d, errors=n_err}
end

function M.write_dtcs(f)
  print("Writing DTCs...")
  local p = {}
  for i=1,ErrorCodeList:count() do
    local c = ErrorCodeList:code(i)
    p[#p+1] = '{"code":' .. json.esc(c:code()) .. ',"desc":' .. json.esc(c:description()) .. '}'
  end
  local dtc_json = '[' .. table.concat(p,',') .. ']'
  f:write('"dtcs":' .. dtc_json .. ',\n')
  print(string.format("  DTCs: %d", #p))
  print("")
  return #p
end

return M
