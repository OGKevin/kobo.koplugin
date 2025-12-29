datafile
========

[![Build Status](https://travis-ci.org/hishamhm/datafile.svg?branch=master)](https://travis-ci.org/hishamhm/datafile)
[![Coverage Status](https://coveralls.io/repos/github/hishamhm/datafile/badge.svg?branch=master)](https://coveralls.io/github/hishamhm/datafile?branch=master)

A Lua library for handling paths when loading data files 

Example usage:

```lua
local datafile = require("datafile")

local my_template = datafile.open("myapp/my_template.txt", "r")
```

This will try to find and open `myapp/my_template.txt` in a series
of locations, based on the "opener" plugins found at the `datafile.openers`
sequence, which contain opener functions loaded from the `datafile.openers.*`
modules (you may modify the `datafile.openers` sequence in an analog fashion
to the `package.loaders`/`package.searchers` sequence from Lua).

## Openers

A few default openers are included:

* `datafile.openers.luarocks`: which tries to determine the LuaRocks context
of the running module (only loaded if LuaRocks is detected).
* `datafile.openers.caller`: tries to find the file based on the path of
the caller script.
* `datafile.openers.xdg`: follows the [freedesktop.org XDG Base Directory Specification](-- http://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html)
* `datafile.openers.unix`: tries traditional Unix paths for data and config files
(/etc and dotfiles at the home dir) -- this is an example of a platform-specific opener.
* `datafile.openers.windows`: tries traditional Windows paths for user and config files. For config files, it tries user configuration first, then system wide.
For data/user files, it tries the user directory first, then the public directory.

Note: when installing trough LuaRocks, only files for the relevant platform will be installed.

## API

##### datafile.open(file, \[mode\], \[context\])

Opens a file, trying the various loaders.

* `file` is a relative filename: it is usually prepended by various prefixes
as the openers attempt to construct absolute pathnames to find the file.
* `mode` is the opening mode, as in [file:open](http://www.lua.org/manual/5.1/manual.html#pdf-io.open).
If not given, "r" is the default.
* `context` is an optional hint to be used by the openers. Currently, the
following contexts are supported:
  * nil - the default context
  * "config" - this is a configuration file 
  * "cache" - a runtime cache file

Some openers may operate only on specific contexts, or ignore the context altogether.

If successful, returns two arguments: the open file handle and its pathname.
If failed, returns nil and an error message.

##### datafile.path(file, \[mode\], \[context\])

A shorthand function that looks for a file and returns its pathname.
The return pathname may be relative.

The input arguments are the same as for `datafile.open`.

If successful, returns one argument: the pathname, which may be relative.
If failed, returns nil and an error message.

## To-do

* More openers (any Mac-specific paths?)
* Testing

Feedback, pull requests, criticism, contributions, etc. are welcome!

