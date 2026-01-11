# Virtual Library

The Virtual Library is the core feature that creates a seamless bridge between your Kobo's kepub
collection and KOReader's file system.

## Enabling and Disabling

The virtual library feature can be toggled on or off through the plugin settings:

1. Open the KOReader menu (tap the top of the screen)
2. Navigate to **Tools** → **Kobo Library**
3. Toggle **Enable virtual library**
4. Restart KOReader when prompted

**Note:** A restart is required for the change to take effect. When disabled, the virtual library
will not be accessible, and all sync-related menu items will be hidden.

The virtual library is **enabled by default** when you first install the plugin.

## How It Works

The plugin creates a virtual filesystem layer that presents your Kobo books as if they were regular
files in KOReader's file browser. This virtual representation is built by:

1. **Reading Kobo's database** (`KoboReader.sqlite`) for book metadata
2. **Creating virtual paths** in the format `KOBO_VIRTUAL://BOOKID/filename`
3. **Mapping virtual paths** to actual kepub file locations
4. **Providing file system operations** for seamless KOReader integration

## Virtual Path Structure

```
Kobo Library/
├── Harry Potter and the Philosopher's Stone.kepub.epub
├── Harry Potter and the Chamber of Secrets.kepub.epub
├── 1984.kepub.epub
├── Animal Farm.kepub.epub
└── [More books...]
```

### Path Translation

| Virtual Path                            | Actual Path                       |
| --------------------------------------- | --------------------------------- |
| `KOBO_VIRTUAL://ABC123/book.kepub.epub` | `/mnt/onboard/.kobo/kepub/ABC123` |

## Library Organization

### Flat Structure

Books are presented in a single flat directory without subfolders:

- **Book files** appear with their titles from Kobo's database
- **File extensions** are preserved (`.kepub.epub`)
- **No subdirectories**: All books in one folder for simple browsing

### Metadata Integration

Each virtual book entry includes:

- **Title**: From Kobo's database or filename fallback
- **Author**: Primary author from book metadata
- **Cover**: Extracted from Kobo's cover cache
- **Series**: Extracted from Kobo's database

## Document Metadata Location

For kepub books opened through the virtual library, KOReader stores metadata in a specific location
to prevent data loss:

- **Automatic Override**: When you open a kepub book, the plugin automatically overrides the "doc"
  metadata location setting to use "dir" location instead
- **Why**: Kobo's system may delete files stored alongside kepub files in the kepub directory,
  causing potential data loss
- **Hash Location**: The "hash" metadata location setting is respected and not overridden
- **Dir Location**: The "dir" metadata location setting works normally

**What this means for you**: If you have KOReader's "Document metadata folder" setting set to
"Document folder", kepub books will automatically store their metadata in the "docsettings" folder
instead, protecting your reading progress and bookmarks from being accidentally deleted by Kobo.

## Encrypted Books Support

The plugin supports decrypting and reading books purchased from the Kobo Store that are protected
with DRM. When DRM decryption is enabled in settings, encrypted books are automatically decrypted
when you open them, and the decrypted versions are cached for quick access on subsequent reads.

**Key Features:**

- **Automatic Decryption**: Opens encrypted KEPUB/EPUB books seamlessly when DRM decryption is
  enabled
- **Smart Caching**: Decrypted books are cached to avoid re-decryption on each access
- **Legitimate Use**: Designed for reading books you legally purchased from the Kobo Store
- **Works offline**: Decryption occurs locally on your device without needing an internet connection

**How to Enable:**

1. Navigate to **Kobo Library** → **DRM Settings**
2. Enable **Enable DRM decryption**
3. Encrypted books in your library will now be accessible

See the [DRM Settings](../settings/drm-settings/index.md) documentation for detailed configuration
options and usage scenarios.
