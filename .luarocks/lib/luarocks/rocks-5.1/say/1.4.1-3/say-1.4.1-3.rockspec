package = "say"
local rock_version = "1.4.1"
local rock_release = "3"
local namespace = "lunarmodules"
local repository = package

version = ("%s-%s"):format(rock_version, rock_release)

source = {
  url = ("git+https://github.com/%s/%s.git"):format(namespace, repository),
  branch = rock_version == "scm" and "master" or nil,
  tag = rock_version ~= "scm" and "v"..rock_version or nil,
}

description = {
  summary = "Lua string hashing/indexing library",
  detailed = [[
    Useful for internationalization.
  ]],
  license = "MIT",
  homepage = ("https://%s.github.io/%s"):format(namespace, repository),
  maintainer = "Caleb Maclennan <caleb@alerque.com>",
}

dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    say = "src/say/init.lua"
  }
}
