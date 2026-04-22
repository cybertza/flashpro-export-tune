--
-- probe.lua — systematic API surface testing
-- Output strategy:
--   print()      → Plugin Interface window (readable while ShowMessage blocks)
--   ShowMessage  → brief "see console" notification only
--   clipboard    → full text copy for pasting elsewhere
--
local M = {}

local function ok_line(label, detail)
  return string.format("OK    %-42s %s", label, detail or "")
end
local function fail_line(label, err)
  return string.format("FAIL  %-42s [%s]", label, tostring(err):sub(1,60))
end
local function miss_line(label)
  return string.format("MISS  %-42s", label)
end

local function try(label, fn)
  local ok, result = pcall(fn)
  if ok then
    local detail = result ~= nil and tostring(result):gsub('\n',' '):sub(1,55) or ""
    return ok_line(label, detail)
  else
    return fail_line(label, result)
  end
end

function M.run(copy_fn)
  local lines = {}
  local counts = {ok=0, fail=0, miss=0, skip=0}

  local function add(line)
    lines[#lines+1] = line
    print(line)   -- goes to Plugin Interface window (readable behind ShowMessage)
    local tag = line:sub(1,4)
    if tag == "OK  " then counts.ok   = counts.ok   + 1
    elseif tag == "FAIL" then counts.fail = counts.fail + 1
    elseif tag == "MISS" then counts.miss = counts.miss + 1
    elseif tag == "SKIP" then counts.skip = counts.skip + 1
    end
  end
  local function hdr(s) lines[#lines+1] = s; print(s) end

  hdr("=== ExportTune API Probe ===")
  hdr("Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S"))
  hdr("")

  -- ── 1. Lua runtime ────────────────────────────────────────────────────────
  hdr("-- 1. Lua Runtime --")
  add(try("_VERSION",         function() return _VERSION end))
  add(try("package.path",     function() return package.path end))
  add(try("dofile",           function() return type(dofile) end))
  add(try("loadfile",         function() return type(loadfile) end))
  add(try("load",             function() return type(load) end))
  add(try("utf8 library",     function() return type(require("utf8")) end))
  add(try("io.open (write)",  function()
    local f = io.open("C:\\Users\\Public\\Documents\\probe_test.txt", "w")
    if f then f:write("test"); f:close() return "writable" end
    return "nil handle"
  end))
  add(try("io.popen",         function() return type(io.popen) end))
  add(try("os.date",          function() return os.date("%Y") end))
  add(try("os.getenv",        function()
    local v = os.getenv
    if type(v) ~= "function" then return "NOT AVAILABLE (type=" .. type(v) .. ")" end
    return (v("TEMP") or "nil"):sub(1,30)
  end))
  hdr("")

  -- ── 2. Dialog API ─────────────────────────────────────────────────────────
  hdr("-- 2. Dialog / Input API --")
  local dialogs = {
    "InputQuery","InputBox","ShowMessage","MessageDlg","MessageDlgPos",
    "MessageDlgPosHelp","QuestionDlg","TaskMessageDlg","TaskMessageDlgPos",
    "CreateMessageDialog","SelectDirectory","PromptForFileName",
  }
  for _, name in ipairs(dialogs) do
    local v = _G[name]
    if v == nil then add(miss_line(name))
    else add(ok_line(name, type(v))) end
  end
  hdr("")

  -- ── 3. VCL constructors — deeper inspection ───────────────────────────────
  hdr("-- 3. VCL Constructors (deeper: MT type, property access, non-nil owner) --")
  local vcl_classes = {
    "TEdit","TPanel","TButton","TLabel","TRadioButton","TCheckBox",
    "TGroupBox","TText","TBitBtn","TForm","TMemo","TListBox","TComboBox",
    "TStringList","TTimer","TImage","TScrollBox","TPageControl","TTabSheet",
    "TTrackBar","TProgressBar","TSpinEdit",
  }
  -- Try to find a usable owner/parent reference first
  local owner_ref = _G["Owner"] or _G["Form"] or _G["MainForm"]

  for _, name in ipairs(vcl_classes) do
    local cls = _G[name]
    if cls == nil then
      add(miss_line(name))
    else
      -- try with nil owner
      local ok2, inst = pcall(function() return cls(nil) end)
      if ok2 and inst ~= nil then
        local mt = getmetatable(inst)
        local idx_type = mt and type(mt.__index) or "none"
        local method_count = 0
        local method_names = {}
        if mt and type(mt.__index) == "table" then
          for k in pairs(mt.__index) do
            method_count = method_count + 1
            if #method_names < 6 then method_names[#method_names+1] = k end
          end
        end
        -- if MT.__index is a function, try accessing common property names
        local prop_results = {}
        if mt and type(mt.__index) == "function" then
          for _, prop in ipairs({"Text","Caption","Name","Width","Height","Parent","Visible","Enabled","Color"}) do
            local pok, pv = pcall(function() return inst[prop] end)
            if pok and pv ~= nil then
              prop_results[#prop_results+1] = prop .. "=" .. tostring(pv):sub(1,15)
            end
          end
        end

        local detail = string.format("MT.__index=%s  methods=%d", idx_type, method_count)
        if #method_names > 0 then detail = detail .. "  e.g." .. table.concat(method_names,",") end
        if #prop_results > 0 then detail = detail .. "  props:" .. table.concat(prop_results,",") end
        add(ok_line(name, detail))

        -- try with owner_ref if we have one
        if owner_ref and owner_ref ~= nil then
          local ok3, inst2 = pcall(function() return cls(owner_ref) end)
          if ok3 and inst2 ~= nil then
            -- try setting Parent
            local pok = pcall(function() inst2.Parent = owner_ref end)
            add(ok_line(name .. "(owner_ref)", pok and "Parent set OK" or "no Parent setter"))
            pcall(function() if inst2.Free then inst2:Free() end end)
          else
            add(fail_line(name .. "(owner_ref)", tostring(inst2)))
          end
        end

        pcall(function() if inst.Free then inst:Free() end end)
      else
        add(fail_line(name, tostring(inst)))
      end
    end
  end
  hdr("")

  -- ── 4. Form / Owner globals ────────────────────────────────────────────────
  hdr("-- 4. Form / Owner / Screen globals --")
  local form_globals = {
    "Owner","Form","MainForm","Screen","Self","Parent",
    "PluginForm","PluginPanel","PluginPage","PluginTab",
  }
  for _, name in ipairs(form_globals) do
    local v = _G[name]
    if v == nil then
      add(miss_line(name))
    else
      local t = type(v)
      local mt = getmetatable(v)
      local idx_type = mt and type(mt.__index) or "no MT"
      local method_count = 0
      if mt and type(mt.__index) == "table" then
        for _ in pairs(mt.__index) do method_count = method_count + 1 end
      end
      -- try common form properties
      local props = {}
      for _, p in ipairs({"Caption","Name","Width","Height","ClientWidth","ClientHeight","ComponentCount"}) do
        local pok, pv = pcall(function() return v[p] end)
        if pok and pv ~= nil then props[#props+1] = p .. "=" .. tostring(pv):sub(1,20) end
      end
      add(ok_line(name,
        t .. "  MT.__index=" .. idx_type .. "  methods=" .. method_count ..
        (#props>0 and "  " .. table.concat(props,",") or "")))
    end
  end
  -- also try Application.MainForm
  add(try("Application.MainForm", function()
    local f = Application.MainForm
    if f == nil then return "nil" end
    local ok_c, c = pcall(function() return f.Caption end)
    return type(f) .. (ok_c and "  Caption=" .. tostring(c) or "")
  end))
  hdr("")

  -- ── 5. OnClose / lifecycle callbacks ──────────────────────────────────────
  hdr("-- 5. OnClose / plugin lifecycle callbacks --")
  -- Define candidate callbacks and see if FlashPro calls them (won't know until close)
  local close_candidates = {
    "OnPluginClose","OnClose","OnUnload","OnDestroy","OnFormClose",
    "OnPluginUnload","OnPluginDestroy","OnExit",
  }
  for _, name in ipairs(close_candidates) do
    local existing = _G[name]
    if existing ~= nil then
      add(ok_line(name, "ALREADY DEFINED  type=" .. type(existing)))
    else
      -- define a stub so FlashPro calls it if supported
      _G[name] = function(...)
        -- write to file so we know it was called even after deregistration
        local fh = io.open("C:\\Users\\Public\\Documents\\exporttune_close.txt","a")
        if fh then
          fh:write(os.date() .. " " .. name .. " called\n")
          fh:close()
        end
      end
      add(ok_line(name .. " (stub defined)", "will write to Public\\Documents\\exporttune_close.txt if called"))
    end
  end
  hdr("  >> Close Plugin Interface window now, then check exporttune_close.txt to see which fired")
  hdr("")

  -- ── 6. utilities ──────────────────────────────────────────────────────────
  hdr("-- 6. utilities module --")
  local ut_ok, ut_result = pcall(require, "utilities")
  if ut_ok then
    add(ok_line("require('utilities')", type(ut_result)))
    for _, fn in ipairs({"table_print","read_table_indexes","read_calibration_table","read_calibration_tablename"}) do
      local v = _G[fn]
      if v ~= nil then add(ok_line("global " .. fn, type(v)))
      else add(miss_line("global " .. fn)) end
    end
    if Calibration:loaded() then
      local rct_ok, rct = pcall(function()
        return read_calibration_tablename("Short term fuel trim maximum")
      end)
      if rct_ok and rct then
        add(ok_line("read_calibration_tablename()", "kind="..tostring(rct.kind).." unit="..tostring(rct.unitname)))
      else
        add(fail_line("read_calibration_tablename()", tostring(rct)))
      end
    end
  else
    add(fail_line("require('utilities')", ut_result))
  end
  hdr("")

  -- ── 7. Calibration string lookup ──────────────────────────────────────────
  hdr("-- 7. Calibration:table(string) --")
  if Calibration:loaded() then
    local ok5, t5 = pcall(function() return Calibration:table("Short term fuel trim maximum") end)
    if ok5 and t5 ~= nil then
      local ok_nm, nm = pcall(function() return t5:name() end)
      add(ok_line("Calibration:table(string)", ok_nm and "=> '"..tostring(nm).."'" or "object OK, name() failed"))
    elseif ok5 then
      add(fail_line("Calibration:table(string)", "returned nil"))
    else
      add(fail_line("Calibration:table(string)", t5))
    end
  else
    lines[#lines+1] = "SKIP  Calibration:table(string) — no calibration loaded"
    print(lines[#lines])
  end
  hdr("")

  -- ── 8. Application / Device / ECU ─────────────────────────────────────────
  hdr("-- 8. Application / Device / ECU --")
  for _, f in ipairs({"app","version","build","bit64","os"}) do
    add(try("Application." .. f, function() return tostring(Application[f]) end))
  end
  for _, f in ipairs({"name","connected","obdiivoltage","hardware","serial","vinlocked","datalogcount"}) do
    add(try("Device." .. f, function()
      local v = Device[f]
      return tostring(type(v)=="function" and v() or v)
    end))
  end
  add(try("ECU.ignitionon()",   function() return tostring(ECU.ignitionon()) end))
  add(try("ECU.recoverymode()", function() return tostring(ECU.recoverymode()) end))
  hdr("")

  -- ── 9. SensorList ─────────────────────────────────────────────────────────
  hdr("-- 9. SensorList --")
  add(try("SensorList:count()", function() return SensorList:count() end))
  add(try("SensorList['RPM']",  function()
    local s = SensorList["RPM"]
    return s and "name="..s:name().." min="..tostring(s:min()).." max="..tostring(s:max()) or "nil"
  end))
  add(try("SensorList:sensor(1)", function()
    local s = SensorList:sensor(1)
    return s and s:name() or "nil"
  end))
  add(try("sensor:live()", function()
    local s = SensorList["RPM"]
    return s and tostring(s:live()) or "no RPM"
  end))
  hdr("")

  -- ── 10. clipboard ─────────────────────────────────────────────────────────
  hdr("-- 10. Clipboard --")
  add(try("io.popen clip.exe", function()
    local h = io.popen('clip', 'w')
    if h then h:write("ExportTune probe " .. os.date("%H:%M:%S")); h:close(); return "OK" end
    return "nil handle"
  end))
  hdr("")

  -- ── summary ───────────────────────────────────────────────────────────────
  local summary = string.format(
    "=== SUMMARY: %d OK  %d FAIL  %d MISSING  %d SKIPPED ===",
    counts.ok, counts.fail, counts.miss, counts.skip)
  hdr(summary)
  hdr("Full output in Plugin Interface window above ^ and copied to clipboard.")
  hdr("Check C:\\Users\\Public\\Documents\\exporttune_close.txt after closing Plugin Interface.")

  -- copy to clipboard
  if copy_fn then copy_fn(table.concat(lines, "\n")) end

  -- ShowMessage: brief notice only — actual output is in the Plugin Interface window
  ShowMessage("ExportTune — API Probe complete.\n\n" .. summary ..
    "\n\nOutput is in the Plugin Interface window (scroll up).\n" ..
    "Full text also copied to clipboard.\n\n" ..
    "After clicking OK: close Plugin Interface to test OnClose callbacks,\n" ..
    "then check C:\\Users\\Public\\Documents\\exporttune_close.txt")
end

return M
