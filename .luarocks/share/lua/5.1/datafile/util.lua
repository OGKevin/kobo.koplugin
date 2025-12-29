
-- utilities for the implementation of datafile modules
local util = {}

-- cache separator
local sep
if (package.config and package.config:sub(1,1) == "\\") or package.path:match("\\") then
   sep = "\\"
else
   sep = "/"
end

function util.try_dirs(dirs, file, mode, open_fn)
   local tried = {}
   for _, dir in ipairs(dirs) do
      local path
      if dir:sub(-1) == "|" then
         path = (dir:sub(1,-2)..file)
      else
         path = (dir..sep..file)
      end
      path = path:gsub(sep.."+", sep)
      local fd, err = (open_fn or io.open)(path, mode)
      if fd then return fd, path end
      tried[#tried+1] = "can't open "..err
   end
   return nil, table.concat(tried, "\n")
end

-- returns the stack level (for the caller) + sourcefile from where
-- 'datafile' module was called or nil + error
function util.stacklevel()
   local level = 1
   local df_found = false
   local src_info
   local src_level
   while true do
      local info = debug.getinfo(level, "Sn")
      if not info then
         break
      end
      if info.source:match("datafile.lua$") then
         df_found = true
      elseif df_found then
         df_found = false
         src_info = info
         src_level = level
      end
      level = level + 1  -- inc before check because we need the match + 1
   end
   if not src_info then
      return nil, "could not determine the code file on the callstack to look up"
   else
      return src_level - 1, src_info.source  -- use -1 to substract the call to this function
   end
end

return util
