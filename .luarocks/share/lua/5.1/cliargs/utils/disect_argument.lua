local function disect_argument(str)
  local _, symbol, key, value
  local negated = false

  _, _, symbol, key = str:find("^([%-]*)(.*)")

  if key then
    local actual_key

    -- split value and key
    _, _, actual_key, value = key:find("([^%=]+)[%=]?(.*)")

    if value then
      key = actual_key
    end

    if key:sub(1,3) == "no-" then
      key = key:sub(4,-1)
      negated = true
    end
  end

  -- no leading symbol means the sole fragment is the value.
  if #symbol == 0 then
    value = str
    key = nil
  end

  return
    #symbol > 0 and symbol or nil,
    key and #key > 0 and key or nil,
    value and #value > 0 and value or nil,
    negated and true or false
end

return disect_argument