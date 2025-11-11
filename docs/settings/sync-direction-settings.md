# Sync Direction Settings

These settings control sync behavior based on which side (Kobo or KOReader) has newer progress. Each setting has three options: **PROMPT** (ask user), **SILENT** (automatic), or **NEVER** (skip).

## FROM Kobo (Pull) Sync Settings

### `sync_from_kobo_newer` (Default: `PROMPT`)
**When to use**: Kobo has more recent reading progress than KOReader

**Options**:
- **Prompt**: Show a dialog and ask whether to pull Kobo's newer progress
- **Silent**: Automatically pull newer progress from Kobo without asking
- **Never**: Keep KOReader progress, ignore newer Kobo data

**Example**: Kobo shows 45% (read yesterday), KOReader shows 30% (read 2 days ago). This setting decides what happens.

**Menu:** Kobo Library → Sync behavior → From Kobo to KOReader → Sync from newer state

### `sync_from_kobo_older` (Default: `NEVER`)
**When to use**: Kobo has a newer timestamp but lower progress percentage than KOReader

**Options**:
- **Prompt**: Show a dialog and ask whether to pull Kobo's progress despite it being less complete 
- **Silent**: Automatically pull Kobo's progress, overwriting KOReader's higher progress 
- **Never**: Keep KOReader's higher progress, don't regress to lower Kobo percentage (recommended)

**Example**: Kobo shows 40% (read today - newer timestamp), KOReader shows 80% (read 2 days ago - older timestamp). This setting decides what happens.

**Menu:** Kobo Library → Sync behavior → From Kobo to KOReader → Sync from older state

## FROM KOReader (Push) Sync Settings

### `sync_to_kobo_newer` (Default: `SILENT`)
**When to use**: KOReader has more recent reading progress than Kobo

**Options**:
- **Prompt**: Show a dialog and ask whether to push KOReader's newer progress  
- **Silent**: Automatically push newer progress to Kobo without asking (recommended)
- **Never**: Keep Kobo progress, don't update with newer KOReader data

**Example**: KOReader shows 65% (read today), Kobo shows 50% (read yesterday). This setting decides what happens.

**Menu:** Kobo Library → Sync behavior → From KOReader to Kobo → Sync to newer state

### `sync_to_kobo_older` (Default: `NEVER`)
**When to use**: KOReader has a newer timestamp but lower progress percentage than Kobo

**Options**:
- **Prompt**: Show a dialog and ask whether to push KOReader's progress despite it being less complete (unusual)
- **Silent**: Automatically push KOReader's progress, overwriting Kobo's higher progress (unusual)
- **Never**: Keep Kobo's higher progress, don't regress to lower KOReader percentage (recommended)

**Example**: KOReader shows 40% (read today - newer timestamp), Kobo shows 80% (read 2 days ago - older timestamp). This setting decides what happens.

**Menu:** Kobo Library → Sync behavior → From KOReader to Kobo → Sync to older state

## Understanding "Newer" vs "Older"

The plugin compares the timestamps of when progress was last updated:

- **Newer:** The more recent progress update (more recently modified timestamp)
- **Older:** The less recent progress update (older modification timestamp)

However, "older" in the setting names refers to scenarios where the source has a **newer timestamp** but **lower progress percentage**. This can happen when someone re-reads earlier parts of a book.

These settings let you decide whether to keep progress based on timestamps or based on completion percentage in each direction.

