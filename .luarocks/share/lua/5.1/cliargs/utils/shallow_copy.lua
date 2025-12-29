-- courtesy of http://lua-users.org/wiki/CopyTable
local function shallow_copy(orig)
  if type(orig) == 'table' then
    local copy = {}

    for orig_key, orig_value in pairs(orig) do
      copy[orig_key] = orig_value
    end

    return copy
  else -- number, string, boolean, etc
    return orig
  end
end

return shallow_copy