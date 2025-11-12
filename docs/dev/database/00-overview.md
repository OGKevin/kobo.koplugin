# Database & Data Storage Overview

This section explains how the plugin interacts with both Kobo's database and KOReader's storage
system to synchronize reading progress.

## The Fundamental Difference

```mermaid
graph TD
    subgraph "Kobo's Approach"
        A[Single SQLite Database] --> B[All books in one place]
        B --> C[Chapter-based positioning]
        C --> D[Unknown coordinate format]
    end

    subgraph "KOReader's Approach"
        E[Sidecar files per book] --> F[Distributed storage]
        F --> G[Percentage-based positioning]
        G --> H[Precise decimal positioning]
    end

    style A fill:#fff3e0
    style E fill:#e1f5ff
```

## Why This Matters

These architectural differences create the core challenge the plugin solves:

1. **Storage location**: Kobo uses one central database, KOReader uses individual files
2. **Position format**: Kobo uses chapter+coordinate system (format unknown), KOReader uses
   percentages
3. **Precision**: Kobo can point to specific positions within chapters, KOReader tracks overall
   progress
4. **Timestamps**: Kobo stores ISO 8601 strings in database, KOReader uses file modification times

## Quick Reference

### Data Flow Summary

```mermaid
sequenceDiagram
    participant K as Kobo DB
    participant P as Plugin
    participant R as KOReader

    Note over K,R: Reading State Sync

    P->>K: Read: percent, timestamp, status
    P->>R: Read: percent_finished, file mtime

    P->>P: Compare timestamps

    alt Kobo is newer
        P->>R: Update percent_finished
        Note over R: KOReader gets Kobo's progress
    else KOReader is newer
        P->>K: Update at chapter boundary
        Note over K: Kobo gets KOReader's progress
    else Equal
        Note over P: No sync needed
    end
```

### Key Files in Codebase

| File                          | Purpose                             |
| ----------------------------- | ----------------------------------- |
| `lib/kobo_state_reader.lua`   | Reads progress from Kobo database   |
| `lib/kobo_state_writer.lua`   | Writes progress to Kobo database    |
| `lib/sync_decision_maker.lua` | Decides when/how to sync            |
| `reading_state_sync.lua`      | Coordinates sync operations         |
| `metadata_parser.lua`         | Queries Kobo database for book info |

See the individual topics above for detailed explanations of how each system works and how the
plugin bridges them.
