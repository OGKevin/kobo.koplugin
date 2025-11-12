# Database Queries

This document lists all SQL queries used by the plugin to interact with the Kobo database.

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
