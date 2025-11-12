# Core Settings

All sync settings are stored in KOReader's configuration and persist across restarts. Here are the
core settings:

## Main Controls

### `sync_reading_state` (Default: `false`)

Global enable/disable for all sync functionality. When disabled, no synchronization occurs between
KOReader and Kobo.

**Menu:** Kobo Library → Sync reading state with Kobo

### `enable_auto_sync` (Default: `false`)

Auto-sync reading progress when opening the virtual library. The sync only happens once per KOReader
startup. Books are always displayed in the virtual library regardless of this setting.

**Menu:** Kobo Library → Enable automatic sync on virtual library

## Direction Controls

### `enable_sync_from_kobo` (Default: `false`)

Allow pulling progress from Kobo to KOReader (FROM Kobo sync).

**Menu:** Kobo Library → Sync behavior → Enable sync FROM Kobo TO KOReader

### `enable_sync_to_kobo` (Default: `true`)

Allow pushing progress from KOReader to Kobo (TO Kobo sync).

**Menu:** Kobo Library → Sync behavior → Enable sync FROM KOReader TO Kobo

## Behavior Controls

Granular settings for different sync scenarios with three options each:

- **`PROMPT`**: Ask user before syncing
- **`SILENT`**: Sync automatically without confirmation
- **`NEVER`**: Skip sync in this scenario

See [Sync Direction Settings](../sync-direction-settings.md) for details on the four behavior
settings.
