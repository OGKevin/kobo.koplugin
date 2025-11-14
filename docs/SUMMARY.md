# Summary

# User Guide

- [Introduction](./introduction.md)
- [Installation](./installation.md)
- [Getting Started](./getting-started.md)
- [Features](./features.md)
  - [Virtual Library](./features/virtual-library.md)
  - [Reading State Sync](./features/reading-state-sync.md)
- [Settings](./settings.md)
  - [Sync Settings Overview](./settings/sync-settings-overview/index.md)
    - [Core Settings](./settings/sync-settings-overview/core.md)
    - [Settings Menu Navigation](./settings/sync-settings-overview/menu.md)
    - [Manual Sync](./settings/sync-settings-overview/manual.md)
    - [Sync Decision Dialog](./settings/sync-settings-overview/dialog.md)
  - [Sync Direction Settings](./settings/sync-direction-settings.md)
  - [Sync Configuration Examples](./settings/sync-configuration-examples.md)
- [Usage Scenarios](./scenarios/index.md)
  - [Komga / Calibre Web Integration](./scenarios/komga-calibre.md)
    - [Workflows](./scenarios/komga-calibre/workflows.md)
      - [Reading a New Book](./scenarios/komga-calibre/new-book.md)
      - [Continuing in Kobo Native](./scenarios/komga-calibre/kobo-native.md)
      - [Return to KOReader](./scenarios/komga-calibre/return-koreader.md)
    - [Sync Flow Diagram](./scenarios/komga-calibre/sync-flow.md)

---

# Developer Guide

- [Architecture](./dev/architecture/00-overview.md)
  - [High-Level Architecture](./dev/architecture/01-high-level.md)
- [Database & Data Storage](./dev/database/00-overview.md)
  - [Kobo Database](./dev/database/kobo/index.md)
    - [Schema](./dev/database/kobo/01-schema.md)
    - [Progress Storage](./dev/database/kobo/02-progress-storage.md)
    - [Queries](./dev/database/kobo/03-queries.md)
  - [KOReader Data](./dev/database/koreader/index.md)
    - [DocSettings](./dev/database/koreader/01-docsettings.md)
    - [ReadHistory](./dev/database/koreader/02-readhistory.md)
    - [Data Flow](./dev/database/koreader/03-data-flow.md)
  - [Sync Decision Logic](./dev/database/03-sync-decision-logic.md)

---

# Techincal Investigations

- [Investigations](./dev/investigations/index.md)
  - [Bluetooth Control](./dev/investigations/bluetooth/00-overview.md)
    - [Architecture](./dev/investigations/bluetooth/01-architecture.md)
    - [Initialization](./dev/investigations/bluetooth/02-initialization.md)
    - [Operations](./dev/investigations/bluetooth/03-operations.md)
    - [Shutdown](./dev/investigations/bluetooth/04-shutdown.md)
    - [Known Issues](./dev/investigations/bluetooth/05-known-issues.md)
