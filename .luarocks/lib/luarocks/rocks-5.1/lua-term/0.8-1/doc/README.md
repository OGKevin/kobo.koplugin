Overview
--------

lua-term is a Lua module for manipulating a terminal.

Installation
------------

lua-term is available on Luarocks.


## OpenBSD

lua-term is available as an OpenBSD package. Use the proper Lua flavour to
get the package for your Lua version:

```
# For Lua 5.1
$ doas pkg_add -r lua-term
# For Lua 5.2
$ doas pkg_add -r lua52-term
# For Lua 5.3
$ doas pkg_add -r lua53-term
```

Or install from ports:

```
$ cd /usr/ports/devel/lua-term
$ env FLAVOR=lua51 doas make install
```

## openSUSE
lua-term is available in the `devel:languages:lua` devel project on [OBS](https://build.opensuse.org/package/show/devel:languages:lua/lua-luaterm).

Add the repository and install lua-term via:
```
zypper addrepo http://download.opensuse.org/repositories/devel:/languages:/lua/openSUSE_Tumbleweed/devel:languages:lua.repo
zypper refresh
zypper in lua-luaterm
```

Adjust the repository URL to your version of openSUSE by substituting `openSUSE_Tumbleweed` with your actual version eg `opensSUSE_42.2`.

Usage
-----

```lua
    local term   = require 'term'
    local colors = term.colors -- or require 'term.colors'

    print(term.isatty(io.stdout)) -- true if standard output goes to the terminal

    print(colors.red 'hello')
    print(colors.red .. 'hello' .. colors.reset)
    print(colors.red, 'hello', colors.reset)

    -- The following functions take an optional IO handle (like io.stdout);
    -- io.stdout is the default if you don't specify one
    term.clear()    -- clears the screen
    term.cleareol() -- clears from the cursor to the end of the line
    --term.cursor.goto(1, 1) -- It will fail in Lua >= 5.2 because goto is a reserved word.
    term.cursor['goto'](1, 1) -- This will work on Lua >= 5.2, please use jump instead
    term.cursor.jump(1, 1) -- jump is just an alias for goto
    term.cursor.jump(io.stdout, 1, 1)
    term.cursor.goup(1)
    term.cursor.godown(1)
    term.cursor.goright(1)
    term.cursor.goleft(1)
    term.cursor.save()    -- save position
    term.cursor.restore() -- restore position
```

`term` Functions
--------------

Some functions in lua-term take an optional file handle argument; if this is
not provided, `io.stdout` is used.

### `term.clear([opt_file])`

Clear the terminal's contents.

### `term.cleareol([opt_file])`

Clear from the current cursor position to the end of the current line.

### `term.isatty(file)`

Returns `true` if `file` is a TTY; `false` otherwise.

*NOTE*: This function has been deprecated in favor of luaposix's implementation.
If you would like this functionality in the future, please use luaposix.

`term.colors` Values
------------------

The following values are available in `term.colors`:

### Terminal Attributes

  * reset
  * clear (a synonym for reset)
  * default (a synonym for reset)
  * bright
  * dim
  * underscore
  * blink
  * reverse
  * hidden

### Foreground Colors

  * black
  * red
  * green
  * yellow
  * blue
  * magenta
  * cyan
  * white

### Background Colors

  * onblack
  * onred
  * ongreen
  * onyellow
  * onblue
  * onmagenta
  * oncyan
  * onwhite

Every value in `term.colors` may be used in several ways:

### As a Function

```lua
print(colors.red 'hello')
```

### As a String

```lua
print(colors.red .. 'hello' .. colors.reset)
print(colors.red, 'hello', colors.reset)
```

`term.cursor` Functions
---------------------

### `term.cursor.goto([opt_file], x, y)`

Place the cursor at (`x`, `y`).

### `term.cursor.jump([opt_file], x, y)`

An alias for `term.cursor.goto`.

### `term.cursor.goup([opt_file], nlines)`

Moves the cursor up `nlines` lines.

### `term.cursor.godown([opt_file], nlines)`

Moves the cursor down `nlines` lines.

### `term.cursor.goright([opt_file], ncols)`

Moves the cursor right `ncols` columns.

### `term.cursor.goleft([opt_file], ncols)`

Moves the cursor left `ncols` columns.

### `term.cursor.save([opt_file])`

Saves the cursor position.

### `term.cursor.restore([opt_file])`

Restores the cursor position.

Alternatives
------------

If you are looking to simply provide coloration to a terminal application and would
like to use a more "tag-like" API (ex. `colors '%{red}hello%{reset}'`), there is a Lua rock
named ansicolors: https://github.com/kikito/ansicolors.lua
