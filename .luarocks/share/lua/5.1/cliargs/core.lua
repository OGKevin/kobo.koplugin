-- luacheck: ignore 212

local _
local disect = require('cliargs.utils.disect')
local lookup = require('cliargs.utils.lookup')
local filter = require('cliargs.utils.filter')
local shallow_copy = require('cliargs.utils.shallow_copy')
local create_printer = require('cliargs.printer')
local config_loader = require('cliargs.config_loader')
local parser = require('cliargs.parser')
local K = require 'cliargs.constants'

local function is_callable(fn)
  return type(fn) == "function" or (getmetatable(fn) or {}).__call
end

local function cast_to_boolean(v)
  if v == nil then
    return v
  else
    return v and true or false
  end
end

-- -------- --
-- CLI Main --
-- -------- --
local function create_core()
  --- @module
  ---
  --- The primary export you receive when you require the library. For example:
  ---
  ---     local cli = require 'cliargs'
  local cli = {}
  local colsz = { 0, 0 } -- column width, help text. Set to 0 for auto detect
  local options = {}

  cli.name = ""
  cli.description = ""

  cli.printer = create_printer(function()
    return {
      name = cli.name,
      description = cli.description,
      options = options,
      colsz = colsz
    }
  end)

  -- Used internally to add an option
  local function define_option(k, ek, v, label, desc, default, callback)
    local flag = (v == nil) -- no value, so it's a flag
    local negatable = flag and (ek and ek:find('^%[no%-]') ~= nil)

    if negatable then
      ek = ek:sub(6)
    end

    -- guard against duplicates
    if lookup(k, ek, options) then
      error("Duplicate option: " .. (k or ek) .. ", please rename one of them.")
    end

    if negatable and lookup(nil, "no-"..ek, options) then
      error("Duplicate option: " .. ("no-"..ek) .. ", please rename one of them.")
    end

    -- below description of full entry record, nils included for reference
    local entry = {
      type = K.TYPE_OPTION,
      key = k,
      expanded_key = ek,
      desc = desc,
      default = default,
      label = label,
      flag = flag,
      negatable = negatable,
      callback = callback
    }

    table.insert(options, entry)
  end

  local function define_command_option(key)
    --- @module
    ---
    --- This is a special instance of the [cli]() module that you receive when
    --- you define a new command using [cli#command]().
    local cmd = create_core()

    cmd.__key__ = key
    cmd.type = K.TYPE_COMMAND

    --- Specify a file that the command should run. The rest of the arguments
    --- are forward to that file to process, which is free to use or not use
    --- lua_cliargs in turn.
    ---
    --- @param {string} file_path
    ---        Absolute file-path to a lua script to execute.
    function cmd:file(file_path)
      cmd.__file__ = file_path
      return cmd
    end

    --- Define a command handler. This callback will be invoked if the command
    --- argument was supplied by the user at runtime. What you return from this
    --- callback will be returned to the parent CLI library's parse routine and
    --- it will return that in turn!
    ---
    --- @param {function} callback
    function cmd:action(callback)
      cmd.__action__ = callback
      return cmd
    end

    return cmd
  end

  -- ------------------------------------------------------------------------ --
  -- PUBLIC API
  -- ------------------------------------------------------------------------ --

  --- CONFIG

  --- Assigns the name of the program which will be used for logging.
  function cli:set_name(in_name)
    cli.name = in_name

    return self
  end

  --- Write down a brief, 1-liner description of what the program does.
  function cli:set_description(in_description)
    cli.description = in_description

    return self
  end

  --- Sets the amount of space allocated to the argument keys and descriptions
  --- in the help listing.
  ---
  --- The sizes are used for wrapping long argument keys and descriptions.
  ---
  --- @param {number} [key_cols=0]
  ---        The number of columns assigned to the argument keys, set to 0 to
  ---        auto detect.
  ---
  --- @param {number} [desc_cols=0]
  ---        The number of columns assigned to the argument descriptions, set to
  ---        0 to auto set the total width to 72.
  function cli:set_colsz(key_cols, desc_cols)
    colsz = { key_cols or colsz[1], desc_cols or colsz[2] }
  end

  function cli:redefine_default(key, new_default)
    local entry = lookup(key, key, options)

    if not entry then
      return nil
    end

    if entry.flag then
      new_default = cast_to_boolean(new_default)
    end

    entry.default = shallow_copy(new_default)

    return true
  end

  --- Load default values from a table.
  ---
  --- @param {table} config
  ---        Your new set of defaults. The keys could either point to the short
  ---        or expanded option keys, and their values are the new defaults.
  ---
  --- @param {boolean} [strict=false]
  ---        Turn this on to return nil and an error message if a key in the
  ---        config table could not be mapped to any CLI option.
  ---
  --- @return {true}
  ---         When the new defaults were loaded successfully, or strict was not
  ---         set.
  ---
  --- @return {union<nil, string>}
  ---         When strict was set and there was an error.
  function cli:load_defaults(config, strict)
    for k, v in pairs(config) do
      local success = self:redefine_default(k, v)

      if strict and not success then
        return nil, "Unrecognized option with the key '" .. k .. "'"
      end
    end

    return true
  end

  --- Read config values from a configuration file.
  ---
  --- @param {string} path
  ---        Absolute file path.
  ---
  --- @param {string} [format=nil]
  ---        The config file format, which has to be one of:
  ---        "lua", "json", "ini", or "yaml".
  ---        When this is left blank, we try to auto-detect the format from the
  ---        file extension.
  ---
  --- @param {boolean} [strict=false]
  ---        Forwarded to [#load_defaults](). See that method for the parameter
  ---        description.
  ---
  --- @return {true|union<nil, string>}
  ---         Returns true on successful load. Otherwise, nil and an error
  ---         message are returned instead.
  function cli:read_defaults(path, format)
    if not format then
      format = path:match('%.([^%.]+)$')
    end

    local loader = config_loader.FORMAT_LOADERS[format]

    if not loader then
      return nil, 'Unsupported file format "' .. format .. '"'
    end

    return config_loader[loader](path)
  end

  --- Define a required argument.
  ---
  ---
  --- Required arguments do not take a symbol like `-` or `--`, may not have a
  --- default value, and are parsed in the order they are defined.
  ---
  ---
  --- For example:
  ---
  --- ```lua
  --- cli:argument('INPUT', 'path to the input file')
  --- cli:argument('OUTPUT', 'path to the output file')
  --- ```
  ---
  --- At run-time, the arguments have to be specified using the following
  --- notation:
  ---
  --- ```bash
  --- $ ./script.lua ./main.c ./a.out
  --- ```
  ---
  --- If the user does not pass a value to _every_ argument, the parser will
  --- raise an error.
  ---
  --- @param {string} key
  ---
  ---        The argument identifier that will be displayed to the user and
  ---        be used to reference the run-time value.
  ---
  --- @param {string} desc
  ---
  ---        A description for this argument to display in usage help.
  ---
  --- @param {function} [callback]
  ---        Callback to invoke when this argument is parsed.
  function cli:argument(key, desc, callback)
    assert(type(key) == "string" and type(desc) == "string",
      "Key and description are mandatory arguments (Strings)"
    )

    assert(callback == nil or is_callable(callback),
      "Callback argument must be a function"
    )

    if lookup(key, key, options) then
      error("Duplicate argument: " .. key .. ", please rename one of them.")
    end

    table.insert(options, {
      type = K.TYPE_ARGUMENT,
      key = key,
      desc = desc,
      callback = callback
    })

    return self
  end

  --- Defines a "splat" (or catch-all) argument.
  ---
  --- This is a special kind of argument that may be specified 0 or more times,
  --- the values being appended to a list.
  ---
  --- For example, let's assume our program takes a single output file and works
  --- on multiple source files:
  ---
  --- ```lua
  --- cli:argument('OUTPUT', 'path to the output file')
  --- cli:splat('INPUTS', 'the sources to compile', nil, 10) -- up to 10 source files
  --- ```
  ---
  --- At run-time, it could be invoked as such:
  ---
  --- ```bash
  --- $ ./script.lua ./a.out file1.c file2.c main.c
  --- ```
  ---
  --- If you want to make the output optional, you could do something like this:
  ---
  --- ```lua
  --- cli:option('-o, --output=FILE', 'path to the output file', './a.out')
  --- cli:splat('INPUTS', 'the sources to compile', nil, 10)
  --- ```
  ---
  --- And now we may omit the output file path:
  ---
  --- ```bash
  --- $ ./script.lua file1.c file2.c main.c
  --- ```
  ---
  --- @param {string} key
  ---        The argument's "name" that will be displayed to the user.
  ---
  --- @param {string} desc
  ---        A description of the argument.
  ---
  --- @param {*} [default=nil]
  ---        A default value.
  ---
  --- @param {number} [maxcount=1]
  ---        The maximum number of occurences allowed.
  ---
  --- @param {function} [callback]
  ---        A function to call **everytime** a value for this argument is
  ---        parsed.
  ---
  function cli:splat(key, desc, default, maxcount, callback)
    assert(#filter(options, 'type', K.TYPE_SPLAT) == 0,
      "Only one splat argument may be defined."
    )

    assert(type(key) == "string" and type(desc) == "string",
      "Key and description are mandatory arguments (Strings)"
    )

    assert(type(default) == "string" or default == nil,
      "Default value must either be omitted or be a string"
    )

    maxcount = tonumber(maxcount or 1)

    assert(maxcount > 0 and maxcount < 1000,
      "Maxcount must be a number from 1 to 999"
    )

    assert(is_callable(callback) or callback == nil,
      "Callback argument: expected a function or nil"
    )

    local typed_default = default or {}

    if type(typed_default) ~= 'table' then
      typed_default = { typed_default }
    end

    table.insert(options, {
      type = K.TYPE_SPLAT,
      key = key,
      desc = desc,
      default = typed_default,
      maxcount = maxcount,
      callback = callback
    })

    return self
  end

  --- Defines an optional argument.
  ---
  --- Optional arguments can use 3 different notations, and can accept a value.
  ---
  --- @param {string} key
  ---
  ---        The argument identifier. This can either be `-key`, or
  ---        `-key, --expanded-key`.
  ---        Values can be specified either by appending a space after the
  ---        identifier (e.g. `-key value` or `--expanded-key value`) or by
  ---        separating them with a `=` (e.g. `-key=value` or
  ---        `--expanded-key=value`).
  ---
  --- @param {string} desc
  ---
  ---        A description for the argument to be shown in --help.
  ---
  --- @param {bool} [default=nil]
  ---
  ---         A default value to use in case the option was not specified at
  ---         run-time (the default value is nil if you leave this blank.)
  ---
  --- @param {function} [callback]
  ---
  ---        A callback to invoke when this option is parsed.
  ---
  --- @example
  ---
  --- The following option will be stored in `args["i"]` and `args["input"]`
  --- with a default value of `file.txt`:
  ---
  ---     cli:option("-i, --input=FILE", "path to the input file", "file.txt")
  function cli:option(key, desc, default, callback)
    assert(type(key) == "string" and type(desc) == "string",
      "Key and description are mandatory arguments (Strings)"
    )

    assert(is_callable(callback) or callback == nil,
      "Callback argument: expected a function or nil"
    )

    local k, ek, v = disect(key)

    -- if there's no VALUE indicator anywhere, what they want really is a flag.
    -- e.g:
    --
    --     cli:option('-q, --quiet', '...')
    if v == nil then
      return self:flag(key, desc, default, callback)
    end

    define_option(k, ek, v, key, desc, default, callback)

    return self
  end

  --- Define an optional "flag" argument.
  ---
  --- Flags are a special subset of options that can either be `true` or `false`.
  ---
  --- For example:
  --- ```lua
  --- cli:flag('-q, --quiet', 'Suppress output.', true)
  --- ```
  ---
  --- At run-time:
  ---
  --- ```bash
  --- $ ./script.lua --quiet
  --- $ ./script.lua -q
  --- ```
  ---
  --- Passing a value to a flag raises an error:
  ---
  --- ```bash
  --- $ ./script.lua --quiet=foo
  --- $ echo $? # => 1
  --- ```
  ---
  --- Flags may be _negatable_ by prepending `[no-]` to their key:
  ---
  --- ```lua
  --- cli:flag('-c, --[no-]compress', 'whether to compress or not', true)
  --- ```
  ---
  --- Now the user gets to pass `--no-compress` if they want to skip
  --- compression, or either specify `--compress` explicitly or leave it
  --- unspecified to use compression.
  ---
  --- @param {string} key
  --- @param {string} desc
  --- @param {*} default
  --- @param {function} callback
  function cli:flag(key, desc, default, callback)
    if type(default) == "function" then
      callback = default
      default = nil
    end

    assert(type(key) == "string" and type(desc) == "string",
      "Key and description are mandatory arguments (Strings)"
    )

    local k, ek, v = disect(key)

    if v ~= nil then
      error("A flag type option cannot have a value set: " .. key)
    end

    define_option(k, ek, nil, key, desc, cast_to_boolean(default), callback)

    return self
  end

  --- Define a command argument.
  ---
  --- @param {string} name
  ---        The name of the command and the argument that the user has to
  ---        supply to invoke it.
  ---
  --- @param {string} [desc]
  ---        An optional string to show in the help listing which should
  ---        describe what the command does. It will be displayed if --help
  ---        was run on the main program.
  ---
  ---
  --- @return {cmd}
  ---         Another instance of the CLI library which is scoped to that
  ---         command.
  function cli:command(name, desc)
    local cmd = define_command_option(name)

    cmd:set_name(cli.name .. ' ' .. name)
    cmd:set_description(desc)

    table.insert(options, cmd)

    return cmd
  end

  --- Parse the process arguments table.
  ---
  --- @param {table<string>} [arguments=_G.arg]
  ---        The list of arguments to parse. Defaults to the global `arg` table
  ---        which contains the arguments the process was started with.
  ---
  --- @return {table}
  ---         A table containing all the arguments, options, flags,
  ---         and splat arguments that were specified or had a default
  ---         (where applicable).
  ---
  --- @return {array<nil, string>}
  ---         If a parsing error has occured, note that the --help option is
  ---         also considered an error.
  function cli:parse(arguments)
    return parser(arguments, options, cli.printer)
  end

  --- Prints the USAGE message.
  ---
  --- @return {string}
  ---         The USAGE message.
  function cli:print_usage()
    cli.printer.print(cli:get_usage_message())
  end

  function cli:get_usage_message()
    return cli.printer.generate_usage()
  end

  --- Prints the HELP information.
  ---
  --- @return {string}
  ---         The HELP message.
  function cli:print_help()
    cli.printer.print(cli.printer.generate_help_and_usage())
  end

  return cli
end

return create_core