# ReadHistory and Timestamps

This document explains how KOReader tracks reading history and the challenges of determining
accurate timestamps.

## ReadHistory

KOReader maintains a separate `ReadHistory` object that tracks:

- When books were last opened
- Reading duration
- Final reading position

### Location

```lua
-- Global ReadHistory module
require("readhistory")
```

### Data Structure

```lua
ReadHistory.hist = {
    ["/path/to/book.epub"] = {
        file = "/path/to/book.epub",
        time = 1705330200,           -- Unix timestamp of last access
    },
}
```

## Timestamp Challenges

The plugin needs to determine "when was this book last read" to compare with Kobo's timestamp.

### Source of Timestamp

The plugin uses **ReadHistory only** as the source of truth for KOReader timestamps:

```lua
ReadHistory.hist = {
    ["/path/to/book.epub"] = {
        file = "/path/to/book.epub",
        time = 1705330200,  -- Unix timestamp from ReadHistory
    },
}
```

### Critical Validation: Sidecar File Check

A ReadHistory timestamp is only valid if the sidecar file exists:

```lua
function getValidatedKOReaderTimestamp(doc_path)
    -- 1. Get timestamp from ReadHistory
    local kr_timestamp = getKOReaderTimestampFromHistory(doc_path)

    if kr_timestamp == 0 then
        return 0
    end

    -- 2. Validate that sidecar file exists
    local has_sidecar = DocSettings:hasSidecarFile(doc_path)

    -- 3. Return 0 if no sidecar (no actual reading progress)
    if not has_sidecar then
        -- This ensures PULL from Kobo when KOReader has no valid data
        return 0
    end

    return kr_timestamp
end
```

### Why Sidecar Validation Matters

Without a sidecar (`.sdr`) file, there's no actual reading progress in KOReader. A ReadHistory entry
without a sidecar is unreliable:

- Could be from after a reset that deleted the `.sdr` file
- Could be a stale entry from a deleted book

By returning `0` when no sidecar exists, the plugin ensures:

- **PULL from Kobo**: Kobo's timestamp will always be newer than `0`
