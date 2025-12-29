
--- @module datafile.openers.xdg
-- datafile module following the freedesktop.org XDG Base Directory Specification
-- http://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html
local xdg = {}

local function split(var)
   local list = {}
   for entry in var:gmatch("([^:]+)") do
      list[#list+1] = entry
   end
   return list
end

local HOME = os.getenv("HOME")
local XDG_DATA_HOME   = os.getenv("XDG_DATA_HOME")   or (HOME and HOME.."/.local/share")
local XDG_CONFIG_HOME = os.getenv("XDG_CONFIG_HOME") or (HOME and HOME.."/.config")
local XDG_CACHE_HOME  = os.getenv("XDG_CACHE_HOME")  or (HOME and HOME.."/.cache")
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR")

local XDG_DATA_DIRS = split(os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share")
if XDG_DATA_HOME then
  table.insert(XDG_DATA_DIRS, 1, XDG_DATA_HOME)
end
table.insert(XDG_DATA_DIRS, XDG_RUNTIME_DIR)

local XDG_CONFIG_DIRS = split(os.getenv("XDG_CONFIG_DIRS") or "/etc/xdg")
if XDG_CONFIG_HOME then
  table.insert(XDG_CONFIG_DIRS, 1, XDG_CONFIG_HOME)
end

local XDG_CACHE_DIRS = {}
table.insert(XDG_CACHE_DIRS, XDG_CACHE_HOME)
table.insert(XDG_CACHE_DIRS, XDG_RUNTIME_DIR)

function xdg.get_dirs(context)
   local dirs = XDG_DATA_DIRS
   if context == "config" then
      dirs = XDG_CONFIG_DIRS
   elseif context == "cache" then
      dirs = XDG_CACHE_DIRS
   end
   return dirs
end

return xdg
