package = "datafile"
version = "0.11-1"
source = {
   url = "git://github.com/hishamhm/datafile.git",
   tag = "v0.11"
}
description = {
   summary = "A library for handling paths when loading data files",
   detailed = [[
      datafile is a library for avoiding hardcoded paths
      when loading resource files in Lua modules.
   ]],
   homepage = "http://github.com/hishamhm/datafile",
   license = "MIT/X11"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      datafile = "datafile.lua",
      ["datafile.openers.caller"] = "datafile/openers/caller.lua",
      ["datafile.openers.luarocks"] = "datafile/openers/luarocks.lua",
      ["datafile.util"] = "datafile/util.lua"
   },
   platforms = {
      unix = {
         modules = {
            ["datafile.openers.unix"] = "datafile/openers/unix.lua",
            ["datafile.openers.xdg"] = "datafile/openers/xdg.lua"
         }
      },
      windows = {
         modules = {
            ["datafile.openers.windows"] = "datafile/openers/windows.lua"
         }
      }
   }
}
