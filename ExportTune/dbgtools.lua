--
-- debug.lua — global dump, VCL inspection, clipboard helper
--
local M = {}

-- ── clipboard ─────────────────────────────────────────────────────────────────

function M.copy_to_clip(text)
  local ok, h = pcall(io.popen, 'clip', 'w')
  if ok and h then
    h:write(text)
    h:close()
    return true
  end
  return false
end

-- ── global inspector ─────────────────────────────────────────────────────────

local INTERESTING_GLOBALS = {
  "TEdit","TPanel","TButton","TLabel","TRadioButton","TCheckBox",
  "TForm","TMemo","TListBox","TComboBox","TGroupBox","TText","TBitBtn",
  "Application","Device","ECU",
  "Calibration","DatalogManager","SensorList","ErrorCodeList",
  "MainForm","Form","Screen","Owner",
  "Clipboard","TClipboard",
  "dl_loaded","cal_loaded","utilities",
}

local function dump_global_val(label, val)
  if val == nil then print("  [" .. label .. "] = nil"); return end
  local t = type(val)
  print("  [" .. label .. "] type=" .. t)
  if t == "table" or t == "userdata" then
    if t == "table" then
      local keys = {}
      for k in pairs(val) do keys[#keys+1] = k end
      table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
      for _,k in ipairs(keys) do
        local v = val[k]
        local vt = type(v)
        local vs = vt=="function" and "function()" or vt=="table" and "{...}" or tostring(v)
        print(string.format("    .%-30s %s (%s)", tostring(k), vs, vt))
      end
    end
    local mt = getmetatable(val)
    if mt then
      print("    [has metatable]")
      if type(mt) == "table" then
        for k,v in pairs(mt) do
          print(string.format("    MT.%-28s %s (%s)", tostring(k), tostring(v), type(v)))
        end
      end
    end
  end
end

local function dump_global(name)
  local val = _G[name]
  if val == nil then
    print("  [" .. name .. "] = nil (not in globals)")
    return
  end
  dump_global_val(name, val)
end

-- ── main debug action ─────────────────────────────────────────────────────────

function M.run()
  local target = InputQuery("ExportTune — Debug",
    "Dump a Lua global to console.\n\n" ..
    "Known interesting globals:\n" ..
    "  TEdit  TPanel  TButton  TLabel  TRadioButton\n" ..
    "  TCheckBox  TForm  TMemo  TText  TBitBtn\n" ..
    "  Application  Device  ECU  Clipboard  TClipboard\n" ..
    "  Calibration  DatalogManager  SensorList\n\n" ..
    "Special targets:\n" ..
    "  *            dump all known globals\n" ..
    "  globals      list everything in _G\n" ..
    "  dialogs      probe all dialog/input API variants\n" ..
    "  clipboard    probe clipboard API access\n" ..
    "  call:TEdit   try to instantiate TEdit(nil)\n\n" ..
    "Output is printed to console AND copied to clipboard.\n\n" ..
    "Enter target:", "globals")
  if not target then print("Debug cancelled."); return end

  local buf = {}
  local orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    local line = table.concat(parts, '\t')
    orig_print(line)
    buf[#buf+1] = line
  end

  if target == "*" then
    for _,name in ipairs(INTERESTING_GLOBALS) do
      dump_global(name)
      print("")
    end

  elseif target == "globals" then
    print("  Scanning all _G keys...")
    local keys = {}
    for k in pairs(_G) do keys[#keys+1] = tostring(k) end
    table.sort(keys)
    for _,k in ipairs(keys) do
      local v = _G[k]
      local t = type(v)
      if t ~= "function" or k:sub(1,1) ~= k:sub(1,1):lower() then
        print(string.format("  %-32s %s", k, t))
      end
    end

  elseif target == "dialogs" then
    local candidates = {
      "InputQuery","InputBox","ShowMessage","ShowMessageFmt",
      "MessageDlg","MessageDlgPos","MessageDlgPosHelp",
      "CreateMessageDialog","QuestionDlg",
      "TaskMessageDlg","TaskMessageDlgPos",
      "SelectDirectory","PromptForFileName",
    }
    print("  Probing dialog/input API variants...")
    for _,name in ipairs(candidates) do
      local v = _G[name]
      if v == nil then
        print(string.format("  %-30s MISSING", name))
      else
        print(string.format("  %-30s %s", name, type(v)))
      end
    end
    print("")
    print("  Testing InputQuery('Test','Probe','ok') ...")
    local ok, result = pcall(InputQuery, "Test", "Probe", "ok")
    if ok then
      print("  InputQuery returned: " .. tostring(result))
    else
      print("  InputQuery ERROR: " .. tostring(result))
    end

  elseif target == "clipboard" then
    print("  Probing clipboard access...")
    local cb = _G["Clipboard"]
    print("  Clipboard global: " .. type(cb))
    if cb then dump_global_val("Clipboard", cb) end
    print("")
    local tc = _G["TClipboard"]
    print("  TClipboard class: " .. type(tc))
    if tc then dump_global_val("TClipboard", tc) end
    print("")
    print("  Testing clip.exe via io.popen...")
    local test_text = "ExportTune clipboard test"
    local clipped = M.copy_to_clip(test_text)
    if clipped then
      print("  clip.exe: SUCCESS — '" .. test_text .. "' sent to clipboard")
    else
      print("  clip.exe: FAILED — io.popen('clip','w') not available")
    end
    print("  Attempting clipboard read via PowerShell...")
    local ok3, h3 = pcall(io.popen, 'powershell -NoProfile -Command "Get-Clipboard"')
    if ok3 and h3 then
      local out = h3:read('*a')
      h3:close()
      print("  PowerShell Get-Clipboard: " .. (out and out:gsub('%s+$','') or "nil"))
    else
      print("  PowerShell read: FAILED")
    end

  elseif target:sub(1,5) == "call:" then
    local cls_name = target:sub(6)
    local cls = _G[cls_name]
    if not cls then
      print("  " .. cls_name .. " not found in globals")
    else
      print("  " .. cls_name .. " type: " .. type(cls))
      local ok2, result = pcall(function() return cls(nil) end)
      if ok2 and result ~= nil then
        print("  Instantiated successfully")
        local mt = getmetatable(result)
        if mt then
          print("  Instance metatable:")
          if type(mt) == "table" then
            local mkeys = {}
            for k in pairs(mt) do mkeys[#mkeys+1] = tostring(k) end
            table.sort(mkeys)
            for _,k in ipairs(mkeys) do
              local v = mt[k]
              print(string.format("    MT.%-28s %s  %s",
                k, type(v), tostring(v):sub(1,40)))
            end
            if type(mt.__index) == "table" then
              print("  MT.__index methods:")
              local ikeys = {}
              for k in pairs(mt.__index) do ikeys[#ikeys+1] = tostring(k) end
              table.sort(ikeys)
              for _,k in ipairs(ikeys) do
                print(string.format("    .%-30s %s", k, type(mt.__index[k])))
              end
            end
          end
        else
          print("  (no metatable on instance)")
        end
        pcall(function() if result.Free then result:Free() end end)
      else
        print("  ERROR: " .. tostring(result))
      end
    end

  else
    dump_global(target)
  end

  print = orig_print

  orig_print("--- BEGIN DEBUG OUTPUT: " .. target .. " (" .. #buf .. " lines) ---")
  for _,line in ipairs(buf) do orig_print(line) end
  orig_print("--- END DEBUG OUTPUT ---")

  local full_text = "ExportTune Debug: " .. target .. "\n\n" .. table.concat(buf,'\n') .. "\n"
  local clipped = M.copy_to_clip(full_text)

  local MAX = 80
  local preview = buf
  local note = ""
  if #buf > MAX then
    preview = {}
    for i=1,MAX do preview[i]=buf[i] end
    note = "\n... (" .. (#buf-MAX) .. " more lines — see console)"
  end
  local clip_note = clipped and "\n[Full output copied to clipboard]" or ""
  ShowMessage("ExportTune — Debug: " .. target .. clip_note .. "\n\n" ..
    table.concat(preview,'\n') .. note)
end

return M
