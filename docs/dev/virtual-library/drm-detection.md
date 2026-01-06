# DRM Detection

The virtual library needs to identify which books are encrypted with DRM to prevent users from
attempting to open books that KOReader cannot read. This is critical for providing a good user
experience and avoiding error messages when browsing the library.

## Database-Only Detection

The plugin uses a simple and fast database lookup to determine if a book is DRM-encrypted.

### How It Works

Query the `content_keys` table in the native Kobo database:

```sql
SELECT 1 FROM content_keys WHERE volumeId = ? LIMIT 1
```

**Detection logic:**

- **Keys exist** → Book is KDRM-encrypted (Kobo-purchased)
- **No keys** → Book is not encrypted (sideloaded DRM-free)

### Why This Works

The `content_keys` table is populated by Kobo for **all KDRM-protected books on disk**. This table
stores the encrypted content keys needed to decrypt individual files within the EPUB/KEPUB archive.

**Key characteristics:**

1. **Present for all encrypted books**: Kobo populates this table when syncing or downloading books
2. **Absent for sideloaded books**: Books transferred via USB don't have KDRM protection
3. **Indexed query**: Fast O(1) lookup using the covering index on `volumeId`
4. **Authoritative**: This is the same table Kobo uses internally for decryption

## Historical Approaches (Deprecated)

### Content Examination

Earlier versions examined actual file content by:

1. Opening the ZIP archive
2. Finding XHTML/HTML files
3. Extracting to memory
4. Checking for readable XML/HTML markers

**Why it was removed:**

- Significantly slower (requires file I/O + decompression)
- Unnecessary complexity
- Database lookup is both faster and more reliable

### rights.xml Check

Even earlier approaches checked for a `rights.xml` file in the archive.

**Why it was removed:**

1. **False positives**: DRM-free books may contain empty `rights.xml` files
2. **Incomplete**: Doesn't reliably indicate KDRM encryption
3. **Unreliable**: File presence doesn't guarantee content is encrypted

## Implementation

See `src/metadata_parser.lua:isBookEncrypted()` for the implementation. The method performs a single
database query and returns the result.

---

References:

- [Issue #119: DRM detection improvements](https://github.com/OGKevin/kobo.koplugin/issues/119)
- [Issue #73: DRM removal investigation](https://github.com/OGKevin/kobo.koplugin/issues/73)
- [DRM Removal Investigation](../investigations/drm-removal.md)
- [Database Schema: content_keys table](../database/kobo/01-schema.md)
