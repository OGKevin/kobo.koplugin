# Manual Sync

You can trigger a manual sync at any time via the menu: **Kobo Library → Sync reading state now**

This respects all the sync behavior settings configured in [Sync Direction Settings](../sync-direction-settings.md).

## Manual Sync Process

1. Open the file browser in KOReader
2. Open the menu (top-left corner)
3. Select "Kobo Library" → "Sync reading state now"
4. Wait for sync to complete
5. See confirmation when done

## Sync Behavior with Manual Sync

Manual sync respects all configured settings:
- **sync_from_kobo_newer** and **sync_from_kobo_older**: Control pull behavior
- **sync_to_kobo_newer** and **sync_to_kobo_older**: Control push behavior
- **PROMPT** settings will show dialogs for each decision
- **SILENT** settings will sync automatically
- **NEVER** settings will skip those scenarios
