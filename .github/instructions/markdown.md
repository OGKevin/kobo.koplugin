# Markdown Formatting Guidelines

## Overview

This project uses **Prettier** to format Markdown files consistently. All documentation should
follow these standards.

## Prettier Configuration

Configuration in `.prettierrc`:

```json
{
  "proseWrap": "always",
  "printWidth": 100,
  "trailingComma": "es5"
}
```

**Key settings:**

- **proseWrap**: `always` - Wraps prose at printWidth
- **printWidth**: `100` - Maximum line length
- **trailingComma**: `es5` - For JSON files

## Line Wrapping

Prose should wrap at 100 characters for readability:

```markdown
This is a long paragraph that will be automatically wrapped by prettier at 100 characters to ensure
consistent line lengths across all documentation files.
```

## Heading Hierarchy

Use proper heading hierarchy (no skipping levels):

```markdown
# Main Title (H1)

Introduction paragraph...

## Section Title (H2)

Section content...

### Subsection Title (H3)

Subsection content...

#### Minor Heading (H4)

Only use when necessary for deep organization.
```

## Code Blocks

Always specify the language for syntax highlighting:

````markdown
```lua
local function example()
    return "Hello, World!"
end
```

```bash
#!/usr/bin/env bash
echo "Shell script example"
```

```json
{
  "key": "value"
}
```
````

## Lists

### Unordered Lists

Use `-` for unordered lists (consistent with prettier):

```markdown
- First item
- Second item
  - Nested item
  - Another nested item
- Third item
```

### Ordered Lists

Use `1.` for all ordered list items (prettier will renumber):

```markdown
1. First step
1. Second step
1. Third step
```

### Task Lists

Use task lists for checkboxes:

```markdown
- [x] Completed task
- [ ] Pending task
- [ ] Another pending task
```

## Links

### Inline Links

```markdown
[Link text](https://example.com) [Link with title](https://example.com "Hover title")
```

### Reference Links

For frequently used links:

```markdown
See the [documentation][docs] for more information.

[docs]: https://example.com/docs
```

### Internal Links

Link to other documentation pages:

```markdown
See [Installation Guide](installation.md) for setup instructions.
```

## Images

```markdown
![Alt text](path/to/image.png) ![Alt text with title](path/to/image.png "Image title")
```

## Tables

Use tables for structured data:

```markdown
| Column 1 | Column 2 | Column 3 |
| -------- | -------- | -------- |
| Data 1   | Data 2   | Data 3   |
| Data 4   | Data 5   | Data 6   |
```

Prettier will automatically align table columns.

## Blockquotes

```markdown
> This is a blockquote. It can span multiple lines.

> **Note:** You can use formatting inside blockquotes.
```

## Emphasis

```markdown
**Bold text** for strong emphasis _Italic text_ for mild emphasis **_Bold and italic_** for combined
emphasis `code` for inline code
```

## Horizontal Rules

Use three hyphens for horizontal rules:

```markdown
---
```

## File Organization

### Documentation Structure

```
docs/
├── SUMMARY.md          # Table of contents (mdBook)
├── introduction.md     # Project introduction
├── getting-started.md  # Quick start guide
├── features/           # Feature documentation
│   ├── README.md
│   └── feature.md
└── dev/                # Developer documentation
    ├── README.md
    └── contributing.md
```

### SUMMARY.md (mdBook)

The table of contents for mdBook:

```markdown
# Summary

[Introduction](introduction.md)

- [Getting Started](getting-started.md)
- [Features](features.md)
  - [Feature 1](features/feature1.md)
  - [Feature 2](features/feature2.md)

---

- [Development](dev/README.md)
  - [Contributing](dev/contributing.md)
```

## Front Matter

For documentation with metadata:

```markdown
---
title: Page Title
description: Page description
date: 2024-01-01
---

# Page Title

Content starts here...
```

## Best Practices

### 1. Use Descriptive Headings

```markdown
<!-- Good -->

## Installation on Linux

<!-- Bad -->

## Install
```

### 2. Keep Paragraphs Focused

One idea per paragraph. Separate paragraphs with blank lines.

```markdown
This paragraph discusses one topic.

This paragraph discusses a different topic.
```

### 3. Use Examples

Include code examples to illustrate concepts:

````markdown
To install the plugin, run:

```bash
cp kobo.koplugin /path/to/koreader/plugins/
```
````

### 4. Link to Related Content

```markdown
See also:

- [Configuration Guide](configuration.md)
- [Troubleshooting](troubleshooting.md)
```

### 5. Use Admonitions (if supported)

For important notes, warnings, or tips:

```markdown
> **Note:** This feature requires KOReader 2024.01 or later.

> **Warning:** This operation cannot be undone.

> **Tip:** Use keyboard shortcuts to speed up your workflow.
```

## Common Patterns

### Feature Documentation

````markdown
# Feature Name

Brief description of the feature.

## Overview

Detailed explanation of what the feature does and why it's useful.

## Usage

Step-by-step instructions:

1. First step
1. Second step
1. Third step

## Example

```lua
-- Example code
local feature = Feature.new()
feature:enable()
```
````

## Configuration

Available configuration options:

- `option1`: Description
- `option2`: Description

## Troubleshooting

Common issues and solutions.

````

### API Documentation

```markdown
## Function Name

Description of what the function does.

### Parameters

- `param1` (string): Description of first parameter
- `param2` (number, optional): Description of second parameter

### Returns

- (boolean): True if successful, false otherwise

### Example

```lua
local result = functionName("value", 42)
````

````

## Running Prettier

```bash
# Check formatting
prettier --check "docs/**/*.md" "*.md"

# Fix formatting
prettier --write "docs/**/*.md" "*.md"
````

## Files to Format

Include in prettier formatting:

- Documentation in `docs/` directory
- Root-level markdown files (`README.md`, `CHANGELOG.md`, etc.)
- Exclude generated files (in `.prettierignore`)

## Anti-Patterns to Avoid

1. **Inconsistent heading levels** - Don't skip levels (H1 → H3)
2. **Long lines** - Let prettier wrap at 100 characters
3. **Inconsistent list markers** - Use `-` for unordered lists
4. **Missing language in code blocks** - Always specify language
5. **Broken links** - Verify links work before committing
6. **Empty sections** - Remove or mark as TODO
7. **Unclear headings** - Be specific and descriptive

## mdBook-Specific Guidelines

### Table of Contents

Always update `SUMMARY.md` when adding new pages:

```markdown
# Summary

- [New Page](path/to/new-page.md)
```

### Internal Links

Use relative paths for internal links:

```markdown
[Link to another page](../other-page.md)
```

### Build and Preview

```bash
# Build documentation
mdbook build

# Serve documentation locally
mdbook serve

# Clean build artifacts
mdbook clean
```

## Accessibility

1. **Use descriptive alt text for images**
2. **Use proper heading hierarchy**
3. **Write clear link text** (avoid "click here")
4. **Keep content scannable** with headings and lists
5. **Use tables for tabular data** (not for layout)

## Version Control

- Commit formatted markdown files
- Don't commit the `book/` directory (build output)
- Use meaningful commit messages for documentation changes

```bash
docs: add installation guide
docs: update feature documentation
docs: fix broken links
```
