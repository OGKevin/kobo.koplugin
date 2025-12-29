package = 'lua-term'
version = '0.8-1'

source = {
  url = 'https://github.com/hoelzro/lua-term/archive/0.08.tar.gz',
  dir = 'lua-term-0.08',
}

description = {
  summary  = 'Terminal functions for Lua',
  homepage = 'https://github.com/hoelzro/lua-term',
  license  = "MIT/X11",
}

build = {
  modules = {
    ['term']        = 'term/init.lua',
    ['term.colors'] = 'term/colors.lua',
    ['term.cursor'] = 'term/cursor.lua',
    ['term.core']   = 'core.c',
  },
  type = 'builtin',
}
