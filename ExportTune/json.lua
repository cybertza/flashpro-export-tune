--
-- json.lua — minimal JSON encoder/decoder
-- No FlashPro API dependencies; safe to require anywhere.
--
local M = {}

function M.esc(s)
  if s == nil then return "null" end
  s = tostring(s)
  s = s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')
  return '"' .. s .. '"'
end

function M.num(v)
  if v == nil then return "null" end
  local n = tonumber(v)
  if not n or n ~= n or n == math.huge or n == -math.huge then return "null" end
  return tostring(n)
end

-- ── decoder ───────────────────────────────────────────────────────────────────

local function skip_ws(s, i)
  while i <= #s and s:sub(i,i):match('%s') do i = i+1 end
  return i
end

local function parse_value(s, i)
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

function M.decode(s)
  local ok, result = pcall(parse_value, s, 1)
  if ok then return result end
  return nil, result
end

return M
