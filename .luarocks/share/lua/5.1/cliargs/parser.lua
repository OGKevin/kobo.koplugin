local K = require 'cliargs.constants'

-------------------------------------------------------------------------------
-- UTILS
-------------------------------------------------------------------------------
local shallow_copy = require 'cliargs.utils.shallow_copy'
local filter = require 'cliargs.utils.filter'
local disect_argument = require 'cliargs.utils.disect_argument'
local lookup = require 'cliargs.utils.lookup'

local function clone_table_shift(t)
  local clone = shallow_copy(t)
  table.remove(clone, 1)
  return clone
end

local function clone_table_remove(t, index)
  local clone = shallow_copy(t)
  table.remove(clone, index)
  return clone
end

-------------------------------------------------------------------------------
-- PARSE ROUTINES
-------------------------------------------------------------------------------
local p = {}
function p.invoke_command(args, options, done)
  local commands = filter(options, 'type', K.TYPE_COMMAND)

  for index, opt in ipairs(args) do
    local command = filter(commands, '__key__', opt)[1]

    if command then
      local command_args = clone_table_remove(args, index)

      if command.__action__ then
        local parsed_command_args, err = command:parse(command_args)

        if err then
          return nil, err
        end

        return command.__action__(parsed_command_args)
      elseif command.__file__ then
        local filename = command.__file__

        if type(filename) == 'function' then
          filename = filename()
        end

        local run_command_file = function()
          _G.arg = command_args

          local res, err = assert(loadfile(filename))()

          _G.arg = args

          return res, err
        end

        return run_command_file()
      end
    end
  end

  return done()
end

function p.print_help(args, printer, done)
  -- has --help or -h ? display the help listing and abort!
  for _, v in pairs(args) do
    if v == "--help" or v == "-h" then
      return nil, printer.generate_help_and_usage()
    end
  end

  return done()
end

function p.track_dump_request(args, done)
  -- starts with --__DUMP__; set dump to true to dump the parsed arguments
  if args[1] == "--__DUMP__" then
    return done(true, clone_table_shift(args))
  else
    return done(false, args)
  end
end

function p.process_arguments(args, options, done)
  local values = {}
  local cursor = 0
  local argument_cursor = 1
  local argument_delimiter_found = false
  local function consume()
    cursor = cursor + 1

    return args[cursor]
  end

  local required = filter(options, 'type', K.TYPE_ARGUMENT)

  while cursor < #args do
    local curr_opt = consume()
    local symbol, key, value, flag_negated = disect_argument(curr_opt)

    -- end-of-options indicator:
    if curr_opt == "--" then
      argument_delimiter_found = true

    -- an option:
    elseif not argument_delimiter_found and symbol then
      local entry = lookup(key, key, options)

      if not key or not entry then
        local option_type = value and "option" or "flag"

        return nil, "unknown/bad " .. option_type .. ": " .. curr_opt
      end

      if flag_negated and not entry.negatable then
        return nil, "flag '" .. curr_opt .. "' may not be negated using --no-"
      end

      -- a flag and a value specified? that's an error
      if entry.flag and value then
        return nil, "flag " .. curr_opt .. " does not take a value"
      elseif entry.flag then
        value = not flag_negated
      -- an option:
      else
        -- the value might be in the next argument, e.g:
        --
        --     --compress lzma
        if not value then
          -- if the option contained a = and there's no value, it means they
          -- want to nullify an option's default value. eg:
          --
          --    --compress=
          if curr_opt:find('=') then
            value = '__CLIARGS_NULL__'
          else
            -- NOTE: this has the potential to be buggy and swallow the next
            -- entry as this entry's value even though that entry may be an
            -- actual argument/option
            --
            -- this would be a user error and there is no determinate way to
            -- figure it out because if there's no leading symbol (- or --)
            -- in that entry it can be an actual argument. :shrug:
            value = consume()

            if not value then
              return nil, "option " .. curr_opt .. " requires a value to be set"
            end
          end
        end
      end

      table.insert(values, { entry = entry, value = value })

      if entry.callback then
        local altkey = entry.key
        local status, err

        if key == entry.key then
          altkey = entry.expanded_key
        else
          key = entry.expanded_key
        end

        status, err = entry.callback(key, value, altkey, curr_opt)

        if status == nil and err then
          return nil, err
        end
      end

    -- a regular argument:
    elseif argument_cursor <= #required then
      local entry = required[argument_cursor]

      table.insert(values, { entry = entry, value = curr_opt })

      if entry.callback then
        local status, err = entry.callback(entry.key, curr_opt)

        if status == nil and err then
          return nil, err
        end
      end

      argument_cursor = argument_cursor + 1

    -- a splat argument:
    else
      local entry = filter(options, 'type', K.TYPE_SPLAT)[1]

      if entry then
        table.insert(values, { entry = entry, value = curr_opt })

        if entry.callback then
          local status, err = entry.callback(entry.key, curr_opt)

          if status == nil and err then
            return nil, err
          end
        end
      end

      argument_cursor = argument_cursor + 1
    end
  end

  return done(values, argument_cursor - 1)
end

function p.validate(options, arg_count, done)
  local required = filter(options, 'type', K.TYPE_ARGUMENT)
  local splatarg = filter(options, 'type', K.TYPE_SPLAT)[1] or { maxcount = 0 }

  local min_arg_count = #required
  local max_arg_count = #required + splatarg.maxcount

  -- missing any required arguments, or too many?
  if arg_count < min_arg_count or arg_count > max_arg_count then
    if splatarg.maxcount > 0 then
      return nil, (
        "bad number of arguments: " ..
        min_arg_count .. "-" .. max_arg_count ..
        " argument(s) must be specified, not " .. arg_count
      )
    else
      return nil, (
        "bad number of arguments: " ..
        min_arg_count .. " argument(s) must be specified, not " .. arg_count
      )
    end
  end

  return done()
end

function p.collect_results(cli_values, options)
  local results = {}
  local function collect_with_default(entry)
    local entry_values = {}
    local _

    for _, item in ipairs(cli_values) do
      if item.entry == entry then
        table.insert(entry_values, item.value)
      end
    end

    if #entry_values == 0 then
      return type(entry.default) == 'table' and entry.default or { entry.default }
    else
      return entry_values
    end
  end

  local function write(entry, value)
    if entry.key then results[entry.key] = value end
    if entry.expanded_key then results[entry.expanded_key] = value end
  end

  for _, entry in pairs(options) do
    local entry_cli_values = collect_with_default(entry)
    local maxcount = entry.maxcount

    if maxcount == nil then
      maxcount = type(entry.default) == 'table' and 999 or 1
    end

    local entry_value = entry_cli_values

    if maxcount == 1 and type(entry_cli_values) == 'table' then
      -- take the last value
      entry_value = entry_cli_values[#entry_cli_values]

      if entry_value == '__CLIARGS_NULL__' then
        entry_value = nil
      end
    end

    write(entry, entry_value)
  end

  return results
end


return function(arguments, options, printer)
  assert(arguments == nil or type(arguments) == "table",
    "expected an argument table to be passed in, " ..
    "got something of type " .. type(arguments)
  )

  local args = arguments or _G.arg or {}

  -- the spiral of DOOM:
  return p.invoke_command(args, options, function()
    return p.track_dump_request(args, function(dump, args_without_dump)
      return p.print_help(args_without_dump, printer, function()
        return p.process_arguments(args_without_dump, options, function(values, arg_count)
          return p.validate(options, arg_count, function()
            if dump then
              return nil, printer.dump_internal_state(values)
            else
              return p.collect_results(values, options)
            end
          end)
        end)
      end)
    end)
  end)
end
