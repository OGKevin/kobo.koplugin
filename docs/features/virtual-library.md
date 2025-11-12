# Virtual Library

The Virtual Library is the core feature that creates a seamless bridge between your Kobo's kepub
collection and KOReader's file system.

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

## Troubleshooting Virtual Library

### Missing Books

1. **DRM protection**: Encrypted books cannot be accessed
