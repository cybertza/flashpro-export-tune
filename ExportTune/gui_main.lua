--
-- gui_main.lua — persistent Plugin-tab UI (option 10)
-- Confirmed working in sandbox: TPanel, TButton, TCheckBox, TRadioButton, TMemo, TEdit
-- NOT working: TLabel (invisible), TPageControl/TTabSheet (child coords broken)
-- Layout strategy: TButton for section headers, TMemo for status + log output
--
local M = {}

M._controls = {}
M._memo     = nil   -- log TMemo ref

-- ── helpers ───────────────────────────────────────────────────────────────────

local function prop(ctrl, k, v)
  pcall(function() ctrl[k] = v end)
end

local function new(cls_name)
  local cls = _G[cls_name]
  if not cls then return nil end
  local ok, inst = pcall(function() return cls(nil) end)
  return (ok and inst) or nil
end

local function keep(c) if c then M._controls[#M._controls+1] = c end; return c end

local function place(root, cls_name, x, y, w, h)
  local c = keep(new(cls_name))
  if not c then return nil end
  prop(c, "Parent", root)
  prop(c, "Left", x);  prop(c, "Top", y)
  if w then prop(c, "Width",  w) end
  if h then prop(c, "Height", h) end
  return c
end

local function btn(root, caption, x, y, w, h, onclick)
  local b = place(root, "TButton", x, y, w or 130, h or 26)
  if b then
    prop(b, "Caption", caption)
    if onclick then pcall(function() b.OnClick = onclick end) end
  end
  return b
end

-- Section header: flat TButton, no action, acts as visual divider/label
local function hdr(root, title, y, W)
  local b = place(root, "TButton", 0, y, W, 22)
  if b then
    prop(b, "Caption", title)
    prop(b, "Flat",    true)
  end
  return b
end

-- ── log pane ──────────────────────────────────────────────────────────────────

function M.log(line)
  if not M._memo then return end
  pcall(function() M._memo.Lines.Add(tostring(line)) end)
end

function M.log_clear()
  if not M._memo then return end
  pcall(function() M._memo.Lines.Clear() end)
end

-- Run fn() with print() captured into the log pane.
-- GUI operations do NOT open the console tab this way.
local function with_log(label, fn)
  M.log("")
  M.log(">> " .. label .. " (" .. os.date("%H:%M:%S") .. ")")
  M.log(string.rep("-", 46))
  local orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    M.log(table.concat(parts, '\t'))
  end
  local ok, err = pcall(fn)
  print = orig_print
  if not ok then M.log("ERROR: " .. tostring(err)) end
  M.log(string.rep("-", 46))
end

-- ── build ─────────────────────────────────────────────────────────────────────

function M.run(get_cal_dir_fn, export_fn, import_fn, health_fn, tools_fns)
  M._controls = {}
  M._memo     = nil

  local root = keep(new("TPanel"))
  if not root then ShowMessage("FAIL: TPanel unavailable"); return end

  local W = 516
  prop(root, "Width",   W)
  prop(root, "Height",  660)
  prop(root, "Caption", "")

  local y = 0

  -- ── top bar ────────────────────────────────────────────────────────────────
  -- TLabel invisible in sandbox — use TButton for "label" text
  local title_btn = place(root, "TButton", 0, y, 380, 26)
  if title_btn then
    prop(title_btn, "Caption", "ExportTune  v" .. (type(VERSION)=="string" and VERSION or "?"))
    prop(title_btn, "Flat", true)
  end
  btn(root, "Open Menu", 388, y, 120, 26, function() show_menu() end)
  y = y + 28

  -- ── status TMemo (read-only info box) ─────────────────────────────────────
  local cal_loaded = Calibration:loaded()
  local cal_file   = cal_loaded and Calibration:filename() or "(none)"
  local cal_name   = cal_file:match("[^\\]+$") or cal_file
  local tbl_n      = cal_loaded and tostring(Calibration:tablecount()) or "--"
  local ok_c, conn  = pcall(function() return Device.connected  end)
  local ok_n, dname = pcall(function() return Device.name       end)

  local status_memo = place(root, "TMemo", 0, y, W, 68)
  if status_memo then
    prop(status_memo, "ReadOnly",   true)
    prop(status_memo, "ScrollBars", 0)   -- ssNone
    prop(status_memo, "WantReturns", false)
    pcall(function()
      status_memo.Lines.Add("Cal     : " .. cal_name)
      status_memo.Lines.Add("Tables  : " .. tbl_n ..
        "   Datalogs: " .. tostring(DatalogManager:count()) .. " loaded")
      status_memo.Lines.Add("Device  : " .. tostring(ok_n and dname or "unknown") ..
        "   connected=" .. tostring(ok_c and conn or "?"))
      status_memo.Lines.Add("NOTE: closing this window deregisters the plugin (FlashPro limit).")
    end)
  end
  y = y + 70

  -- ── EXPORT ─────────────────────────────────────────────────────────────────
  hdr(root, "EXPORT", y, W); y = y + 24

  btn(root, "Full Export",  4,   y, 156, 26, function()
    with_log("Full Export", function() export_fn("full") end) end)
  btn(root, "Cal Only",    168,  y, 120, 26, function()
    with_log("Cal Export",  function() export_fn("cal")  end) end)
  btn(root, "Datalog Only",296,  y, 130, 26, function()
    with_log("DL Export",   function() export_fn("dl")   end) end)
  y = y + 30

  -- ── IMPORT ─────────────────────────────────────────────────────────────────
  hdr(root, "IMPORT", y, W); y = y + 24

  btn(root, "Preview (dry run)", 4, y, 170, 26, function()
    with_log("Import Preview", function()
      import_fn(true, get_cal_dir_fn())
    end)
  end)
  btn(root, "Apply Changes (!WRITES!)", 182, y, 210, 26, function()
    local cal_path = Calibration:loaded() and Calibration:filename() or "your .fpcal file"
    local c = InputQuery("ExportTune - Confirm Write",
      "!! This will MODIFY your calibration !!\n\n" ..
      "Ensure you have a backup of:\n" ..
      cal_path .. "\n\n" ..
      "AI-generated changes must be reviewed by a\n" ..
      "qualified tuner before driving the vehicle.\n\n" ..
      "---\n" ..
      "ExportTune is free and open source.\n" ..
      "If this saved you time, or you charged a customer\n" ..
      "for a tune using it - please consider a small\n" ..
      "donation to support further development:\n" ..
      "github.com/sponsors/cybertza\n" ..
      "We trust you. That's why there is no paywall. :)\n" ..
      "---\n\n" ..
      "Type YES to continue:", "")
    if c == "YES" then
      with_log("Apply Import", function()
        import_fn(false, get_cal_dir_fn())
      end)
    end
  end)
  y = y + 30

  -- ── HEALTH ─────────────────────────────────────────────────────────────────
  hdr(root, "HEALTH", y, W); y = y + 24

  btn(root, "Run Health Check", 4, y, 170, 26, function()
    with_log("Health Check", function() health_fn() end)
  end)
  y = y + 30

  -- ── TOOLS ──────────────────────────────────────────────────────────────────
  if tools_fns then
    hdr(root, "TOOLS", y, W); y = y + 24
    if tools_fns.probe then
      btn(root, "API Probe", 4, y, 120, 26, function()
        with_log("API Probe", function()
          tools_fns.probe()
        end)
      end)
    end
    if tools_fns.debug then
      btn(root, "Debug Dump", 132, y, 120, 26, function()
        with_log("Debug Dump", function()
          tools_fns.debug()
        end)
      end)
    end
    if tools_fns.gui_test then
      btn(root, "GUI Test", 260, y, 100, 26, tools_fns.gui_test)
    end
    y = y + 30
  end

  -- ── LOG PANE ───────────────────────────────────────────────────────────────
  hdr(root, "LOG", y, W - 70); y = y + 2
  btn(root, "Clear", W - 66, y - 22, 62, 22, function() M.log_clear() end)

  local log_h = 660 - y - 2
  local memo = place(root, "TMemo", 0, y, W, log_h)
  if memo then
    prop(memo, "ScrollBars", 2)   -- ssVertical
    pcall(function() memo.Font.Name = "Courier New" end)
    pcall(function() memo.Font.Size = 8 end)
    M._memo = memo
    M.log("ExportTune  v" .. (type(VERSION)=="string" and VERSION or "?") ..
      "   " .. os.date("%Y-%m-%d %H:%M:%S"))
    M.log("Cal: " .. cal_name .. "   Tables: " .. tbl_n)
    M.log("Ready.  Use the buttons above.")
  end
end

return M
