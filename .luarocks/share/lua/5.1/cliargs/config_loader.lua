local trim = require 'cliargs.utils.trim'

local function read_file(filepath)
  local f, err = io.open(filepath, "r")

  if not f then
    return nil, err
  end

  local contents = f:read('*all')

  f:close()

  return contents
end

return {
  FORMAT_LOADERS = {
    ["lua"]   = "from_lua",
    ["json"]  = "from_json",
    ["yaml"]  = "from_yaml",
    ["yml"]   = "from_yaml",
    ["ini"]   = "from_ini",
  },

  --- Load configuration from a Lua file that exports a table.
  from_lua = function(filepath)
    local file, err = loadfile(filepath)

    if not file and err then
      return nil, err
    end

    return file()
  end,

  --- Load configuration from a JSON file.
  ---
  --- Requires the "dkjson"[1] module to be present on the system. Get it with:
  ---
  ---     luarocks install dkjson
  ---
  --- [1] http://dkolf.de/src/dkjson-lua.fsl/home
  from_json = function(filepath)
    local src, config, _, err
    local json = require 'dkjson'

    src, err = read_file(filepath)

    if not src and err then
      return nil, err
    end

    config, _, err = json.decode(src)

    if err then
      return nil, err
    end

    return config
  end,

  --- Load configuration from an INI file.
  ---
  --- Requires the "inifile"[1] module to be present on the system. Get it with:
  ---
  ---     luarocks install inifile
  ---
  --- The INI file must contain a group that lists the default values. For
  --- example:
  ---
  ---     [cli]
  ---     quiet = true
  ---     compress = lzma
  ---
  --- The routine will automatically cast boolean values ("true" and "false")
  --- into Lua booleans. You may opt out of this behavior by passing `false`
  --- to `no_cast`.
  ---
  --- [1] http://docs.bartbes.com/inifile
  from_ini = function(filepath, group, no_cast)
    local inifile = require 'inifile'
    local config, err

    group = group or 'cli'

    assert(type(group) == 'string',
      'You must provide an INI group to read from.'
    )

    config, err = inifile.parse(filepath)

    if not config and err then
      return nil, err
    end

    if not no_cast then
      for k, src_value in pairs(config[group]) do
        local v = trim(src_value)

        if v == 'true' then
          v = true
        elseif v == 'false' then
          v = false
        end

        config[group][k] = v
      end
    end

    return config[group]
  end,

  --- Load configuration from a YAML file.
  ---
  --- Requires the "yaml"[1] module to be present on the system. Get it with:
  ---
  ---     luarocks install yaml
  ---
  --- [1] http://doc.lubyk.org/yaml.html
  from_yaml = function(filepath)
    local src, config, _, err
    local yaml = require 'yaml'

    src, err = read_file(filepath)

    if not src and err then
      return nil, err
    end

    config, err = yaml.load(src)

    if not config and err then
      return nil, err
    end

    return config
  end
}
