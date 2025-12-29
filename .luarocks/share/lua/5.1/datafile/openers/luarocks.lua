
--- @module datafile.openers.luarocks
-- datafile module for modules installed with LuaRocks
local luarocks = {}

local ok, path = pcall(require, "luarocks.path")
if not ok then
   -- LuaRocks not found, bail out!
   return {}
end
local manif_core, _
ok, manif_core = pcall(require, "luarocks.manif_core") -- LuaRocks 2
if not ok then
   local pok, cfg = pcall(require, "luarocks.core.cfg")
   if pok then
      pcall(cfg.init)
      _, manif_core = pcall(require, "luarocks.core.manif") -- LuaRocks 3
   end
end
if not manif_core then
   -- LuaRocks not found, bail out!
   return {}
end

local load_local_manifest = manif_core.load_local_manifest  -- LuaRocks 2
load_local_manifest = load_local_manifest or manif_core.fast_load_local_manifest  --LuaRocks 3

local cfg
ok, cfg = pcall(require, "luarocks.cfg") -- LuaRocks 2
if not ok then
   _, cfg = pcall(require, "luarocks.core.cfg") -- LuaRocks 3
end
if cfg then
   if not cfg.lua_extension then -- cfg not initialized
      if cfg.init then
         local cfg_ok, err = cfg.init()
         if cfg_ok and cfg.init_package_paths then
            cfg.init_package_paths()
         end
      end
   end
end
if not (cfg and cfg.lua_extension) then
   -- cfg still not initialized, bail out!
   return {}
end

local util = require("datafile.util")

function luarocks.get_dirs()
   local level, source = util.stacklevel()
   if not level then return nil, source end
   source = source:gsub("\\", "/")
   if source:match("^@") then
      local prefix, luaver, modpath = source:match("@(.*)/share/lua/([^/]*)/(.*)")
      if prefix and luaver and modpath then
         local modname = path.path_to_module(modpath):gsub("\\","."):gsub("/",".")
         local rocks_dir = prefix.."/lib/luarocks/rocks-"..luaver
         local manifest = load_local_manifest(rocks_dir)
         if not manifest then -- look for generic rocks_dir
            rocks_dir = prefix.."/lib/luarocks/rocks"
            manifest = load_local_manifest(rocks_dir)
         end
         if not manifest then
            return nil, "could not open LuaRocks manifest for "..prefix
         end
         local providers = manifest.modules[modname]

         -- try versioned module names
         while not providers do
            local strip = modname:match("(.*)_[^_]+")
            if not strip then break end
            providers = manifest.modules[strip]
         end
         local dirs = {
            prefix .. "/share/lua/" .. luaver,
            prefix .. "/lib/lua/" .. luaver,
         }

         if providers then
            for _, provider in ipairs(providers) do
               table.insert(dirs, prefix .. "/lib/luarocks/rocks/" .. provider)
               table.insert(dirs, prefix .. "/lib/luarocks/rocks-"..luaver.."/" .. provider)
            end
         end
         return dirs
      else
         local rockdir
         rockdir, prefix, luaver = source:match("@((.*)/lib/luarocks/rocks%-?([^/]*)/[^/]*/[^/]*)/.*$")
         if prefix and luaver and rockdir then
            luaver = luaver ~= "" and luaver or _VERSION:match(" ([^ ]+)$")
            local dirs = {
               prefix .. "/share/lua/" .. luaver,
               prefix .. "/lib/lua/" .. luaver,
               rockdir
            }
            return dirs
         end
      end
   end
   return nil, "could not recognize "..source.." as a LuaRocks module"
end

return luarocks

