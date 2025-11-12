#!/usr/bin/env bash
set -e

# Define variables
PLUGIN_NAME="kobo"
OUTPUT_DIR="/tmp"
WORK_DIR=$(mktemp -d)

# Cleanup on exit
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Starting package process..."

# Create the plugin directory structure
mkdir -p "$WORK_DIR/$PLUGIN_NAME.koplugin"

echo "Copying plugin files..."

# Copy main files
cp _meta.lua main.lua "$WORK_DIR/$PLUGIN_NAME.koplugin/"

# Copy all Lua files in the root directory
for file in *.lua; do
    if [ -f "$file" ]; then
        cp "$file" "$WORK_DIR/$PLUGIN_NAME.koplugin/"
    fi
done

# Copy directories
if [ -d "lib" ]; then
    cp -r lib "$WORK_DIR/$PLUGIN_NAME.koplugin/"
    echo "Copied lib directory"
fi

if [ -d "patches" ]; then
    cp -r patches "$WORK_DIR/$PLUGIN_NAME.koplugin/"
    echo "Copied patches directory"
fi

# Copy documentation and metadata files if they exist
for file in README.md CHANGELOG.md LICENSE.md LICENSE version.txt; do
    if [ -f "$file" ]; then
        cp "$file" "$WORK_DIR/$PLUGIN_NAME.koplugin/"
        echo "Copied $file"
    fi
done

# Copy the raw folder to /tmp
echo "Copying raw plugin folder to $OUTPUT_DIR..."
rm -rf "$OUTPUT_DIR/$PLUGIN_NAME.koplugin"
cp -r "$WORK_DIR/$PLUGIN_NAME.koplugin" "$OUTPUT_DIR/"

# Create ZIP archive
echo "Creating ZIP archive..."
cd "$WORK_DIR"
zip -r "$PLUGIN_NAME.koplugin.zip" "$PLUGIN_NAME.koplugin" -i '*.lua' '*.md' > /dev/null 2>&1 || true
cd - > /dev/null

# Copy ZIP to output directory
cp "$WORK_DIR/$PLUGIN_NAME.koplugin.zip" "$OUTPUT_DIR/"

echo ""
echo "✓ Packaging complete!"
echo "Output location: $OUTPUT_DIR"
echo "  - Raw folder: $OUTPUT_DIR/$PLUGIN_NAME.koplugin/"
echo "  - ZIP archive: $OUTPUT_DIR/$PLUGIN_NAME.koplugin.zip"
