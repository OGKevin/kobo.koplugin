-- courtesy of the jungle: http://lua-users.org/wiki/StringTrim
return function(str)
  return str:match "^%s*(.-)%s*$"
end