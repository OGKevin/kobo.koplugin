# KOReader DocSettings

This document describes how KOReader stores reading progress in sidecar files.

## DocSettings (Sidecar Files)

KOReader stores reading progress in "sidecar" files alongside the book files. These are Lua tables serialized to disk.

### File Location

For a book at `/mnt/onboard/.kobo/kepub/book.epub`, the sidecar is at:
```
/mnt/onboard/.kobo/kepub/book.sdr/metadata.epub.lua
```

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
