-- Luacheck configuration for kobo.koplugin
globals = { "os", "io", "table", "string", "math", "debug" }
ignore = { "212" }  -- Ignore unused argument warnings (common in callbacks)
max_line_length = false
