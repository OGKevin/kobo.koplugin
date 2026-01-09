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

## Step-by-Step Workflow

### Step 1: Purchase a Book

1. **Via Kobo Website**:
   - Visit the Kobo Store at [kobo.com](https://www.kobo.com)
   - Browse or search for the book you want
   - Click "Buy" and complete the purchase
   - The book is added to your Kobo library

2. **Via Kobo Device** (Nickel):
   - Open the native Kobo reader (Nickel) on your device
   - Tap "Store" in the bottom menu
   - Browse or search for a book
   - Tap to purchase and confirm

### Step 2: Download to Device

1. **Switch to Nickel** (if not already there):
   - Close KOReader
   - The device should automatically switch to Nickel
   - If not, restart your device

2. **Download the Book**:
   - In Nickel, tap "Library" in the bottom menu
   - Find your newly purchased book (it may show a download icon)
   - Tap the book to download it to your device
   - Wait for the download to complete (watch for the download progress indicator)

3. **Verify Download**:
   - Once downloaded, the book should be available offline
   - You'll see the book cover instead of a download icon

### Step 3: Configure DRM Settings (One-Time)

If you haven't already enabled DRM decryption:

1. **Switch to KOReader**:
   - Tap the home button or restart your device
   - KOReader should launch automatically (if set as default reader)

2. **Enable DRM Decryption**:
   - Tap the top of the screen to open the menu
   - Navigate to **Tools** → **Kobo Library** → **DRM Settings**
   - Tap **Enable DRM decryption** to turn it on
   - The virtual library will refresh automatically

3. **Optional - Configure Cache Directory**:
   - In the same DRM Settings menu, tap **Cache directory**
   - Choose where decrypted books should be stored (default is usually fine)
   - Confirm your selection

### Step 4: Open and Read

1. **Navigate to Kobo Library**:
   - In KOReader, go to the file browser
   - Locate and tap the **Kobo Library** folder
   - Your purchased books will be listed here

2. **Open Your Book**:
   - Find the book you just purchased
   - Tap to open it
   - **First Open**: The plugin will decrypt the book automatically (may take 5-30 seconds depending
     on book size)
   - A progress indicator will show during decryption
   - Once decrypted, the book opens normally

3. **Start Reading**:
   - The book opens just like any other book in KOReader
   - All KOReader features work normally (highlights, bookmarks, dictionary, etc.)
   - Your reading progress is tracked and can be synced with Kobo Nickel if sync is enabled

### Step 5: Subsequent Opens

The next time you open the same book:

- The cached decrypted version is used
- Opening is instant (no decryption wait)
- Works offline without any delays

## Tips and Best Practices

### Managing Storage

- Decrypted books use additional storage space
- Use **Tools** → **Kobo Library** → **DRM Settings** → **Clear decrypted book cache** to free up
  space when needed
- Consider moving the cache to an SD card if your device supports it

### Book Organization

- Books appear in the virtual library with their original titles and metadata
- You can use KOReader's collections feature to organize your books
- Reading progress is saved in KOReader's metadata, not in the decrypted files

### Sync Integration

If you have reading state sync enabled:

- Your reading progress in KOReader can be synced back to Nickel
- You can switch between KOReader and Nickel seamlessly
- See [Reading State Sync](../features/reading-state-sync.md) for more details

## Troubleshooting

### Book Doesn't Appear in Virtual Library

1. Verify the book was downloaded in Nickel (check that it's available offline)
2. In KOReader, go to **Tools** → **Kobo Library** → **Refresh library**
3. Check that the virtual library is enabled in settings

### Decryption Fails

1. Ensure DRM decryption is enabled in **Tools** → **Kobo Library** → **DRM Settings**
2. Verify the book was purchased with your Kobo account
3. Ensure the book was downloaded through Nickel (not sideloaded)
4. Try restarting KOReader
5. Check the device serial number is correctly read from `/mnt/onboard/.kobo/version`

### Book Opens But Pages Are Blank

1. Clear the decrypted book cache
2. Try opening the book again (it will re-decrypt)
3. If the problem persists, the book file may be corrupted - try re-downloading in Nickel

### Running Out of Space

1. Use **Clear decrypted book cache** to remove cached files
2. Move the cache directory to an SD card (if supported)
3. Remove books you've finished from the cache
4. Delete books you no longer need from your Kobo library in Nickel

## Advanced Topics

### Cache Management

The cache directory stores decrypted versions of your books. Key points:

- Default location: `/mnt/onboard/.cache/koreader/drm`
- Cached files have the same filename as the book ID
- Clearing the cache only removes decrypted copies (original encrypted files remain)
- Changing cache location doesn't move existing cached files

### Security Considerations

- Decrypted books are stored unencrypted in the cache directory
- Anyone with access to your device can read cached books
- Consider using a device lock/PIN for security
- Clearing the cache removes decrypted copies

### Multiple Kobo Accounts

If you switch Kobo accounts:

1. Decryption keys are tied to your device and account
2. Books from the previous account may not decrypt with the new account
3. Clear the cache when switching accounts to avoid confusion
4. Re-download books from the new account

## Related Documentation

- [Virtual Library Feature](../features/virtual-library.md) - Overview of the virtual library
- [DRM Settings](../settings/drm-settings/index.md) - Detailed DRM configuration options
- [Reading State Sync](../features/reading-state-sync.md) - Syncing progress between KOReader and
  Nickel
