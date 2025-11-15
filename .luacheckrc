-- Luacheck configuration for kobo.koplugin
globals = { "os", "io", "table", "string", "math", "debug", "G_reader_settings" }
ignore = { "212" } -- Ignore unused argument warnings (common in callbacks)
max_line_length = false

-- Busted testing framework configuration for spec files
files["spec/"] = {
    std = "+busted",
    globals = { "assert", "spy", "stub", "mock", "helper" }
}

-- Ignore the .devenv directory and its contents
exclude_files = { ".devenv/**" }
