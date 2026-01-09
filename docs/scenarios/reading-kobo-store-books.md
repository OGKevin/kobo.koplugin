# Reading Kobo Store Books

This scenario walks through purchasing and reading books from the Kobo Store using KOReader with DRM
decryption support.

## Overview

The Kobo Plugin enables you to read books purchased from the Kobo Store directly in KOReader. When
you enable DRM decryption, encrypted books are automatically decrypted when opened, providing a
seamless reading experience.

## Prerequisites

- A Kobo device with KOReader installed
- An active Kobo account
- The kobo.koplugin installed and configured
- Internet connection for purchasing and downloading books

## Steps

1. Purchase a book from the Kobo Store via their website or the Kobo device itself.

2. Switch to Nickel, tap "Library" in the bottom menu, and download your newly purchased book.

3. Switch to KOReader and enable DRM decryption: **Kobo Library** → **DRM Settings** → **Enable DRM
   decryption**. (One-time setup)

4. In KOReader, navigate to the **Kobo Library** folder in the file browser.

5. Open your purchased book. The plugin will decrypt it automatically (5-30 seconds depending on
   book size).

6. Start reading

## Related Documentation

- [Virtual Library Feature](../features/virtual-library.md) - Overview of the virtual library
- [DRM Settings](../settings/drm-settings/index.md) - Detailed DRM configuration options
- [Reading State Sync](../features/reading-state-sync.md) - Syncing progress between KOReader and
  Nickel
