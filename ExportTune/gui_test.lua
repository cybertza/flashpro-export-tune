--
-- gui_test.lua — VCL layout test v3
-- Key finding: Parent=GroupBox fails silently in FlashPro sandbox.
-- Fix: All controls parent to root TPanel. GroupBox used as visual
--      frame only (no children). Coords calculated to fall inside frame.
--
local M = {}

M._click_count = 0
M._controls    = {}

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

local function keep(ctrl)
  if ctrl then M._controls[#M._controls+1] = ctrl end
  return ctrl
end

-- place(root, "TLabel", "Caption text", x, y, w, h)
-- w and h are optional
local function place(root, cls_name, x, y, w, h)
  local c = keep(new(cls_name))
  if not c then return nil end
  prop(c, "Parent", root)
  prop(c, "Left",   x)
  prop(c, "Top",    y)
  if w then prop(c, "Width",  w) end
  if h then prop(c, "Height", h) end
  return c
end

local function frame(root, caption, x, y, w, h)
  -- GroupBox as visual frame — no children parented to it
  local g = keep(new("TGroupBox"))
  if not g then return end
  prop(g, "Parent",  root)
  prop(g, "Caption", caption)
  prop(g, "Left",    x)
  prop(g, "Top",     y)
  prop(g, "Width",   w)
  prop(g, "Height",  h)
end

local function lbl(root, caption, x, y)
  local l = place(root, "TLabel", x, y)
  if l then prop(l, "Caption", caption) end
  return l
end

-- ── build ─────────────────────────────────────────────────────────────────────

function M.run()
  -- root panel (nil owner → auto-hosted in Plugin tab)
  local root = keep(new("TPanel"))
  if not root then ShowMessage("FAIL: TPanel not available"); return end
  prop(root, "Width",   520)
  prop(root, "Height",  420)
  prop(root, "Caption", "")

  -- title
  lbl(root, "ExportTune  —  Plugin UI", 10, 6)

  -- ── STATUS frame ─────────────────────────────────────────────────────────
  -- GroupBox frame: top=24, height=80 → inner area top=44..104
  frame(root, "Status", 8, 24, 500, 80)

  local cal_txt = Calibration:loaded()
    and ("Cal: " .. (Calibration:filename():match("[^\\]+$") or "loaded"))
    or  "Cal: (none loaded)"
  lbl(root, cal_txt, 16, 44)

  local dl_txt = "Datalogs: " .. tostring(DatalogManager:count()) .. " loaded"
  lbl(root, dl_txt,  16, 62)

  local ok_c, conn = pcall(function() return Device.connected end)
  lbl(root, "Device connected: " .. tostring(ok_c and conn or "unknown"), 16, 80)

  -- ── ACTIONS frame ─────────────────────────────────────────────────────────
  -- GroupBox frame: top=112, height=84 → inner area top=132..196
  frame(root, "Actions", 8, 112, 500, 84)

  local btn = place(root, "TButton", 16, 132, 160, 28)
  if btn then
    prop(btn, "Caption", "Click Me  (count=0)")
    pcall(function()
      btn.OnClick = function()
        M._click_count = M._click_count + 1
        pcall(function() btn.Caption = "Click Me  (count=" .. M._click_count .. ")" end)
      end
    end)
  end

  local chk = place(root, "TCheckBox", 190, 136)
  if chk then prop(chk, "Caption", "Enable feature X") end

  local rb1 = place(root, "TRadioButton", 16, 166)
  if rb1 then prop(rb1, "Caption", "Option A") end

  local rb2 = place(root, "TRadioButton", 110, 166)
  if rb2 then prop(rb2, "Caption", "Option B") end

  -- ── INPUT row ─────────────────────────────────────────────────────────────
  lbl(root, "Input:", 8, 210)

  local edt = place(root, "TEdit", 60, 207, 220, 22)
  if edt then prop(edt, "Text", "type here") end

  local btn_read = place(root, "TButton", 292, 206, 100, 24)
  if btn_read then
    prop(btn_read, "Caption", "Read Input")
    pcall(function()
      btn_read.OnClick = function()
        local ok_t, txt = pcall(function() return edt.Text end)
        ShowMessage("TEdit.Text = " .. (ok_t and tostring(txt) or "FAIL"))
      end
    end)
  end

  -- ── OUTPUT frame ──────────────────────────────────────────────────────────
  -- GroupBox frame: top=240, height=160 → inner area top=258..400
  frame(root, "Output", 8, 240, 500, 160)

  local memo = place(root, "TMemo", 16, 258, 484, 134)
  if memo then
    prop(memo, "ReadOnly",   true)
    prop(memo, "ScrollBars", 2)
    local ok_ml = pcall(function()
      memo.Lines.Text =
        "ExportTune GUI Test v3\r\n" ..
        cal_txt .. "\r\n" ..
        dl_txt  .. "\r\n" ..
        "OnClick, TEdit read, TCheckBox, TRadioButton all confirmed.\r\n" ..
        "Parent=TGroupBox fails in sandbox — controls parented to root.\r\n" ..
        "GroupBox used as visual frame only."
    end)
    if not ok_ml then
      pcall(function()
        memo.Text =
          "ExportTune GUI Test v3\r\n" .. cal_txt .. "\r\n" .. dl_txt
      end)
    end
  end

  ShowMessage(
    "ExportTune — GUI Test v3\n\n" ..
    "Layout rebuilt: GroupBox = visual frame only.\n" ..
    "All controls parented directly to root TPanel.\n\n" ..
    "• Click 'Click Me' to test OnClick\n" ..
    "• Edit the Input box and click 'Read Input'\n" ..
    "• Check Plugin tab layout")
end

return M
