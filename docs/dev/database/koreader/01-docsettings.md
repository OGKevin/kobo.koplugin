# KOReader DocSettings

This document describes how KOReader stores reading progress in sidecar files.

## DocSettings (Sidecar Files)

KOReader stores reading progress in "sidecar" files alongside the book files. These are Lua tables
serialized to disk.

### File Location

KOReader supports three location modes for storing sidecar files, configured via the "Document
metadata folder" setting:

1. **Document folder ("doc")**: Sidecar stored next to the book file
2. **docsettings folder ("dir")**: Sidecar stored in a central docsettings directory
3. **Hash folder ("hash")**: Sidecar stored in a hashed subdirectory structure

For books opened through the virtual library, the plugin automatically overrides the "doc" location
to use "dir" location instead.

#### Example Locations

**Standard EPUB** with "doc" location:

```
/mnt/onboard/Books/book.epub
/mnt/onboard/Books/book.sdr/metadata.epub.lua
```

**Virtual library book** with "doc" location (automatically overridden to "dir"):

```
/mnt/onboard/.kobo/kepub/ABC123
/mnt/onboard/.adds/koreader/docsettings/mnt/onboard/.kobo/kepub/ABC123.sdr/metadata.kepub.epub.lua
```

#### Virtual Library Books Location Override

The plugin overrides "doc" location to "dir" for virtual library books to prevent data loss. This is
necessary because:

- Kobo's system may delete unrecognized files in the virtual library directory during maintenance
  operations
- Storing sidecar files alongside virtual library books could result in loss of reading progress and
  bookmarks
- The "dir" location stores sidecars in KOReader's dedicated folder, which Kobo's system does not
  touch

**Note**: The "hash" location is respected and not overridden, as it also stores files outside the
virtual library directory.

### Key Fields

```lua
{
    -- Core progress data
    percent_finished = 0.673,        -- 0.0 to 1.0 (67.3% read)
    last_percent = 0.673,            -- Last known percent

    -- Status and metadata
    summary = {
        status = "reading",          -- "reading", "complete", or "finished"
        modified = "2024-01-15",     -- Last modification date
    },

    -- Page/position data (depends on document type)
    last_xpointer = "/body/div[2]/p[15]",  -- Position in EPUB
    page = 42,                       -- Current page number (PDFs)

    -- Timestamps (stored by ReadHistory, not in sidecar directly)
    -- See ReadHistory section below
}
```

## How KOReader Calculates Percent

The `percent_finished` field is calculated differently based on document type:

### EPUB (Reflowable)

```lua
-- Position is tracked by XPointer (path in DOM tree)
-- Percentage = (current_position_bytes / total_document_bytes)

-- Example:
percent_finished = 0.673  -- 67.3% through the document
```

### PDF (Fixed Layout)

```lua
-- Position is tracked by page number
-- Percentage = (current_page / total_pages)

-- Example:
-- Page 42 of 100 pages
percent_finished = 0.42  -- 42%
```
