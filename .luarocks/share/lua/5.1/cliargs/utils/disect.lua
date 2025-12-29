local split = require('cliargs.utils.split')

local RE_ADD_COMMA = "^%-([%a%d]+)[%s]%-%-"
local RE_ADJUST_DELIMITER = "(%-%-?)([%a%d]+)[%s]"

-- parameterize the key if needed, possible variations:
--
--     -key
--     -key VALUE
--     -key=VALUE
--
--     -key, --expanded
--     -key, --expanded VALUE
--     -key, --expanded=VALUE
--
--     -key --expanded
--     -key --expanded VALUE
--     -key --expanded=VALUE
--
--     --expanded
--     --expanded VALUE
--     --expanded=VALUE
local function disect(key)
  -- characters allowed are a-z, A-Z, 0-9
  -- extended + values also allow; # @ _ + -
  local k, ek, v, _
  local dummy

  -- leading "-" or "--"
  local prefix

  -- if there is no comma, between short and extended, add one
  _, _, dummy = key:find(RE_ADD_COMMA)
  if dummy then
    key = key:gsub(RE_ADD_COMMA, "-" .. dummy .. ", --", 1)
  end

  -- replace space delimiting the value indicator by "="
  --
  --     -key VALUE => -key=VALUE
  --     --expanded-key VALUE => --expanded-key=VALUE
  _, _, prefix, dummy = key:find(RE_ADJUST_DELIMITER)
  if prefix and dummy then
    key = key:gsub(RE_ADJUST_DELIMITER, prefix .. dummy .. "=", 1)
  end

  -- if there is no "=", then append one
  if not key:find("=") then
    key = key .. "="
  end

  -- get value
  _, _, v = key:find(".-%=(.+)")

  -- get key(s), remove spaces
  key = split(key, "=")[1]:gsub(" ", "")

  -- get short key & extended key
  _, _, k = key:find("^%-([^-][^%s,]*)")
  _, _, ek = key:find("%-%-(.+)$")

  if v == "" then
    v = nil
  end

  return k,ek,v
end

return disect