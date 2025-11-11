# Komga / Calibre Web Integration

## Goal

Streamline your workflow by syncing books through Kobo's native system. Read Komga or Calibre Web synced books directly in KOReader while maintaining seamless reading progress synchronization.

## Use Case

You use Komga or Calibre Web to manage your digital library and sync books to your Kobo device. You want to:
- Keep Kobo as your single source of truth for books
- Enjoy KOReader's superior reading features and customization
- Have reading progress automatically sync between Kobo and KOReader
- Avoid managing duplicate book copies or complex sync setups
- Kobo syncs progress back to Komga/Calibre Web, completing the loop

## Benefits

### Simplified Setup
- One book source (Komga/Calibre Web → Kobo)
- No need to manually manage books in multiple locations
- KOReader automatically sees all books from your sync service
- Reading progress syncs back to Komga/Calibre Web through Kobo's sync mechanism

### Best of Both Worlds
- Use KOReader's superior reader
- Leverage Komga/Calibre Web's library management
- Use Kobo's native sync capabilities

## Setup

### Prerequisites
- Komga or Calibre Web configured and syncing books to Kobo
- Kobo Plugin installed and enabled in KOReader
- Sync enabled in plugin settings

### Important Limitation

When syncing reading progress **to Kobo**, the position is rounded to chapter boundaries. This means Kobo's native reader will open at the nearest chapter rather than the exact position where you stopped in KOReader. However, when KOReader receives progress from Kobo, it opens at the exact percentage, providing fine-grained positioning.

### Configuration

Use these recommended settings:

```
✅ Sync reading state with Kobo: ON
✅ Enable automatic sync on virtual library: ON
✅ Enable sync FROM Kobo TO KOReader: ON
✅ Enable sync FROM KOReader TO Kobo: ON

Sync from Kobo (newer): SILENT
Sync to Kobo (newer): SILENT
Sync from Kobo (older): NEVER
Sync to Kobo (older): NEVER
```

These settings mean:
- Sync is enabled globally
- Auto-sync is enabled (syncs automatically when accessing the virtual library)
- Progress always syncs when you close books or access the library
- Never sync older/less complete progress (prevents losing progress)

## Workflows

Detailed step-by-step workflows for common reading scenarios:

- **[Reading a New Book](./komga-calibre/workflows.md)**: Setting up and opening a book for the first time
- **[Continuing in Kobo Native](./komga-calibre/workflows.md)**: Switching between KOReader and Kobo's native reader
- **[Return to KOReader](./komga-calibre/workflows.md)**: Coming back to KOReader after reading in Kobo

See the [Workflows](./komga-calibre/workflows.md) page for detailed instructions.

## Sync Flow Diagram

The [Sync Flow Diagram](./komga-calibre/sync-flow.md) visualizes how books and reading progress move through the system.

## Next Steps

- Review [Sync Settings](../settings/sync-settings-overview/index.md) for advanced configuration
- Check [Troubleshooting](../troubleshooting.md) for common issues
- See [Settings Menu Navigation](../settings/sync-settings-overview/menu.md) for how to access settings
