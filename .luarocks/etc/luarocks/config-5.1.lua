-- LuaRocks configuration

rocks_trees = {
   { name = "user", root = home .. "/.luarocks" };
   { name = "system", root = "/home/runner/work/kobo.koplugin/kobo.koplugin/.luarocks" };
}
variables = {
   LUA_DIR = "/home/runner/work/kobo.koplugin/kobo.koplugin/.lua";
   LUA_BINDIR = "/home/runner/work/kobo.koplugin/kobo.koplugin/.lua/bin";
   LUA_VERSION = "5.1";
   LUA = "/home/runner/work/kobo.koplugin/kobo.koplugin/.lua/bin/luajit";
}
