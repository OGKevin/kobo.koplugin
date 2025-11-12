# Shell Script Coding Guidelines

## Formatting Standards

All shell scripts (`.sh` files) must follow these standards:

**Key principles:**

- Use `bash` or `zsh` with proper shebang: `#!/usr/bin/env bash`
- 4-space indentation (consistent with Lua)
- Quote all variables: `"$var"` instead of `$var`
- Use shellcheck for static analysis

## Shell Script Best Practices

### 1. Shebang & Set Options

```bash
#!/usr/bin/env bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure
```

**When to use:**

- `set -e`: Always use for scripts that should fail fast
- `set -u`: Use when all variables should be defined
- `set -o pipefail`: Use when working with pipes

### 2. Variable Naming

- Use UPPER_SNAKE_CASE for constants
- Use lowercase with underscores for local variables
- Always quote variables in double quotes

```bash
readonly PLUGIN_NAME="kobo"
readonly OUTPUT_DIR="/tmp"

work_dir=$(mktemp -d)
current_file="example.txt"

# Always quote variables
echo "Processing $current_file"
cp "$source_file" "$dest_file"
```

### 3. Comments & Documentation

- Add header comment explaining script purpose
- Use inline comments for non-obvious logic
- Document complex functions with purpose and parameters

```bash
#!/usr/bin/env bash
# Creates plugin distribution package
# Outputs to $OUTPUT_DIR
#
# Usage: ./package.sh

set -e

# Define constants
readonly PLUGIN_NAME="kobo"
readonly OUTPUT_DIR="/tmp"

# Main packaging function
package_plugin() {
    local work_dir="$1"
    # Implementation
}
```

### 4. Error Handling

- Use `trap` for cleanup on exit
- Provide meaningful error messages
- Check command return codes

```bash
trap "rm -rf $work_dir" EXIT

if [ ! -f "$file" ]; then
    echo "Error: File not found: $file" >&2
    exit 1
fi

# Check command success
if ! command_that_might_fail; then
    echo "Error: Command failed" >&2
    exit 1
fi
```

### 5. Command Structure

- One command per line (avoid long chained commands)
- Use `if` statements instead of `&&` chains for clarity
- Avoid subshells when possible

```bash
# GOOD
if command1; then
    command2
else
    echo "Error: command1 failed" >&2
    exit 1
fi

# AVOID
command1 && command2 || (echo "Error" >&2; exit 1)
```

### 6. Stdout vs Stderr

- Output informational messages to stdout
- Output errors to stderr (`>&2`)
- Keep scripts composable/pipeable

```bash
echo "Processing started..."           # stdout
echo "Processing file: $filename"      # stdout

echo "Warning: File missing" >&2       # stderr
echo "Error: Invalid input" >&2        # stderr
```

## Function Structure

### Function Definition

```bash
# Function with documentation
# Args:
#   $1 - Input file path
#   $2 - Output directory
# Returns:
#   0 on success, 1 on failure
process_file() {
    local input_file="$1"
    local output_dir="$2"

    if [ ! -f "$input_file" ]; then
        echo "Error: Input file not found: $input_file" >&2
        return 1
    fi

    # Process the file
    cp "$input_file" "$output_dir/"

    return 0
}
```

### Function Calls

```bash
# Call function with arguments
if process_file "$source" "$destination"; then
    echo "Processing successful"
else
    echo "Processing failed" >&2
    exit 1
fi
```

## Common Patterns

### File and Directory Checks

```bash
# Check if file exists
if [ -f "$file" ]; then
    echo "File exists"
fi

# Check if directory exists
if [ -d "$dir" ]; then
    echo "Directory exists"
fi

# Check if file is executable
if [ -x "$script" ]; then
    echo "File is executable"
fi

# Check if file is readable
if [ -r "$file" ]; then
    echo "File is readable"
fi
```

### String Operations

```bash
# String comparison
if [ "$var1" = "$var2" ]; then
    echo "Strings are equal"
fi

# String contains
if [[ "$string" == *"substring"* ]]; then
    echo "String contains substring"
fi

# String is empty
if [ -z "$var" ]; then
    echo "Variable is empty"
fi

# String is not empty
if [ -n "$var" ]; then
    echo "Variable is not empty"
fi
```

### Loops

```bash
# Loop over files
for file in *.txt; do
    if [ -f "$file" ]; then
        process_file "$file"
    fi
done

# Loop over arguments
for arg in "$@"; do
    echo "Argument: $arg"
done

# While loop
while IFS= read -r line; do
    echo "Line: $line"
done < "$input_file"
```

### Temporary Files and Directories

```bash
# Create temporary directory
work_dir=$(mktemp -d)

# Cleanup on exit
trap "rm -rf $work_dir" EXIT

# Create temporary file
temp_file=$(mktemp)
echo "data" > "$temp_file"
```

### Command Output

```bash
# Capture command output
output=$(command)

# Capture and check exit code
if output=$(command 2>&1); then
    echo "Command succeeded: $output"
else
    echo "Command failed: $output" >&2
    exit 1
fi

# Redirect stderr to stdout
output=$(command 2>&1)

# Redirect stdout to file
command > output.txt

# Redirect stderr to file
command 2> error.txt

# Redirect both to file
command > output.txt 2>&1
```

## Shellcheck Compliance

This project uses shellcheck for static analysis. Configuration in `.shellcheckrc`:

```bash
# Shellcheck configuration for kobo.koplugin
# Enable strict checking
disable=SC2034  # Ignore unused variables (can enable during development)
```

### Common Shellcheck Rules

- **SC2086**: Quote expansion of variables
  ```bash
  # Bad
  cp $file $dest
  
  # Good
  cp "$file" "$dest"
  ```

- **SC2181**: Check exit code explicitly
  ```bash
  # Bad
  command
  if [ $? -eq 0 ]; then
  
  # Good
  if command; then
  ```

- **SC2154**: Check undefined variables
  ```bash
  # Use set -u to catch undefined variables
  set -u
  ```

- **SC2155**: Separate declaration and assignment
  ```bash
  # Bad
  local var=$(command)
  
  # Good
  local var
  var=$(command)
  ```

## Script Template

```bash
#!/usr/bin/env bash
# Script description
# Usage: ./script.sh [arguments]

set -e
set -u
set -o pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Variables
work_dir=""

# Cleanup function
cleanup() {
    if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
        rm -rf "$work_dir"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main function
main() {
    work_dir=$(mktemp -d)
    
    echo "Starting $SCRIPT_NAME..."
    
    # Script logic here
    
    echo "Completed successfully"
}

# Run main function
main "$@"
```

## Anti-Patterns to Avoid

1. **Unquoted Variables** - Always quote: `"$var"`
2. **Using `cd` without checking** - Check if directory exists first
3. **Not checking command exit codes** - Use `set -e` or check explicitly
4. **Using `ls` for file processing** - Use globbing or `find` instead
5. **Not cleaning up temporary files** - Use `trap` for cleanup
6. **Parsing `ls` output** - Use shell globbing or `find`
7. **Using `echo` for complex output** - Use `printf` for formatted output

## Best Practices Summary

1. **Always quote variables**: `"$var"`
2. **Use `set -e`** to fail fast
3. **Use `set -u`** to catch undefined variables
4. **Use `trap` for cleanup**
5. **Check file existence before operations**
6. **Write errors to stderr**: `>&2`
7. **Use `readonly` for constants**
8. **Validate inputs early**
9. **Use meaningful variable names**
10. **Add comments for complex logic**
11. **Run shellcheck on all scripts**
12. **Test scripts with different inputs**
