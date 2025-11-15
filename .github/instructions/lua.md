---
applyTo: "**/*.lua"
---

# Lua Coding Guidelines

## Formatting Standards

All Lua code must be formatted using **stylua** with these exact settings:

```bash
stylua \
  --sort-requires \
  --indent-type Spaces \
  --indent-width 4 \
  <file>
```

**Key principles:**

- **Indentation:** 4 spaces (never tabs)
- **Requires:** Automatically sorted alphabetically
- **Line length:** Follow stylua defaults

## Code Structure & Naming

### 1. Import Statements

- Group all imports at the top of the file
- Use `require()` statements exclusively
- Sort requires alphabetically
- Separate import group from code with a blank line

```lua
local LibraryManager = require("lib.library_manager")
local StatusConverter = require("lib.status_converter")
local Utils = require("lib.utils")

local MyModule = {}
```

### 2. Variable Declarations

- Group related variables together
- Use descriptive names (avoid single-letter variables except in loops)
- Separate logical groups with blank lines

```lua
local config = {}
local currentBook = nil

local MAX_RETRIES = 3
local SYNC_INTERVAL = 5000
```

### 3. Function Naming

- Use camelCase for functions and variables
- Use UPPER_SNAKE_CASE for constants
- Private functions should be prefixed with underscore: `_privateFunction()`
- Public functions are exposed via module table

```lua
local function _internalHelper()
    -- implementation
end

function MyModule.publicFunction()
    return _internalHelper()
end
```

### 4. Control Flow

- **No else statements allowed** - use early returns instead
- Add blank lines around control structures for readability
- Minimize nesting depth

```lua
-- GOOD: Early return pattern
if not isValid then
    return nil
end

-- Process valid case
return result

-- BAD: Avoid this
if isValid then
    return result
else
    return nil
end
```

### 5. Documentation

- Use DocBlocks (comment blocks) for all functions and modules
- Provide clear description, parameters, and return types
- Inline comments should be minimal; extract complex logic into named functions instead

```lua
--- Synchronize reading state with remote service.
-- @param bookId string The unique book identifier
-- @param position number Current reading position
-- @return boolean True if sync was successful
local function syncReadingState(bookId, position)
    -- implementation
end
```

### 6. Return Statements

- Surround return statements with blank lines to make them stand out
- Use early returns to reduce nesting

```lua
local function processBook(book)
    if not book then
        return nil
    end

    local result = transformBook(book)

    return result
end
```

### 7. Line Breaks & Readability

- Add line breaks before and after control structures
- Use blank lines to separate logical sections
- Maximum line length is respected by stylua

```lua
function Module.process()
    local data = loadData()

    if not data then
        return
    end

    for _, item in ipairs(data) do
        processItem(item)
    end

    return true
end
```

## Module Pattern

All Lua modules should follow this pattern:

```lua
local RequiredModule = require("path.to.module")

local MyModule = {}

-- Private constants
local DEFAULT_VALUE = 42

-- Private functions
local function _privateHelper(param)
    return param * 2
end

-- Public functions
function MyModule.publicMethod(input)
    if not input then
        return nil
    end

    local processed = _privateHelper(input)

    return processed
end

function MyModule.new(options)
    local instance = {
        config = options or {},
    }

    setmetatable(instance, { __index = MyModule })

    return instance
end

return MyModule
```

## Error Handling

### Input Validation

Always validate function inputs:

```lua
function MyModule.process(data)
    if not data then
        return nil, "data is required"
    end

    if type(data) ~= "table" then
        return nil, "data must be a table"
    end

    -- Process data
    return result
end
```

### Early Returns

Use early returns for error conditions:

```lua
function MyModule.complexOperation(input)
    if not input then
        return nil
    end

    if not input.isValid then
        return nil
    end

    if not input.hasData then
        return nil
    end

    -- Main logic here
    return processedResult
end
```

## Common Patterns

### Table Iteration

```lua
-- Array iteration
for i, item in ipairs(items) do
    processItem(item)
end

-- Dictionary iteration
for key, value in pairs(dict) do
    processKeyValue(key, value)
end
```

### Nil Checks

```lua
-- Check for nil
if not value then
    return nil
end

-- Check for specific value
if value == nil then
    return nil
end

-- Provide default value
local result = value or defaultValue
```

### String Operations

```lua
-- Concatenation
local message = "Hello, " .. name

-- Format strings
local formatted = string.format("User %s has %d items", username, count)

-- Pattern matching
local match = string.match(text, "pattern")
```

## Testing Guidelines

### Test File Structure

```lua
local Module = require("lib.module")

describe("Module", function()
    local instance

    before_each(function()
        instance = Module.new()
    end)

    after_each(function()
        -- Cleanup if needed
    end)

    describe("publicMethod", function()
        it("should handle valid input", function()
            local result = instance:publicMethod("valid")

            assert.are.equal(result, "expected")
        end)

        it("should return nil for invalid input", function()
            local result = instance:publicMethod(nil)

            assert.is_nil(result)
        end)
    end)
end)
```

### Mocking

Mock external dependencies, not the code under test:

```lua
local function createMockService()
    return {
        getData = function()
            return { id = "1", value = "test" }
        end,
        saveData = function(data)
            return true
        end,
    }
end

describe("Module with mocks", function()
    it("should use mocked service", function()
        local mockService = createMockService()
        local module = Module.new({ service = mockService })

        local result = module:process()

        assert.is_not_nil(result)
    end)
end)
```

## Anti-Patterns to Avoid

1. **Global Variables** - Always use local variables
2. **Else Statements** - Use early returns instead
3. **Deep Nesting** - Extract functions, use early returns
4. **Magic Numbers** - Use named constants
5. **Long Functions** - Break into smaller, focused functions
6. **Unclear Names** - Use descriptive variable and function names

## Luacheck Configuration

This project uses luacheck for static analysis. Configuration in `.luacheckrc`:

```lua
globals = { "os", "io", "table", "string", "math", "debug" }
ignore = { "212" }  -- Ignore unused argument warnings (common in callbacks)
max_line_length = false
```

## Performance Tips

1. **Local Variables** - Access is faster than global
2. **Cache Lookups** - Store repeated table lookups in locals
3. **Avoid Table Creation** - Reuse tables when possible in hot paths
4. **Profile** - Measure before optimizing

```lua
-- Good: Cache table lookup
local math_floor = math.floor
for i = 1, 1000 do
    local result = math_floor(i / 2)
end

-- Bad: Repeated table lookup
for i = 1, 1000 do
    local result = math.floor(i / 2)
end
```
