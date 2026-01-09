# DRM Settings

The DRM (Digital Rights Management) settings allow you to decrypt and access legitimately purchased
books from the Kobo Store that have been downloaded via the native Kobo reader (Nickel) to your
device.

**Important Notice:** This feature is intended to decrypt and open books that you have legally
purchased from Kobo's store and downloaded to your Kobo device. It is designed to allow you to read
your own books using KOReader while respecting the rights of content creators and publishers.

## Settings Overview

### Enable DRM Decryption

- **Location:** Tools → Kobo Library → DRM Settings → Enable DRM decryption
- **Default:** Disabled

When enabled, the plugin will automatically decrypt encrypted Kobo books (KEPUB/EPUB files) when you
try to open them from the virtual library. Decrypted books are cached to avoid re-decrypting them on
each access, providing a seamless reading experience.

**How it works:**

1. When you open an encrypted book, the plugin automatically decrypts it in the background
2. The decrypted version is stored in the cache directory
3. On subsequent opens, the cached version is used for instant access
4. You can read your encrypted books just like any other book in your library

### Cache Directory

- **Location:** Tools → Kobo Library → DRM Settings → Cache directory
- **Default:** `/mnt/onboard/.cache/koreader/drm`

Select the directory where decrypted books will be cached. This is where the plugin stores the
decrypted copies of your encrypted books.

**Important:** When you change the cache directory location, you become responsible for managing and
cleaning up any files left in the old cache location. The plugin will not automatically clean up the
previous cache directory. You should manually delete the old cache directory if you want to reclaim
that storage space.

**Tips:**

- Choose a location with sufficient storage space for your decrypted books
- The default location is usually suitable for most users
- If you move the cache to an SD card, ensure the card is always inserted when reading encrypted
  books

### Clear Decrypted Book Cache

- **Location:** Tools → Kobo Library → DRM Settings → Clear decrypted book cache

Removes all cached decrypted books from the cache directory. This frees up storage space but means
that encrypted books will need to be re-decrypted the next time you open them.

**When to use this:**

- To free up storage space when you're running low on device storage
- After removing books from your Kobo library to clean up orphaned cache files
- If you suspect cached files are corrupted

**What happens:**

1. Shows the number of cached books and total storage used
2. Confirms deletion before proceeding
3. Removes all decrypted book files from the cache directory
4. Next time you open an encrypted book, it will be decrypted again

## Usage Scenario: Reading Kobo Store Books

Here's a typical workflow for reading books purchased from the Kobo Store:

### Step 1: Buy Book from Kobo Store

1. Purchase a book from the Kobo Store using your Kobo account (via web, mobile app, or device)
2. The book will be added to your library

### Step 2: Download to Your Device

1. On your Kobo device, open the native Kobo reader (Nickel)
2. Navigate to your library and find the purchased book
3. Tap to download the book to your device
4. Wait for the download to complete

### Step 3: Enable DRM Decryption (One-Time Setup)

1. Switch to KOReader
2. Tap the top of the screen to open the menu
3. Navigate to **Tools** → **Kobo Library** → **DRM Settings**
4. Enable **Enable DRM decryption**
5. Optionally configure the cache directory if you want to use a different location

### Step 4: Open and Read from Virtual Library

1. In KOReader, navigate to the file browser
2. Find and open the **Kobo Library** folder
3. Your purchased book will appear in the list
4. Tap to open the book
5. The first time you open it, the plugin will decrypt it automatically (may take a few seconds)
6. Start reading!

### Subsequent Reads

Once a book has been decrypted and cached:

- Opening the book is instant (no waiting for decryption)
- The cached version is automatically used
- You can read offline without any decryption delays

## Troubleshooting

### Book Won't Decrypt

- Ensure DRM decryption is enabled in settings
- Verify the book was downloaded through Nickel (not sideloaded)
- Check that the book is from your Kobo account
- Try restarting KOReader

### Running Out of Storage

- Use "Clear decrypted book cache" to free up space
- Consider moving the cache directory to an SD card if your device supports it
- Remove books you've finished reading from the cache

### Cache Files After Changing Directory

- Manually delete the old cache directory to reclaim storage space
- The plugin does not automatically clean up old cache locations
