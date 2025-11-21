# Database Queries

This document lists all SQL queries used by the plugin to interact with the Kobo database.

## Virtual Library Book Discovery

The virtual library uses a reverse lookup approach to discover books:

```sql
-- Bulk metadata query for discovered book files
-- Used after scanning the kepub directory for files
SELECT ContentID, Title, Attribution, Publisher, Series, SeriesNumber, ___PercentRead
FROM content
WHERE ContentType = 6 AND ContentID IN (?, ?, ?, ...)
```

### Why Reverse Lookup?

Previously, the plugin queried the database first with ID format filters (`NOT LIKE '%-%'` to
exclude UUID-style IDs), then checked if those files existed. This failed for books synced from
Calibre Web which use UUID-style IDs like `a3a06c7b-f1a0-4f6b-8fae-33b6926124e4`.

The new approach:

1. **Scans the kepub directory** (`/mnt/onboard/.kobo/kepub/`) for all files
2. **Filters out encrypted files** by checking for valid ZIP/EPUB signature (PK\x03\x04)
3. **Queries metadata in one batch** using `WHERE ContentID IN (...)` with all unencrypted book IDs
4. **Merges the results** to create the final accessible book list

This supports **all book ID formats** regardless of naming conventions while maintaining efficiency
through a single bulk query.

## Reading Progress (Pull from Kobo)

```sql
-- Main book query
SELECT DateLastRead, ReadStatus, ChapterIDBookmarked, ___PercentRead
FROM content
WHERE ContentID = ? AND ContentType = 6
LIMIT 1

-- Chapter lookup (to calculate exact progress using ___FileOffset directly)
SELECT ContentID, ___FileOffset, ___FileSize, ___PercentRead
FROM content
WHERE ContentID LIKE '?%' AND ContentType = 9
  AND (ContentID LIKE '%?' OR ContentID LIKE '%?#%')
LIMIT 1
```

## Writing Progress (Push to Kobo)

```sql
-- Find target chapter using ___FileOffset
SELECT ContentID, ___FileOffset, ___FileSize
FROM content
WHERE ContentID LIKE '?%' AND ContentType = 9
  AND ___FileOffset <= ?
ORDER BY ___FileOffset DESC
LIMIT 1

-- Fallback: Get last chapter (if position is beyond all chapters)
SELECT ContentID
FROM content
WHERE ContentID LIKE '?%' AND ContentType = 9
ORDER BY ___FileOffset DESC
LIMIT 1

-- Update main book entry
UPDATE content
SET ___PercentRead = ?,
    DateLastRead = ?,
    ReadStatus = ?,
    ChapterIDBookmarked = ?
WHERE ContentID = ? AND ContentType = 6

-- Update current chapter entry
UPDATE content
SET ___PercentRead = ?
WHERE ContentID = ? AND ContentType = 9
```

## Data Flow Diagram

```mermaid
sequenceDiagram
    participant P as Plugin
    participant DB as Kobo Database
    participant BE as Book Entry<br/>(ContentType=6)
    participant CE as Chapter Entries<br/>(ContentType=9)

    Note over P: Reading from Kobo
    P->>DB: Query book entry
    DB->>BE: SELECT DateLastRead, ReadStatus, ChapterIDBookmarked, ___PercentRead
    BE-->>P: Return book data

    P->>DB: Query chapters
    DB->>CE: SELECT ContentID, ___FileOffset, ___FileSize, ___PercentRead
    CE-->>P: Return chapter data

    P->>P: Calculate total progress<br/>from chapter offsets/sizes

    Note over P: Writing to Kobo
    P->>P: Find target chapter<br/>for percentage
    P->>DB: Update chapter entry
    DB->>CE: UPDATE ___PercentRead
    P->>DB: Update book entry
    DB->>BE: UPDATE ___PercentRead, DateLastRead,<br/>ReadStatus, ChapterIDBookmarked
```
