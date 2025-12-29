local split = require('cliargs.utils.split')

local function buildline(words, size, overflow)
  -- if overflow is set, a word longer than size, will overflow the size
  -- otherwise it will be chopped in line-length pieces
  local line = {}
  if #words[1] > size then
    -- word longer than line
    if overflow then
      line[1] = words[1]
      table.remove(words, 1)
    else
      line[1] = words[1]:sub(1, size)
      words[1] = words[1]:sub(size + 1, -1)
    end
  else
    local len = 0
    while words[1] and (len + #words[1] + 1 <= size) or (len == 0 and #words[1] == size) do
      line[#line+1] = words[1]
      len = len + #words[1] + 1
      table.remove(words, 1)
    end
  end
  return table.concat(line, " "), words
end

local function wordwrap(str, size, overflow)
  -- if overflow is set, then words longer than a line will overflow
  -- otherwise, they'll be chopped in pieces
  local out, words = {}, split(str, ' ')
  while words[1] do
    out[#out+1], words = buildline(words, size, overflow)
  end
  return out
end

return wordwrap