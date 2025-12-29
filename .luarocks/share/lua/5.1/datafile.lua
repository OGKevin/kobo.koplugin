
local datafile = {}

local util = require("datafile.util")

-- An array of datafile.openers, analog to package.searchers
datafile.openers = {}

local openers = {
   "datafile.openers.luarocks",
   "datafile.openers.caller",
   "datafile.openers.xdg",
   "datafile.openers.unix",
   "datafile.openers.windows",
}

-- Install openers, if present
for _, opener in ipairs(openers) do
   local ok, mod = pcall(require, opener)
   if ok then
      table.insert(datafile.openers, mod)
   end
end

-- Fallback opener
table.insert(datafile.openers, { get_dirs = function() return { "." } end })

function datafile.open(file, mode, context, open_fn)
   local tried = {}
   mode = mode or "r"
   for _, mod in ipairs(datafile.openers) do
      local fd, path
      if mod.opener then
         fd, path = mod.opener(file, mode, context)
      elseif mod.get_dirs then
         local dirs, err = mod.get_dirs(context, file, mode)
         if dirs then
            fd, path = util.try_dirs(dirs, file, mode, open_fn or io.open)
         elseif err then
            path = err
         end
      end
      if fd then
         return fd, path
      elseif path then
         tried[#tried+1] = path
      end
   end
   return nil, ("file '"..file.."' not found:\n"..table.concat(tried, "\n")):gsub("\n+", "\n\t")
end

local function find_file(file, mode)
   local ok, err, code = os.rename(file, file)
   if not ok then
      if code == 13 or code == 30 then
         -- Permission denied, but it exists
         if mode:match("w") then
            return nil, file .. ": " .. err
         else
            return true, file
         end
      end
      return nil, file .. ": " .. err
   end
   return true, file
end

function datafile.path(file, mode, context)
   local fd, path = datafile.open(file, mode or "r", context, find_file)
   if fd then
      return path
   end
   return nil, path
end

return datafile

