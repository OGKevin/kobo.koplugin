return function(t, k, v)
  local out = {}

  for _, item in ipairs(t) do
    if item[k] == v then
      table.insert(out, item)
    end
  end

  return out
end