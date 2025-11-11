# Sync Flow Diagram

**Note**: This diagram assumes the recommended settings are enabled (auto-sync ON).

**Important Limitation**: When syncing to Kobo, position is rounded to chapter boundaries. When Kobo syncs back to KOReader, KOReader opens at the exact percentage from Kobo.

```mermaid
sequenceDiagram
    participant Komga as Komga/<br/>Calibre Web
    participant Kobo as Kobo<br/>Database
    participant VLib as Virtual<br/>Library
    participant KOR as KOReader
    
    Komga->>Kobo: New book or update
    
    Note over VLib: User opens KOReader
    KOR->>VLib: Browse library
    VLib->>Kobo: Read book list
    
    Note over VLib: Auto-sync triggered (first open per session)
    VLib->>Kobo: Sync all books progress
    Kobo->>VLib: Return latest progress
    
    Note over KOR: User selects and opens book
    KOR->>KOR: Open book at last synced position (fine-grained %)
    
    Note over KOR: User reads to 45%
    
    Note over KOR: User closes book
    Note over KOR,Kobo: Sync TO Kobo (rounded to chapter boundary)
    KOR->>Kobo: Write 45% progress (as chapter position)
    Kobo->>Kobo: Update book status
    
    Note over Kobo: User opens Kobo native
    Kobo->>Kobo: Read progress (at chapter boundary)
    Kobo->>Kobo: Open book at chapter boundary
    
    Note over Kobo: User reads to 60%
    
    Note over Kobo: User closes book
    Kobo->>Kobo: Update to 60%
    
    Note over VLib: User opens KOReader again (new session)
    KOR->>VLib: Browse library
    VLib->>Kobo: Read book list
    
    Note over VLib: Auto-sync triggered (first open in new session)
    VLib->>Kobo: Sync all books progress
    Kobo->>VLib: Return 60% progress
    
    Note over KOR: User selects and opens book
    Note over KOR: Sync FROM Kobo (fine-grained %)
    KOR->>KOR: Open book at 60% (fine-grained position from Kobo)
```

This diagram shows the complete flow of how books and reading progress move through the system when using Komga or Calibre Web with the Kobo Plugin. The key points are:
- Books are always displayed in the virtual library (independent of sync setting)
- Reading **progress** syncs automatically when:
  - Accessing the virtual library (if auto-sync enabled) - syncs all books once per session
  - Closing a book - always syncs that book's progress to Kobo (rounded to chapter boundary)
- KOReader uses fine-grained percentages when opening books (from either app)
- Kobo uses chapter-based positioning when opening books
