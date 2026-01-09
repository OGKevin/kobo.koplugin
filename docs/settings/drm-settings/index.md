# DRM Settings

The DRM (Digital Rights Management) settings allow you to decrypt and access legitimately purchased
books from the Kobo Store that have been downloaded via the native Kobo reader (Nickel) to your
device.

**Important Notice:** _This feature is intended to decrypt and open books that you have legally
purchased from Kobo's store and downloaded to your Kobo device. It is designed to allow you to read
your own books using KOReader while respecting the rights of content creators and publishers._

## Settings Overview

### Enable DRM Decryption

- **Location:** Kobo Library → DRM Settings → Enable DRM decryption
- **Default:** Disabled

When enabled, the plugin will automatically decrypt encrypted Kobo books when you try to open them
from the virtual library. Decrypted books are cached to avoid re-decrypting them on each access,
providing a seamless reading experience.

**How it works:**

1. When you open an encrypted book, the plugin automatically decrypts it in the background
2. The decrypted version is stored in the cache directory
3. On subsequent opens, the cached version is used for instant access
4. You can read your encrypted books just like any other book in your library

### Cache Directory

- **Location:** Kobo Library → DRM Settings → Cache directory
- **Default:** `/tmp/kobo.koplugin.cache/`

Select the directory where decrypted books will be cached. This is where the plugin stores the
decrypted copies of your encrypted books.

**Important:** When you change the cache directory location, you become responsible for managing and
cleaning up any dangling files. Since the default path is in a temporary directory, the system will
automatically clean it up as needed.

### Clear Decrypted Book Cache

- **Location:** Kobo Library → DRM Settings → Clear decrypted book cache

Removes all cached decrypted books from the cache directory. This frees up storage space but means
that encrypted books will need to be re-decrypted the next time you open them.
