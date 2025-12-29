package = "argparse"
version = "0.7.1-1"
source = {
   url = "https://github.com/luarocks/argparse/archive/0.7.1.zip",
   md5 = "3393e3336b47dade24e0f273c6ae4ddb",
   dir = "argparse-0.7.1"
}
description = {
   summary = "A feature-rich command-line argument parser",
   detailed = "Argparse supports positional arguments, options, flags, optional arguments, subcommands and more. Argparse automatically generates usage, help, and error messages, and can generate shell completion scripts.",
   homepage = "https://github.com/luarocks/argparse",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1, < 5.5"
}
build = {
   type = "builtin",
   modules = {
      argparse = "src/argparse.lua"
   }
}
