# Copilot Instructions for kobo.koplugin

## Project Overview

**kobo.koplugin** is a KOReader plugin that extends Kobo device functionality with virtual library management and reading state synchronization.

- **Language:** Lua (primary), Markdown (docs), Shell (build scripts)
- **Testing Framework:** Busted
- **Current Version:** 0.1.0
- **Plugin ID:** kobo.koplugin

## Project Structure

```
/
├── _meta.lua                              # Plugin metadata (version, description, author)
├── main.lua                               # Plugin entry point
├── *.lua                                  # Core plugin modules (extensions, managers, handlers)
├── lib/                                   # Shared libraries and utilities
│   ├── kobo_state_reader.lua
│   ├── kobo_state_writer.lua
│   ├── status_converter.lua
│   └── sync_decision_maker.lua
├── patches/                               # KoReader patches
│   ├── 2-filemanager-menu-separator.lua
│   ├── 2-kobo-virtual-library-startup.lua
│   └── 2-readerrolling-position-fix.lua
├── spec/                                  # Busted test files
│   ├── helper.lua
│   └── *_spec.lua
├── docs/                                  # Markdown documentation
├── book/                                  # mdBook generated HTML (output directory)
└── package.sh                             # Build script for creating distributable ZIP
```

## Language-Specific Guidelines

This project uses multiple languages with specific coding standards:

- **Lua:** See `.github/instructions/lua.md` for detailed Lua coding guidelines
- **Shell Scripts:** See `.github/instructions/shell.md` for shell script best practices
- **Markdown:** See `.github/instructions/markdown.md` for documentation formatting

## General Coding Principles

### 1. Code Quality

- Write clear, maintainable code
- Prefer simplicity over cleverness
- Document complex logic with comments
- Keep functions focused and single-purpose
- Use descriptive variable and function names

### 2. Testing Requirements

- All new features must include tests
- Tests must be placed in `spec/` directory with `_spec.lua` suffix
- Use Busted testing framework DSL
- Aim for minimum 70% code coverage
- Mock external dependencies, not code under test

### 3. Error Handling

- Always validate inputs to functions
- Return early on error conditions
- Provide meaningful error messages
- Handle edge cases explicitly

### 4. Performance Considerations

- Avoid unnecessary file I/O operations
- Cache computed values when appropriate
- Be mindful of memory usage on embedded devices
- Profile code for performance-critical sections

## CI/CD Workflows

This project uses GitHub Actions for continuous integration:

- **Linting:** Runs luacheck, stylua, prettier, and shellcheck
- **Testing:** Runs busted tests with coverage reporting
- **Build:** Creates distributable artifacts (kobo.koplugin.zip, kobo-patches.zip)
- **Documentation:** Builds mdBook documentation and deploys to GitHub Pages
- **Release:** Automated releases using release-please

All workflows use intelligent change detection to run only when relevant files are modified.

## Development Workflow

### Local Development

```bash
# Format Lua code
stylua --sort-requires --indent-type Spaces --indent-width 4 *.lua lib/ spec/

# Lint Lua code
luacheck *.lua lib/ spec/

# Check shell scripts
shellcheck *.sh

# Format markdown
prettier --write "docs/**/*.md" "*.md"

# Run tests
busted spec/
```

### Creating Releases

This project uses conventional commits for automated releases:

- `feat: description` → Minor version bump
- `fix: description` → Patch version bump
- `docs: description` → No version bump
- `chore: description` → No version bump
- `BREAKING CHANGE:` in body → Major version bump

When you push to main with conventional commits, release-please automatically creates a PR with version bump and changelog.

## Common Patterns

### Module Structure

```lua
local Module = {}

-- Private function (underscore prefix)
local function _internalHelper()
    -- implementation
end

-- Public function
function Module.publicFunction()
    return _internalHelper()
end

return Module
```

### Early Return Pattern

```lua
-- GOOD: Use early returns
function process(data)
    if not data then
        return nil
    end
    
    if not data.isValid then
        return nil
    end
    
    return transformData(data)
end

-- BAD: Avoid nested if-else
function process(data)
    if data then
        if data.isValid then
            return transformData(data)
        else
            return nil
        end
    else
        return nil
    end
end
```

### Test Structure

```lua
describe("Module", function()
    local instance
    
    before_each(function()
        instance = Module.new()
    end)
    
    describe("method", function()
        it("should handle valid input", function()
            local result = instance:method("valid")
            assert.are.equal(result, expected)
        end)
        
        it("should handle invalid input", function()
            local result = instance:method(nil)
            assert.is_nil(result)
        end)
    end)
end)
```

## Anti-Patterns to Avoid

1. **No else statements** - Use early returns instead
2. **No deeply nested code** - Extract functions, use early returns
3. **No magic numbers** - Use named constants
4. **No global state** - Pass dependencies explicitly
5. **No mocking code under test** - Only mock external dependencies

## Build and Package

The `package.sh` script creates distributable archives:

- `kobo.koplugin.zip` - Full plugin package
- Includes: `_meta.lua`, `main.lua`, all `*.lua` files, `lib/`, `patches/`, `README.md`
- Excludes: `spec/`, `docs/`, `book/`, `devenv.*`, `.git*`, test files

## Plugin Architecture

This is a KOReader plugin that:

1. Extends KOReader with virtual library functionality
2. Syncs reading state between Kobo Nickel and KOReader
3. Provides patches for KOReader core functionality
4. Manages book metadata from Kobo's database

When making changes:

- Understand the KOReader plugin architecture
- Be aware of Kobo device constraints (memory, storage)
- Test on actual hardware when possible
- Consider backward compatibility with existing user installations

## Documentation

Documentation is written in Markdown and built with mdBook:

- Source files in `docs/` directory
- Configuration in `book.toml`
- Table of contents in `docs/SUMMARY.md`
- Built output in `book/` directory
- Automatically deployed to GitHub Pages on main branch

When updating documentation:

- Keep prose wrapped at 100 characters (prettier enforces this)
- Use clear section headings
- Include code examples where helpful
- Update SUMMARY.md if adding new pages
