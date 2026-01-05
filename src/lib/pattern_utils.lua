---
--- Pattern utilities for safe Lua pattern matching.
--- @module PatternUtils

local PatternUtils = {}

---
--- Escape special pattern characters in a string for use in Lua pattern matching.
--- This escapes all Lua magic pattern characters: ^$()%.[]*+-%?
--- @param str string: The string to escape.
--- @return string: The escaped string safe for use in Lua patterns.
function PatternUtils.escape(str)
    if not str or type(str) ~= "string" then
        return str
    end

    return (str:gsub("([%.%-%+%[%]%(%)%$%^%%%?%*])", "%%%1"))
end

return PatternUtils
