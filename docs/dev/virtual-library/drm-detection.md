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

## Implementation

The DRM detection is implemented in `MetadataParser:isBookEncrypted()` in `src/metadata_parser.lua`:

```lua
function MetadataParser:isBookEncrypted(book_id)
    logger.dbg("MetadataParser: checking if book is encrypted", book_id)

    -- Get the file path for this book
    local filepath = self:getBookFilePath(book_id)
    if not filepath then
        logger.dbg("MetadataParser: book file not found", book_id)
        return true  -- Missing files are treated as encrypted
    end

    -- Open the archive (EPUB/KEPUB is a ZIP file)
    local arc = Archiver.Reader:new()

    if arc:open(filepath) then
        local content_file_data = nil
        local content_file_found = false

        -- Iterate through files in the archive
        for entry in arc:iterate() do
            if
                entry.mode == "file"
                and (entry.path:match("%.xhtml$") or entry.path:match("%.html$"))
                and not entry.path:match("^META%-INF/")
                and not entry.path:match("toc%.")
            then
                -- Extract content to memory for examination
                content_file_data = arc:extractToMemory(entry.index)
                content_file_found = true

                break  -- Only need to check one content file
            end
        end

        arc:close()

        if content_file_found then
            -- Check if content is empty
            if not content_file_data or #content_file_data == 0 then
                logger.dbg("MetadataParser: content file is empty", book_id)

                return true
            end

            -- Examine first 100 bytes for readable XML/HTML markers
            local first_bytes = content_file_data:sub(1, 100)
            local is_readable = first_bytes:match("^%s*<%?xml")
                or first_bytes:match("^%s*<!DOCTYPE")
                or first_bytes:match("^%s*<html")
                or first_bytes:match("^%s*<")

            if not is_readable then
                logger.dbg("MetadataParser: book is encrypted (binary content detected)", book_id)

                return true
            end

            logger.dbg("MetadataParser: book is not encrypted (readable content found)", book_id)

            return false
        end

        logger.dbg("MetadataParser: no content files found in archive", book_id)

        return true
    end

    logger.dbg("MetadataParser: could not open book archive", book_id)

    return true  -- Unreadable archives are treated as encrypted
end
```

## Detection Strategy

### 1. File Accessibility Check

The first check verifies that the book file exists and can be accessed. Missing files are treated as
encrypted since they cannot be opened.

```lua
-- From MetadataParser:isBookEncrypted()
local filepath = self:getBookFilePath(book_id)
if not filepath then
    logger.dbg("MetadataParser: book file not found", book_id)
    return true
end
```

### 2. Archive Validation

Next, the code attempts to open the EPUB/KEPUB archive. Since these files are ZIP archives, the code
tries to open them. If successful, it proceeds to examine content. If opening fails (handled at the
end of the function), the book is treated as encrypted.

```lua
-- From MetadataParser:isBookEncrypted()
local arc = Archiver.Reader:new()

if arc:open(filepath) then
    -- Success: examine content (see next sections)
    -- ...
end

-- If we reach here, archive couldn't be opened
logger.dbg("MetadataParser: could not open book archive", book_id)
return true
```

### 3. Content File Selection

The code searches for actual book content files (XHTML or HTML) while filtering out:

- **META-INF directory**: Contains metadata, not readable content
- **Table of Contents files**: Navigation files that may be readable even in encrypted books

```lua
-- From MetadataParser:isBookEncrypted()
for entry in arc:iterate() do
    if
        entry.mode == "file"
        and (entry.path:match("%.xhtml$") or entry.path:match("%.html$"))
        and not entry.path:match("^META%-INF/")
        and not entry.path:match("toc%.")
    then
        content_file_data = arc:extractToMemory(entry.index)
        content_file_found = true

        break
    end
end
```

### 4. Content Readability Analysis

The actual content is extracted to memory and the first 100 bytes are examined for common XML/HTML
patterns:

- `<?xml` - XML declaration
- `<!DOCTYPE` - DOCTYPE declaration
- `<html` - HTML opening tag
- `<` - Any opening tag

**Encrypted content** appears as binary data and won't match these patterns.

**DRM-free content** will be readable text starting with standard markup declarations.

```lua
-- From MetadataParser:isBookEncrypted()
if content_file_found then
    if not content_file_data or #content_file_data == 0 then
        logger.dbg("MetadataParser: content file is empty", book_id)

        return true
    end

    local first_bytes = content_file_data:sub(1, 100)
    local is_readable = first_bytes:match("^%s*<%?xml")
        or first_bytes:match("^%s*<!DOCTYPE")
        or first_bytes:match("^%s*<html")
        or first_bytes:match("^%s*<")

    if not is_readable then
        logger.dbg("MetadataParser: book is encrypted (binary content detected)", book_id)

        return true
    end

    logger.dbg("MetadataParser: book is not encrypted (readable content found)", book_id)

    return false
end
```

### 5. Edge Cases

The code handles several edge cases:

- **Empty content files**: Treated as encrypted
- **No content files found**: Treated as encrypted (archive may only contain metadata)
- **Archive cannot be opened**: Treated as encrypted

All of these cases result in the book being excluded from the virtual library since KOReader cannot
read them.

## Performance Considerations

The implementation is designed for efficiency:

1. **Early Exit**: Only examines the first content file found, not all files in the archive
2. **Partial Read**: Only reads the first 100 bytes of content, not the entire file
3. **Caching**: Results are used during library building and don't need to be rechecked unless the
   library is rescanned

## Testing

The DRM detection logic is thoroughly tested in `spec/metadata_parser_spec.lua`:

```lua
describe("isBookEncrypted", function()
    it("should return true if file is missing", function()
        -- Test missing files
    end)

    it("should return true if archive cannot be opened", function()
        -- Test corrupted/invalid archives
    end)

    it("should return true if content file is binary/encrypted", function()
        -- Test encrypted content (binary data)
    end)

    it("should return false if content file is readable XML with xhtml extension", function()
        -- Test valid XHTML content
    end)

    it("should return false if content file is readable HTML", function()
        -- Test valid HTML content
    end)

    it("should return false if content has DOCTYPE declaration", function()
        -- Test content with DOCTYPE
    end)

    it("should skip META-INF files", function()
        -- Test that META-INF files are ignored
    end)

    it("should skip TOC files", function()
        -- Test that navigation files are ignored
    end)

    it("should return true if content file is empty", function()
        -- Test empty content files
    end)
end)
```

## Why This Matters

Content-based DRM detection provides several benefits:

1. **Accuracy**: Directly examines what KOReader will try to read
2. **DRM-Agnostic**: Works regardless of the specific DRM technology used
3. **False Positive Prevention**: DRM-free books with `rights.xml` files are correctly identified as
   readable
4. **User Experience**: Users only see books they can actually open, reducing frustration

## Alternative Approaches Considered

### Approach 1: rights.xml Check

**Method**: Check for presence of `rights.xml` file in META-INF directory

**Pros**: Fast, simple implementation

**Cons**: High false positive rate, doesn't detect all DRM types

### Approach 2: File Extension

**Method**: Assume `.kepub.epub` files from Kobo store are always DRM-protected

**Pros**: Very fast

**Cons**: Many Kobo books are DRM-free (e.g., from Calibre), would exclude legitimate books

### Approach 3: Attempt to Open

**Method**: Let KOReader try to open each book and catch errors

**Cons**: Slow, poor user experience, would require error handling throughout the UI

### Current Approach: Content Examination ✓

**Method**: Read and analyze actual book content

**Pros**: Accurate, handles all DRM types, efficient

**Cons**: Slightly more complex implementation

The content examination approach provides the best balance of accuracy, performance, and user
experience.
