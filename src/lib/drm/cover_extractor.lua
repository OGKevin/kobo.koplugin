--- Kobo DRM Cover Extractor
--- Extracts cover images from encrypted EPUB books without full decryption.
---
--- This module:
--- 1. Decrypts only the OPF file to find cover metadata
--- 2. Decrypts only the cover image file
--- 3. Caches the extracted cover for reuse
---
--- @module lib.drm.cover_extractor

local Archiver = require("ffi/archiver")
local FileDecryptor = require("src/lib/drm/file_decryptor")
local logger = require("logger")

local CoverExtractor = {}

---
--- Parse OPF content to find cover image path.
--- @param opf_content string: Decrypted OPF XML content
--- @return string|nil: Cover image path within archive (e.g., "OEBPS/images/cover.jpg")
local function parseCoverPathFromOPF(opf_content)
    if not opf_content then
        logger.dbg("CoverExtractor: OPF content is nil")

        return nil
    end

    -- Method 1: Look for <meta name="cover" content="cover-id"/>
    local cover_id = opf_content:match('<meta%s+name="cover"%s+content="([^"]+)"')
    if not cover_id then
        cover_id = opf_content:match('<meta%s+content="([^"]+)"%s+name="cover"')
    end

    if cover_id then
        logger.dbg("CoverExtractor: Found cover ID:", cover_id)
        local cover_href =
            opf_content:match('<item%s+[^>]*id="' .. cover_id:gsub("%-", "%%-") .. '"[^>]*href="([^"]+)"')
        if not cover_href then
            cover_href = opf_content:match('<item%s+[^>]*href="([^"]+)"[^>]*id="' .. cover_id:gsub("%-", "%%-") .. '"')
        end

        if cover_href then
            logger.dbg("CoverExtractor: Found cover href:", cover_href)

            return cover_href
        end
    end

    -- Method 2: Look for properties="cover-image" in manifest
    local cover_href = opf_content:match('<item%s+[^>]*properties="cover%-image"[^>]*href="([^"]+)"')
    if not cover_href then
        cover_href = opf_content:match('<item%s+[^>]*href="([^"]+)"[^>]*properties="cover%-image"')
    end

    if cover_href then
        logger.dbg("CoverExtractor: Found cover via properties:", cover_href)

        return cover_href
    end

    logger.dbg("CoverExtractor: No cover found in OPF")

    return nil
end

---
--- Find OPF file path from container.xml or by scanning archive.
--- @param arc table: Archiver.Reader instance
--- @return string|nil: OPF file path
--- @return number|nil: OPF file index in archive
local function findOPFPath(arc)
    for entry in arc:iterate() do
        if entry.path == "META-INF/container.xml" then
            local container_content = arc:extractToMemory(entry.index)
            if container_content then
                local opf_path = container_content:match('full%-path="([^"]+)"')
                if opf_path then
                    logger.dbg("CoverExtractor: OPF path from container:", opf_path)
                    for entry2 in arc:iterate() do
                        if entry2.path == opf_path then
                            return opf_path, entry2.index
                        end
                    end
                end
            end
        end
    end

    for entry in arc:iterate() do
        if entry.path:match("%.opf$") then
            logger.dbg("CoverExtractor: Found OPF by extension:", entry.path)

            return entry.path, entry.index
        end
    end

    logger.warn("CoverExtractor: Could not find OPF file")
    return nil, nil
end

---
--- Resolve relative cover path to absolute path within archive.
--- @param opf_path string: Path to OPF file (e.g., "OEBPS/content.opf")
--- @param cover_href string: Relative cover path from OPF (e.g., "images/cover.jpg")
--- @return string: Absolute path within archive
local function resolveCoverPath(opf_path, cover_href)
    -- Remove any URL encoding or anchor fragments
    cover_href = cover_href:gsub("#.*$", ""):gsub("%%20", " ")

    -- If cover_href is already absolute (doesn't contain directory part of OPF)
    if not cover_href:match("^%.%.") and not cover_href:match("^%./") then
        -- Check if it's relative to OPF directory
        local opf_dir = opf_path:match("^(.+)/[^/]+$") or ""
        if opf_dir ~= "" then
            return opf_dir .. "/" .. cover_href
        end
        return cover_href
    end

    -- Handle relative paths (../ or ./)
    local opf_dir = opf_path:match("^(.+)/[^/]+$") or ""
    local parts = {}
    for part in opf_dir:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    for part in cover_href:gmatch("[^/]+") do
        if part == ".." then
            table.remove(parts)
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end

    return table.concat(parts, "/")
end

---
--- Extract cover image from encrypted EPUB.
--- Reads the unencrypted OPF file, finds the cover path, and decrypts only that file.
--- @param book_id string: Book UUID
--- @param input_path string: Path to encrypted EPUB file
--- @param output_path string: Where to save extracted cover
--- @param kobo_dir string: Path to .kobo directory
--- @param db_path string: Path to KoboReader.sqlite
--- @param kobo_kdrm table: KoboKDRM instance for getting decryption keys
--- @return boolean: True if successful
--- @return string|nil: Error message if failed
function CoverExtractor:extractCover(book_id, input_path, output_path, kobo_dir, db_path, kobo_kdrm)
    logger.dbg("CoverExtractor: Extracting cover for book:", book_id)
    logger.dbg("CoverExtractor: Input:", input_path)
    logger.dbg("CoverExtractor: Output:", output_path)

    local arc = Archiver.Reader:new()
    if not arc:open(input_path) then
        return false, "Failed to open archive"
    end

    local opf_path, opf_index = findOPFPath(arc)
    if not opf_path then
        arc:close()

        return false, "OPF file not found"
    end

    local opf_content = arc:extractToMemory(opf_index)
    if not opf_content then
        arc:close()

        return false, "Failed to extract OPF file"
    end

    logger.dbg("CoverExtractor: OPF file is unencrypted, size:", #opf_content)

    local cover_href = parseCoverPathFromOPF(opf_content)
    if not cover_href then
        arc:close()

        return false, "Cover not specified in OPF"
    end

    local cover_path = resolveCoverPath(opf_path, cover_href)
    logger.dbg("CoverExtractor: Resolved cover path:", cover_path)

    local cover_key = kobo_kdrm:getDecryptedKey(book_id, cover_path, kobo_dir, db_path)
    if not cover_key then
        arc:close()

        return false, "Failed to get decryption key for cover file"
    end

    for entry in arc:iterate() do
        if entry.path == cover_path then
            local cover_encrypted = arc:extractToMemory(entry.index)
            if not cover_encrypted then
                arc:close()

                return false, "Failed to extract cover file"
            end

            logger.dbg("CoverExtractor: Decrypting cover image:", cover_path)
            local cover_content = FileDecryptor:decryptFileContent(cover_encrypted, cover_key)

            if not cover_content then
                arc:close()

                return false, "Failed to decrypt cover file"
            end

            local output_file = io.open(output_path, "wb")
            if not output_file then
                arc:close()

                return false, "Failed to create output file"
            end

            output_file:write(cover_content)
            output_file:close()

            logger.info("CoverExtractor: Successfully extracted cover to:", output_path)
            arc:close()

            return true, nil
        end
    end

    arc:close()

    return false, "Cover file not found in archive"
end

return CoverExtractor
