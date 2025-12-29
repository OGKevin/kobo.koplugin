local wordwrap = require('cliargs.utils.wordwrap')
local filter = require('cliargs.utils.filter')
local K = require('cliargs.constants')
local MAX_COLS = 72
local _

local function create_printer(get_parser_state)
  local printer = {}

  function printer.print(msg)
    return _G.print(msg)
  end

  local function get_max_label_length()
    local maxsz = 0
    local state = get_parser_state()
    local optargument = filter(state.options, 'type', K.TYPE_SPLAT)[1]
    local commands = filter(state.options, 'type', K.TYPE_COMMAND)

    for _, entry in ipairs(commands) do
      if #entry.__key__ > maxsz then
        maxsz = #entry.__key__
      end
    end

    for _,table_name in ipairs({"options"}) do
      for _, entry in ipairs(state[table_name]) do
        local key = entry.label or entry.key or entry.__key__

        if #key > maxsz then
          maxsz = #key
        end
      end
    end

    if optargument and #optargument.key > maxsz then
      maxsz = #optargument.key
    end

    return maxsz
  end

  -- Generate the USAGE heading message.
  function printer.generate_usage()
    local state = get_parser_state()
    local msg = "Usage:"

    local required = filter(state.options, 'type', K.TYPE_ARGUMENT)
    local optional = filter(state.options, 'type', K.TYPE_OPTION)
    local optargument = filter(state.options, 'type', K.TYPE_SPLAT)[1]

    if #state.name > 0 then
      msg = msg .. ' ' .. tostring(state.name)
    end

    if #optional > 0 then
      msg = msg .. " [OPTIONS]"
    end

    if #required > 0 or optargument then
      msg = msg .. " [--]"
    end

    if #required > 0 then
      for _,entry in ipairs(required) do
        msg = msg .. " " .. entry.key
      end
    end

    if optargument then
      if optargument.maxcount == 1 then
        msg = msg .. " [" .. optargument.key .. "]"
      elseif optargument.maxcount == 2 then
        msg = msg .. " [" .. optargument.key .. "-1 [" .. optargument.key .. "-2]]"
      elseif optargument.maxcount > 2 then
        msg = msg .. " [" .. optargument.key .. "-1 [" .. optargument.key .. "-2 [...]]]"
      end
    end

    return msg
  end

  function printer.generate_help()
    local msg = ''
    local state = get_parser_state()
    local col1 = state.colsz[1]
    local col2 = state.colsz[2]
    local required = filter(state.options, 'type', K.TYPE_ARGUMENT)
    local optional = filter(state.options, 'type', K.TYPE_OPTION)
    local commands = filter(state.options, 'type', K.TYPE_COMMAND)
    local optargument = filter(state.options, 'type', K.TYPE_SPLAT)[1]

    local function append(label, desc)
      label = "  " .. label .. string.rep(" ", col1 - (#label + 2))
      desc = table.concat(wordwrap(desc, col2), "\n") -- word-wrap
      desc = desc:gsub("\n", "\n" .. string.rep(" ", col1)) -- add padding

      msg = msg .. label .. desc .. "\n"
    end

    if col1 == 0 then
      col1 = get_max_label_length(state)
    end

    -- add margins
    col1 = col1 + 3

    if col2 == 0 then
      col2 = MAX_COLS - col1
    end

    if col2 < 10 then
      col2 = 10
    end

    if #commands > 0 then
      msg = msg .. "\nCOMMANDS: \n"

      for _, entry in ipairs(commands) do
        append(entry.__key__, entry.description or '')
      end
    end

    if required[1] or optargument then
      msg = msg .. "\nARGUMENTS: \n"

      for _,entry in ipairs(required) do
        append(entry.key, entry.desc .. " (required)")
      end
    end

    if optargument then
      local optarg_desc = ' ' .. optargument.desc
      local default_value = optargument.maxcount > 1 and
        optargument.default[1] or
        optargument.default

      if #optargument.default > 0 then
        optarg_desc = optarg_desc .. " (optional, default: " .. tostring(default_value[1]) .. ")"
      else
        optarg_desc = optarg_desc .. " (optional)"
      end

      append(optargument.key, optarg_desc)
    end

    if #optional > 0 then
      msg = msg .. "\nOPTIONS: \n"

      for _,entry in ipairs(optional) do
        local desc = entry.desc
        if not entry.flag and entry.default and #tostring(entry.default) > 0 then
          local readable_default = type(entry.default) == "table" and "[]" or tostring(entry.default)
          desc = desc .. " (default: " .. readable_default .. ")"
        elseif entry.flag and entry.negatable then
          local readable_default = entry.default and 'on' or 'off'
          desc = desc .. " (default: " .. readable_default .. ")"
        end
        append(entry.label, desc)
      end
    end

    return msg
  end

  function printer.dump_internal_state(values)
    local state = get_parser_state()
    local required = filter(state.options, 'type', K.TYPE_ARGUMENT)
    local optional = filter(state.options, 'type', K.TYPE_OPTION)
    local optargument = filter(state.options, 'type', K.TYPE_SPLAT)[1]
    local maxlabel = get_max_label_length()
    local msg = ''

    local function print(fragment)
      msg = msg .. fragment .. '\n'
    end

    print("\n======= Provided command line =============")
    print("\nNumber of arguments: ", #arg)

    for i,v in ipairs(arg) do -- use gloabl 'arg' not the modified local 'args'
      print(string.format("%3i = '%s'", i, v))
    end

    print("\n======= Parsed command line ===============")
    if #required > 0 then print("\nArguments:") end
    for _, entry in ipairs(required) do
      print(
        "  " ..
        entry.key .. string.rep(" ", maxlabel + 2 - #entry.key) ..
        " => '" ..
        tostring(values[entry]) ..
        "'"
      )
    end

    if optargument then
      print(
        "\nOptional arguments:" ..
        optargument.key ..
        "; allowed are " ..
        tostring(optargument.maxcount) ..
        " arguments"
      )

      if optargument.maxcount == 1 then
          print(
            "  " .. optargument.key ..
            string.rep(" ", maxlabel + 2 - #optargument.key) ..
            " => '" ..
            optargument.key ..
            "'"
          )
      else
        for i = 1, optargument.maxcount do
          if values[optargument] and values[optargument][i] then
            print(
              "  " .. tostring(i) ..
              string.rep(" ", maxlabel + 2 - #tostring(i)) ..
              " => '" ..
              tostring(values[optargument][i]) ..
              "'"
            )
          end
        end
      end
    end

    if #optional > 0 then print("\nOptional parameters:") end
    local doubles = {}
    for _, entry in pairs(optional) do
      if not doubles[entry] then
        local value = values[entry]

        if type(value) == "string" then
          value = "'"..value.."'"
        else
          value = tostring(value) .." (" .. type(value) .. ")"
        end

        print("  " .. entry.label .. string.rep(" ", maxlabel + 2 - #entry.label) .. " => " .. value)

        doubles[entry] = entry
      end
    end

    print("\n===========================================\n\n")

    return msg
  end

  function printer.generate_help_and_usage()
    local msg = ''

    msg = msg .. printer.generate_usage() .. '\n'
    msg = msg .. printer.generate_help()

    return msg
  end

  return printer
end

return create_printer