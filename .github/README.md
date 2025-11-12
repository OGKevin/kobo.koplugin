# GitHub Actions & Copilot Setup

This directory contains the CI/CD workflows and Copilot instructions for the kobo.koplugin project.

## Directory Structure

```
.github/
├── workflows/           # GitHub Actions workflow definitions
│   ├── lint.yml        # Code linting (luacheck, stylua, prettier, shellcheck)
│   ├── test.yml        # Test execution (busted)
│   ├── build-artifact.yml  # Build distributable artifacts
│   ├── docs.yml        # Documentation build and GitHub Pages deploy
│   └── release.yml     # Automated releases with release-please
├── instructions/       # Language-specific coding guidelines
│   ├── lua.md         # Lua code style and best practices
│   ├── shell.md       # Shell script standards
│   └── markdown.md    # Markdown formatting rules
├── copilot-instructions.md  # Main Copilot instructions
└── README.md          # This file
```

## Workflows Overview

### 1. Lint Workflow (`lint.yml`)

**Triggers:** Push to any branch, Pull requests

**What it does:**
- Detects changes to Lua, Shell, and Markdown files
- Runs luacheck on Lua files
- Runs stylua (format checker) on Lua files
- Runs prettier on Markdown files
- Runs shellcheck on shell scripts
- Only runs checks on changed file types (saves CI time)

**Requirements:**
- All Lua files must pass luacheck
- All Lua files must be formatted with stylua
- All Markdown must be formatted with prettier
- All shell scripts must pass shellcheck

### 2. Test Workflow (`test.yml`)

**Triggers:** Push to any branch, Pull requests

**What it does:**
- Detects changes to Lua and test files
- Runs busted test suite
- Generates code coverage report
- Only runs when relevant files change

**Requirements:**
- All tests must pass
- Aim for 70%+ code coverage

### 3. Build Artifact Workflow (`build-artifact.yml`)

**Triggers:** Push to any branch

**What it does:**
- Detects changes to plugin files
- Runs package.sh to create kobo.koplugin.zip
- Creates kobo-patches.zip (patches only)
- Uploads both as GitHub Actions artifacts
- Artifacts retained for 7 days
- Only runs when source files change

**Artifacts:**
- `kobo.koplugin-{branch}-{commit}.zip` - Full plugin
- `kobo-patches-{branch}-{commit}.zip` - Patches only

### 4. Documentation Workflow (`docs.yml`)

**Triggers:** Push to any branch, Pull requests

**What it does:**
- Detects changes to documentation files
- Builds mdBook documentation
- On main branch: deploys to `docs` branch for GitHub Pages
- Only runs when docs change

**Requirements:**
- Documentation must build without errors
- GitHub Pages must be enabled (source: `docs` branch)

### 5. Release Workflow (`release.yml`)

**Triggers:** Push to main branch

**What it does:**
- Uses release-please to manage releases
- Creates release PR with version bump and changelog
- When release PR is merged, creates GitHub Release
- Uploads kobo.koplugin.zip and kobo-patches.zip as release assets
- Generates SHA256 checksums for all assets

**Conventional Commits:**
- `feat:` - Minor version bump
- `fix:` - Patch version bump
- `BREAKING CHANGE:` - Major version bump
- `docs:`, `chore:`, etc. - No version bump

## Change Detection

All workflows use `tj-actions/changed-files@v47` to detect changes. This ensures:
- Workflows only run when relevant files are modified
- Faster CI execution
- Reduced CI resource usage
- Better PR feedback (only relevant checks run)

### How it works:

1. `detect-changes` job runs first
2. Checks which file patterns changed
3. Sets output variables (`lua_changed`, `shell_changed`, etc.)
4. Subsequent jobs use `if: needs.detect-changes.outputs.X == 'true'`
5. Jobs are skipped if no relevant changes detected

## Configuration Files

### Root Directory

- `.luacheckrc` - Luacheck configuration
- `.prettierrc` - Prettier configuration
- `.prettierignore` - Files to exclude from prettier
- `.shellcheckrc` - Shellcheck configuration
- `release-please-config.json` - Release-please settings
- `.release-please-manifest.json` - Current version tracking

### Existing Files (Not Modified)

- `.busted` - Busted test configuration (already exists)

## Copilot Instructions

GitHub Copilot automatically reads instructions from this directory to provide context-aware assistance.

### Main Instructions (`copilot-instructions.md`)

- Project overview and architecture
- General coding principles
- Testing requirements
- CI/CD workflow information
- Common patterns and anti-patterns

### Language-Specific Instructions

**Lua (`instructions/lua.md`):**
- stylua configuration and formatting rules
- Import statement organization
- Variable and function naming conventions
- Control flow best practices (early returns, no else statements)
- Documentation standards
- Module structure patterns

**Shell (`instructions/shell.md`):**
- Shebang and set options
- Variable naming and quoting rules
- Error handling patterns
- Stdout vs stderr usage
- Shellcheck compliance requirements

**Markdown (`instructions/markdown.md`):**
- Prettier configuration preferences
- Line wrapping (100 characters)
- Heading hierarchy
- Code block formatting
- Link and reference styles

## Local Development

### Install Tools

```bash
# Lua tools
luarocks install luacheck
luarocks install busted
luarocks install luacov

# Install stylua
wget https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux-x86_64.zip
unzip stylua-linux-x86_64.zip
sudo mv stylua /usr/local/bin/

# Node tools
npm install -g prettier

# Shell tools (usually pre-installed)
# shellcheck is often available via package manager
```

### Run Checks Locally

```bash
# Lint Lua code
luacheck *.lua lib/ spec/

# Format Lua code
stylua --sort-requires --indent-type Spaces --indent-width 4 *.lua lib/ spec/

# Check Lua formatting
stylua --check --sort-requires --indent-type Spaces --indent-width 4 *.lua lib/ spec/

# Check shell scripts
shellcheck *.sh

# Format markdown
prettier --write "docs/**/*.md" "*.md"

# Check markdown formatting
prettier --check "docs/**/*.md" "*.md"

# Run tests
busted spec/

# Build documentation
mdbook build

# Build package
./package.sh
```

### Pre-commit Checklist

Before pushing changes:

1. ✅ Format Lua code with stylua
2. ✅ Check Lua code with luacheck
3. ✅ Check shell scripts with shellcheck
4. ✅ Format markdown with prettier
5. ✅ Run tests with busted
6. ✅ Build package with package.sh (if plugin files changed)
7. ✅ Build docs with mdbook (if docs changed)

## Creating a Release

### 1. Use Conventional Commits

```bash
# Feature (minor version bump)
git commit -m "feat: add new synchronization feature"

# Bug fix (patch version bump)
git commit -m "fix: resolve reading state sync issue"

# Breaking change (major version bump)
git commit -m "feat: redesign plugin API

BREAKING CHANGE: Plugin API has been completely redesigned"

# No version bump
git commit -m "docs: update installation guide"
git commit -m "chore: update dependencies"
```

### 2. Push to Main

```bash
git push origin main
```

### 3. Review Release PR

- release-please will create a PR automatically
- Review the changelog and version bump
- Merge the PR when ready

### 4. Release Created

- GitHub Release is created automatically
- Artifacts are uploaded (kobo.koplugin.zip, kobo-patches.zip)
- Checksums are generated (SHA256)
- Release notes are generated from commits

## Troubleshooting

### Workflow Not Running

- Check if relevant files changed (workflows use change detection)
- Verify GitHub Actions is enabled in repository settings
- Check workflow logs for errors

### Lint Failures

**Luacheck fails:**
```bash
# Run locally to see issues
luacheck *.lua lib/ spec/

# Fix issues in code
# Re-run to verify
```

**Stylua fails:**
```bash
# Format code locally
stylua --sort-requires --indent-type Spaces --indent-width 4 *.lua lib/ spec/

# Commit formatted code
```

**Prettier fails:**
```bash
# Format markdown locally
prettier --write "docs/**/*.md" "*.md"

# Commit formatted markdown
```

**Shellcheck fails:**
```bash
# Check scripts locally
shellcheck *.sh

# Fix issues following shellcheck suggestions
```

### Test Failures

```bash
# Run tests locally
busted spec/

# Check specific test file
busted spec/my_test_spec.lua

# Run with verbose output
busted --verbose spec/
```

### Build Failures

```bash
# Test package script
./package.sh

# Check output
ls -lh /tmp/kobo.koplugin.zip
unzip -l /tmp/kobo.koplugin.zip
```

### Documentation Build Failures

```bash
# Build docs locally
mdbook build

# Clean and rebuild
mdbook clean
mdbook build

# Serve locally for testing
mdbook serve
```

## GitHub Pages Setup

To enable documentation deployment:

1. Go to repository Settings → Pages
2. Set Source to: "Deploy from a branch"
3. Select Branch: `docs`
4. Select Directory: `/` (root)
5. Save

Documentation will be automatically deployed when changes are pushed to main branch.

## Security Notes

- Workflows use `actions/checkout@v4` (latest stable)
- `tj-actions/changed-files@v47` is pinned to specific version
- Artifacts have 7-day retention (not permanent storage)
- Release assets include SHA256 checksums for verification
- Workflows use minimal permissions (only what's needed)

## Maintenance

### Updating Workflow Dependencies

Check for updates regularly:

- GitHub Actions: `actions/checkout`, `actions/upload-artifact`
- Third-party actions: `tj-actions/changed-files`, `googleapis/release-please-action`
- Tools: stylua, prettier, luacheck versions

### Monitoring CI Usage

- Check Actions tab for workflow runs
- Monitor artifact storage usage
- Review workflow execution times
- Optimize change detection patterns if needed

## Support

For issues or questions:

1. Check workflow logs in Actions tab
2. Review this README and copilot-instructions.md
3. Check language-specific instructions in `instructions/`
4. Open an issue in the repository
