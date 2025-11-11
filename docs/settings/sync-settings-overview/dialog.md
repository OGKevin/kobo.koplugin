# Sync Decision Dialog

When [Sync Direction Settings](../sync-direction-settings.md) are set to **PROMPT**, the plugin shows a dialog whenever a sync decision needs to be made.

## Dialog Format

```
Book: The Great Gatsby

Kobo: 45% (2024-01-15 14:30)
KOReader: 38% (2024-01-14 22:15)

Sync newer reading progress from Kobo?
```

## When Dialogs Appear

Dialogs appear when:
1. A book has different reading positions in KOReader and Kobo
2. [Sync Direction Settings](../sync-direction-settings.md) are set to **PROMPT** for that scenario
3. The sync decision is about to be made (newer or older state)

### Dialog Behavior

When you see a dialog, you have two options:

| Button | Effect |
|--------|--------|
| **Yes** | Proceed with the sync operation |
| **No** | Skip this sync decision, no changes are made |

### Example Scenarios

**Scenario 1: Pull newer from Kobo**
```
Book: The Great Gatsby

Kobo: 60% (2024-01-15 14:30)
KOReader: 40% (2024-01-14 22:15)

Sync newer reading progress from Kobo?
```
- Kobo has newer timestamp (newer progress)
- Appears when `sync_from_kobo_newer = PROMPT`
- Click **Yes** to update KOReader to 60%, or **No** to keep 40%

**Scenario 2: Push older to Kobo**
```
Book: The Great Gatsby

KOReader: 35% (2024-01-13 10:00)
Kobo: 50% (2024-01-14 22:15)

Sync older reading progress to Kobo?
```
- KOReader has older progress (less complete)
- Appears when `sync_to_kobo_older = PROMPT`
- Click **Yes** to revert Kobo to 35%, or **No** to keep 50%
