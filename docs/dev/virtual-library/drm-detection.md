# DRM Detection

The virtual library needs to identify which books are encrypted with DRM to prevent users from
attempting to open books that KOReader cannot read. This is critical for providing a good user
experience and avoiding error messages when browsing the library.

## Why Content-Based Detection?

### Historical Approach: rights.xml

Earlier approaches to DRM detection relied on checking for the presence of a `rights.xml` file in
the EPUB/KEPUB archive. This file is part of Adobe's ADEPT DRM system and typically contains
metadata about the DRM protection.

**Problems with this approach:**

1. **False Positives**: Some DRM-free books may contain `rights.xml` files that are simply empty or
   contain non-restrictive metadata
2. **Incomplete**: Not all DRM systems use `rights.xml` - other protection schemes exist
3. **Unreliable**: The presence of the file doesn't guarantee the content is actually encrypted

### Current Approach: Content Examination

The plugin now examines the actual content files within the EPUB/KEPUB archive to determine if they
are readable. This provides a more reliable detection mechanism that works across different DRM
implementations.

---

References:

- https://github.com/OGKevin/kobo.koplugin/issues/119
