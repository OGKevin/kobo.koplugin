
--- @module datafile.openers.caller
-- datafile module based on caller's path.
local caller = {}

local util = require("datafile.util")

function caller.get_dirs()
   local level, source = util.stacklevel()
   if not level then return nil, source end
   source = source:gsub("\\", "/")
   if not source:match("^@") then return nil end
   local dirs = {}
   source = source:sub(2)
   -- Try to figure out how many levels of the pathname belong to the module.
   local no_extension = source:match("(.*)%.[^.]*$")
   local prefix = no_extension or source
   local suffix = ""
   local mod
   local dots = 0
   local added = false
   while true do
      prefix, mod = prefix:match("^(.+)/([^/]+)$")
      if not prefix then break end
      mod = mod..suffix
      if package.loaded[mod] then
         table.insert(dirs, prefix)
         added = true
         break
      end
      suffix = "."..mod
      dots = dots + 1
   end
   -- Finally, the exact location of the module.
   if dots > 0 or not added then
      local sourcedir = source:match("^(.+)/([^/]+)$")
      if sourcedir then
         table.insert(dirs, sourcedir)
      end
   end
   return dirs
end

return caller

