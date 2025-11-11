# Reading State Sync

The Reading State Sync feature maintains consistent reading progress between KOReader and Kobo's native reader by synchronizing position, completion status, and reading statistics.

**Note:** When syncing to Kobo, reading position is updated only at chapter boundaries. Fine-grained position within a chapter is not preserved.

## Overview

Reading State Sync works by:
1. **Monitoring reading progress** in both KOReader and Kobo
2. **Comparing timestamps** to determine the most recent reading session
3. **Syncing progress and status** in the appropriate direction

## How Sync Works

### Bidirectional Synchronization
The plugin supports sync in both directions:

#### FROM Kobo TO KOReader (Pull)
- Retrieves progress from Kobo's database
- Updates KOReader's document settings
- Preserves reading position and completion status

#### FROM KOReader TO Kobo (Push)
- Reads KOReader's progress from sidecar files
- Writes to Kobo's SQLite database
- Updates reading statistics in Kobo

### Timestamp-Based Sync Decision

```mermaid
graph TD
    A[Read KOReader Progress] --> B[Read Kobo Progress]
    B --> C{Compare Timestamps}
    C -->|Kobo Newer| D[Sync FROM Kobo]
    C -->|KOReader Newer| E[Sync TO Kobo]
    C -->|Same/No Data| F[No Sync Needed]
    D --> G[Update KOReader Data]
    E --> H[Update Kobo Database]
    F --> I[Done]
    G --> I
    H --> I
```

## Sync Decision Flowchart
```mermaid
flowchart TD
    A[Start Sync] --> B{Progress Data Exists?}
    B -- "Neither" --> C[No Sync Needed]
    B -- "Both" --> D[Compare Timestamps]
    B -- "Only Kobo" --> E[Sync FROM Kobo]
    B -- "Only KOReader" --> F[Sync TO Kobo]
    D -- "Kobo Newer" --> E
    D -- "KOReader Newer" --> F
    D -- "Same/No Change" --> C
    E --> G[Update KOReader Data]
    F --> H[Update Kobo Database]
    G --> I[Done]
    H --> I
    C --> I
```

## Data Sources

### KOReader Data
Reading progress is stored in `.sdr` sidecar files managed by KOReader.

### Kobo Data
Progress is read from the `KoboReader.sqlite` database used by the Kobo system.

## Automatic Sync Triggers

### Library Access
```mermaid
graph TD
    A[Open Virtual Library] --> B{Auto-sync Enabled?}
    B -->|No| D[Show Library]
    B -->|Yes| C{Already Synced Since KOReader Started?}
    C -->|Yes| D
    C -->|No| E[Sync All Books]
    E --> D
```

## Document Close
```mermaid
graph TD
    A[Close Document] --> B{Is Virtual Kepub?}
    B -->|No| D[Normal Close]
    B -->|Yes| C[Extract Book ID]
    C --> E{Auto-sync Enabled?}
    E -->|No| F[Skip Sync]
    E -->|Yes| G[Sync TO Kobo]
    G --> H["Update Position<br/>(Chapter Boundary Only)"]
    H --> I[Return to Virtual Library]
    F --> I
```

**Important Limitation**: When syncing progress to Kobo, the position is updated only at chapter boundaries. Fine-grained position within a chapter is not preserved by Kobo's native reader.

However, when Kobo syncs progress back to KOReader, KOReader opens the book at the exact percentage received from Kobo, providing fine-grained positioning.