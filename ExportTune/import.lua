--
-- import.lua — reads tune_import.json and applies changes to the calibration
-- Depends on: json
--
local json = require("json")

local M = {}

-- Calibration:table(name) confirmed working (probe 2026-04-21) — no cache needed

function M.clear_cache()
  -- kept for API compatibility with event callbacks; nothing to clear
end

-- ── per-change applier ────────────────────────────────────────────────────────

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
      if not ok then print("    ERROR applying: " .. tostring(err)); return false end
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
      print(string.format("  ERROR [%s] values length %d != table length %d", name, #new_vals, len))
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
          local ok, err = pcall(function() t:setvalue(nv, c, r) end)
          if not ok then
            print(string.format("  ERROR at [%d,%d]: %s", c, r, tostring(err)))
            return false
          end
        end
      end
    end
    return true

  elseif kind == "Table3D" then
    local new_pages = change["pages"]
    if type(new_pages) ~= "table" then
      print("  ERROR [" .. name .. "] 'pages' array required for Table3D")
      return false
    end
    local i1 = t:index(1)
    local i2 = t:index(2)
    local i3 = t:index(3)
    local cols  = i1:length()
    local rows  = i2:length()
    local pages = i3:length()
    print(string.format("  %s  %-45s  (%dx%dx%d)",
      dry_run and "PREVIEW" or "SET    ", name, cols, rows, pages))
    if #new_pages ~= pages then
      print(string.format("  ERROR [%s] page count %d != %d", name, #new_pages, pages))
      return false
    end
    for p=1,pages do
      local page = new_pages[p]
      if type(page) ~= "table" or #page ~= rows then
        print(string.format("  ERROR [%s] page %d has %d rows, expected %d",
          name, p, type(page)=="table" and #page or 0, rows))
        return false
      end
      for r=1,rows do
        local row = page[r]
        if type(row) ~= "table" or #row ~= cols then
          print(string.format("  ERROR [%s] page %d row %d has %d cols, expected %d",
            name, p, r, type(row)=="table" and #row or 0, cols))
          return false
        end
        for c=1,cols do
          local nv = tonumber(row[c])
          if not nv then
            print(string.format("  ERROR [%s] non-numeric at page %d row %d col %d", name, p, r, c))
            return false
          end
          if not dry_run then
            local ok, err = pcall(function() t:setvalue(nv, c, r, p) end)
            if not ok then
              print(string.format("  ERROR at [%d,%d,%d]: %s", c, r, p, tostring(err)))
              return false
            end
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

-- ── main import runner ────────────────────────────────────────────────────────

function M.run(dry_run, cal_dir)
  if not cal_dir then
    print("ERROR: No calibration loaded — cannot locate import file")
    return
  end

  local import_file = cal_dir .. "\\tune_import.json"
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
    print("Mode        : DRY RUN (preview only — no changes applied)")
  else
    print("Mode        : LIVE (changes will be written to calibration)")
  end
  print("")

  local applied, skipped, errors = 0, 0, 0

  for _,change in ipairs(changes) do
    local name = change["name"]
    if not name then
      print("  ERROR: change entry missing 'name' field")
      errors = errors + 1
    else
      local ok_t, t = pcall(function() return Calibration:table(name) end)
      if not ok_t or t == nil then
        print("  NOT FOUND  " .. name)
        errors = errors + 1
      else
        -- skip readonly tables
        local ok_ro, ro = pcall(function() return t:readonly() end)
        if ok_ro and ro then
          print("  SKIP (readonly)  " .. name)
          skipped = skipped + 1
        else
          local ok = apply_change(t, change, dry_run)
          if ok then applied = applied + 1 else skipped = skipped + 1 end
        end
      end
    end
  end

  print("")
  print(string.format("  Applied: %d   Skipped: %d   Errors: %d", applied, skipped, errors))

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

return M
