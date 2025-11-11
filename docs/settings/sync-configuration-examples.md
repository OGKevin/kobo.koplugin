# Sync Configuration Examples

Common configuration patterns for different use cases. Choose the pattern that best matches your reading habits.

## Conservative Sync 

**Use case:** You want full control and visibility over every sync decision.

**Settings:**
```
sync_reading_state = true
enable_auto_sync = false
enable_sync_from_kobo = true
enable_sync_to_kobo = true
sync_from_kobo_newer = PROMPT       -- Ask before pulling newer
sync_from_kobo_older = NEVER        -- Never regress progress
sync_to_kobo_newer = PROMPT         -- Ask before pushing newer
sync_to_kobo_older = NEVER          -- Never regress progress
```

## Automatic Sync (Both directions, prefer newer)

**Use case:** You read on both systems and want seamless synchronization.

**Settings:**
```
sync_reading_state = true
enable_auto_sync = true
enable_sync_from_kobo = true
enable_sync_to_kobo = true
sync_from_kobo_newer = SILENT       -- Auto-pull newer
sync_from_kobo_older = NEVER        -- Keep higher KOReader progress
sync_to_kobo_newer = SILENT         -- Auto-push newer
sync_to_kobo_older = NEVER          -- Keep higher Kobo progress
```

## KOReader Primary

**Use case:** You primarily read in KOReader and want Kobo to follow.

**Settings:**
```
sync_reading_state = true
enable_auto_sync = false
enable_sync_from_kobo = false       -- Don't pull from Kobo
enable_sync_to_kobo = true
sync_to_kobo_newer = SILENT         -- Auto-push newer to Kobo
sync_to_kobo_older = NEVER          -- Don't regress Kobo
```

## Kobo Primary

**Use case:** You primarily read in Kobo native reader and want KOReader to follow.

**Settings:**
```
sync_reading_state = true
enable_auto_sync = true
enable_sync_from_kobo = true
enable_sync_to_kobo = false         -- Don't push to Kobo
sync_from_kobo_newer = SILENT       -- Auto-pull newer from Kobo
sync_from_kobo_older = NEVER        -- Don't regress KOReader
```

## Manual Sync Only

**Use case:** You want complete control and prefer to trigger sync manually.

**Settings:**
```
sync_reading_state = true
enable_auto_sync = false
enable_sync_from_kobo = true
enable_sync_to_kobo = true
sync_from_kobo_newer = PROMPT       -- Always ask
sync_from_kobo_older = PROMPT       -- Always ask
sync_to_kobo_newer = PROMPT         -- Always ask
sync_to_kobo_older = PROMPT         -- Always ask
```
