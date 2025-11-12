# Data Flow and Status Mapping

This document shows how data flows between the plugin and KOReader, and how status values are
converted.

## Data Flow: Reading from KOReader

```mermaid
sequenceDiagram
    participant P as Plugin
    participant DS as DocSettings
    participant RH as ReadHistory
    participant FS as File System

    P->>DS: readSetting("percent_finished")
    DS-->>P: 0.673

    P->>DS: readSetting("summary")
    DS-->>P: {status: "reading"}

    P->>RH: Get timestamp for book
    RH-->>P: 1705330200 or 0

    P->>FS: Check if sidecar exists
    FS-->>P: true/false

    alt Sidecar exists
        P->>P: Use ReadHistory timestamp<br/>= 1705330200
    else No sidecar
        P->>P: Return 0<br/>(ensures PULL from Kobo)
    end
```

## Data Flow: Writing to KOReader

```mermaid
sequenceDiagram
    participant P as Plugin
    participant DS as DocSettings
    participant BL as BookList Cache

    Note over P: Syncing 67% from Kobo

    P->>DS: saveSetting("percent_finished", 0.67)
    P->>DS: saveSetting("last_percent", 0.67)

    P->>DS: Read current summary
    DS-->>P: {status: "reading", modified: "2024-01-14"}

    P->>P: Update status if needed<br/>(67% -> still "reading")

    P->>DS: saveSetting("summary", updated_summary)
    P->>DS: flush() (write to disk)

    P->>BL: Update UI cache
    Note over BL: BookList widget will show 67%
```

## Status Mapping

KOReader and Kobo use different status values:

| KOReader     | Kobo ReadStatus | Meaning                |
| ------------ | --------------- | ---------------------- |
| `"reading"`  | `1`             | In progress            |
| `"complete"` | `2`             | Finished               |
| `"finished"` | `2`             | Finished (alternative) |
| (not set)    | `0`             | Unopened               |

```lua
-- Converting Kobo -> KOReader
function StatusConverter.koboToKoreader(kobo_status)
    if kobo_status == 0 then return nil end        -- Unopened
    if kobo_status == 2 then return "complete" end -- Finished
    return "reading"                                -- 1 or 3
end

-- Converting KOReader -> Kobo
function StatusConverter.koreaderToKobo(kr_status)
    if kr_status == "complete" or kr_status == "finished" then
        return 2  -- Finished
    end
    return 1  -- Reading
end
```

## Example: Complete Sync Flow

```mermaid
sequenceDiagram
    participant K as Kobo DB
    participant P as Plugin
    participant DS as DocSettings
    participant RH as ReadHistory

    Note over P: User opens book in virtual library

    P->>K: Read Kobo state
    K-->>P: 45%, timestamp: 1705300000

    P->>DS: Read KOReader state
    DS-->>P: percent_finished: 0.67

    P->>RH: Get last read time
    RH-->>P: 1705330000

    P->>P: Compare timestamps<br/>KOReader newer (1705330000 > 1705300000)

    Note over P: Decision: Push KOReader -> Kobo

    P->>K: Write 67% to Kobo<br/>at chapter boundary
    K-->>P: Success

    Note over K: Kobo now shows 67%<br/>at start of chapter 2
```
