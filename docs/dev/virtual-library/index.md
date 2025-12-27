# Virtual Library Implementation

The virtual library system creates a seamless integration between Kobo's native kepub collection and
KOReader's file browser, allowing users to access their Kobo library without switching between
reading applications.

## Overview

The virtual library implementation consists of several key components:

1. **Metadata Parser** (`src/metadata_parser.lua`) - Reads Kobo's SQLite database to retrieve book
   metadata
2. **Virtual Filesystem** (`src/filesystem_ext.lua`) - Provides filesystem operations for virtual
   paths
3. **File Chooser Extensions** (`src/filechooser_ext.lua`) - Integrates the virtual library into
   KOReader's file browser

## Key Features

- **Automatic Discovery**: Scans Kobo's kepub directory and matches files with database metadata
- **DRM Detection**: Identifies encrypted books to prevent access errors
- **Metadata Integration**: Displays book titles, authors, and cover images from Kobo's database
- **Transparent Access**: Books appear as regular files in KOReader's file browser

## Topics

- [DRM Detection](./drm-detection.md) - How the plugin identifies encrypted books
