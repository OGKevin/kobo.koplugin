-- Kobo KDRM Main Orchestrator
--- Coordinates the complete book decryption process.
---
--- This module ties together:
--- 1. Reading device serial and user credentials
--- 2. Deriving user keys
--- 3. Decrypting content keys and files
--- 4. Creating decrypted EPUB/KEPUB files

local Archiver = require("ffi/archiver")
local FileDecryptor = require("src/lib/drm/file_decryptor")
local KeyDerivation = require("src/lib/drm/key_derivation")
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local KoboKDRM = {}

---
--- Read device serial from version file.
--- @param kobo_dir string: Path to .kobo directory
--- @return string|nil: Device serial, or nil on failure
function KoboKDRM:getDeviceSerial(kobo_dir)
    local version_path = kobo_dir .. "/version"

    local file = io.open(version_path, "r")
    if not file then
        logger.warn("KoboKDRM: Could not open version file:", version_path)

        return nil
    end

    local content = file:read("*all")
    file:close()

    -- Format: serial,version,version,version,version,platform_id
    local serial = content:match("^([^,]+)")
    if not serial then
        logger.warn("KoboKDRM: Could not parse serial from version file")
        return nil
    end

    logger.dbg("KoboKDRM: Device serial:", serial)

    return serial
end

---
--- Read user ID from Kobo database.
--- @param db_path string: Path to KoboReader.sqlite
--- @return string|nil: User UUID, or nil on failure
function KoboKDRM:getUserId(db_path)
    logger.dbg("KoboKDRM: Reading user ID from:", db_path)

    local db_conn = SQ3.open(db_path)
    if not db_conn then
        logger.warn("KoboKDRM: Could not open database:", db_path)

        return nil
    end

    local stmt = db_conn:prepare("SELECT UserID FROM user")
    if not stmt then
        db_conn:close()
        logger.warn("KoboKDRM: Could not prepare user query")

        return nil
    end

    local user_id = nil
    local row = stmt:step()
    if row then
        user_id = row[1]
    end

    stmt:close()
    db_conn:close()

    if not user_id then
        logger.warn("KoboKDRM: No user ID found in database")

        return nil
    end

    logger.dbg("KoboKDRM: User ID:", user_id)

    return user_id
end

---
--- Get all content keys for a book from the database.
--- @param db_path string: Path to KoboReader.sqlite
--- @param volume_id string: Book UUID
--- @return table|nil: Map of elementId -> encrypted key (base64), or nil on failure
function KoboKDRM:getContentKeys(db_path, volume_id)
    logger.dbg("KoboKDRM: Reading content keys for book:", volume_id)

    local db_conn = SQ3.open(db_path)
    if not db_conn then
        logger.warn("KoboKDRM: Could not open database:", db_path)

        return nil
    end

    local stmt = db_conn:prepare("SELECT elementId, elementKey FROM content_keys WHERE volumeId = ?")
    if not stmt then
        db_conn:close()
        logger.warn("KoboKDRM: Could not prepare content_keys query")

        return nil
    end

    stmt:bind(volume_id)

    local content_keys = {}
    local row = stmt:step()
    while row do
        local element_id = row[1]
        local element_key = row[2]
        content_keys[element_id] = element_key
        row = stmt:step()
    end

    stmt:close()
    db_conn:close()

    local count = 0
    for _ in pairs(content_keys) do
        count = count + 1
    end

    logger.dbg("KoboKDRM: Found", count, "content keys for book")

    return content_keys
end

---
--- Get decrypted content key for a single file in an encrypted book.
--- This is the most efficient method when you only need to decrypt one specific file.
--- @param book_id string: Book UUID
--- @param element_id string: File path within the EPUB (e.g., "OEBPS/images/cover.jpg")
--- @param kobo_dir string: Path to .kobo directory
--- @param db_path string: Path to KoboReader.sqlite
--- @return string|nil: Decrypted content key (16 bytes), or nil on failure
function KoboKDRM:getDecryptedKey(book_id, element_id, kobo_dir, db_path)
    logger.dbg("KoboKDRM: Getting decrypted key for file:", element_id, "in book:", book_id)

    local serial = self:getDeviceSerial(kobo_dir)
    if not serial then
        logger.warn("KoboKDRM: Failed to read device serial")

        return nil
    end

    local user_id = self:getUserId(db_path)
    if not user_id then
        logger.warn("KoboKDRM: Failed to read user ID")

        return nil
    end

    local content_keys_map = self:getContentKeys(db_path, book_id)
    if not content_keys_map or next(content_keys_map) == nil then
        logger.warn("KoboKDRM: No content keys found for book")

        return nil
    end

    local encrypted_key_b64 = content_keys_map[element_id]
    if not encrypted_key_b64 then
        logger.warn("KoboKDRM: No content key found for element:", element_id)

        return nil
    end

    local first_element = next(content_keys_map)
    local first_key_b64 = content_keys_map[first_element]

    local user_key = KeyDerivation:findWorkingKey(serial, user_id, function(candidate_key)
        local test_content_key = FileDecryptor:decryptContentKey(first_key_b64, candidate_key)
        if test_content_key and #test_content_key == 16 then
            logger.dbg("KoboKDRM: Successfully decrypted content key with candidate user key")

            return true
        end

        return false
    end)

    if not user_key then
        logger.warn("KoboKDRM: Could not find working user key")

        return nil
    end

    local content_key = FileDecryptor:decryptContentKey(encrypted_key_b64, user_key)
    if not content_key then
        logger.warn("KoboKDRM: Failed to decrypt content key for element:", element_id)

        return nil
    end

    logger.dbg("KoboKDRM: Successfully decrypted content key for:", element_id)

    return content_key
end

---
--- Get decrypted content keys for a book without decrypting the full book.
--- This is useful for extracting only specific files (like covers) from encrypted books.
--- @param book_id string: Book UUID
--- @param kobo_dir string: Path to .kobo directory
--- @param db_path string: Path to KoboReader.sqlite
--- @return table|nil: Map of element_id -> content_key (decrypted), or nil on failure
function KoboKDRM:getDecryptedKeys(book_id, kobo_dir, db_path)
    logger.dbg("KoboKDRM: Getting decrypted keys for book:", book_id)

    local serial = self:getDeviceSerial(kobo_dir)
    if not serial then
        logger.warn("KoboKDRM: Failed to read device serial")

        return nil
    end

    local user_id = self:getUserId(db_path)
    if not user_id then
        logger.warn("KoboKDRM: Failed to read user ID")

        return nil
    end

    local content_keys_map = self:getContentKeys(db_path, book_id)
    if not content_keys_map or next(content_keys_map) == nil then
        logger.warn("KoboKDRM: No content keys found for book")

        return nil
    end

    local first_element = next(content_keys_map)
    local first_key_b64 = content_keys_map[first_element]

    local user_key = KeyDerivation:findWorkingKey(serial, user_id, function(candidate_key)
        local test_content_key = FileDecryptor:decryptContentKey(first_key_b64, candidate_key)
        if test_content_key and #test_content_key == 16 then
            logger.dbg("KoboKDRM: Successfully decrypted content key with candidate user key")

            return true
        end

        return false
    end)

    if not user_key then
        logger.warn("KoboKDRM: Could not find working user key")

        return nil
    end

    local decrypted_keys = {}
    for element_id, encrypted_key_b64 in pairs(content_keys_map) do
        local content_key = FileDecryptor:decryptContentKey(encrypted_key_b64, user_key)
        if content_key then
            decrypted_keys[element_id] = content_key
        end
    end

    logger.dbg("KoboKDRM: Decrypted", #decrypted_keys, "content keys")

    return decrypted_keys
end

---
--- Decrypt a complete book file.
--- @param book_id string: Book UUID
--- @param input_path string: Path to encrypted EPUB/KEPUB
--- @param output_path string: Path for decrypted output
--- @param kobo_dir string: Path to .kobo directory
--- @param db_path string: Path to KoboReader.sqlite
--- @return boolean: True if successful, false otherwise
--- @return string|nil: Error message if failed
function KoboKDRM:decryptBook(book_id, input_path, output_path, kobo_dir, db_path)
    logger.dbg("KoboKDRM: Starting decryption for book:", book_id)
    logger.dbg("KoboKDRM: Input:", input_path)
    logger.dbg("KoboKDRM: Output:", output_path)

    local serial = self:getDeviceSerial(kobo_dir)
    if not serial then
        return false, "Failed to read device serial"
    end

    local user_id = self:getUserId(db_path)
    if not user_id then
        return false, "Failed to read user ID"
    end

    local content_keys_map = self:getContentKeys(db_path, book_id)
    if not content_keys_map or next(content_keys_map) == nil then
        return false, "No content keys found for book"
    end

    logger.dbg("KoboKDRM: Searching for working user key...")
    local first_element = next(content_keys_map)
    local first_key_b64 = content_keys_map[first_element]

    logger.dbg("KoboKDRM: First element ID from database:", first_element)

    local user_key, hash_key = KeyDerivation:findWorkingKey(serial, user_id, function(candidate_key)
        logger.dbg("KoboKDRM: Testing user key candidate...")
        local test_content_key = FileDecryptor:decryptContentKey(first_key_b64, candidate_key)
        if not test_content_key then
            return false
        end

        return true
    end)

    if not user_key then
        return false, "Could not find working user key"
    end

    logger.dbg("KoboKDRM: Found working hash key:", hash_key)

    logger.dbg("KoboKDRM: Decrypting all content keys...")
    local decrypted_keys = {}
    for element_id, encrypted_key_b64 in pairs(content_keys_map) do
        local content_key = FileDecryptor:decryptContentKey(encrypted_key_b64, user_key)
        if content_key then
            decrypted_keys[element_id] = content_key
        else
            logger.warn("KoboKDRM: Failed to decrypt content key for:", element_id)
        end
    end

    local keys_count = 0
    for _ in pairs(decrypted_keys) do
        keys_count = keys_count + 1
    end

    logger.dbg("KoboKDRM: Decrypted", keys_count, "content keys")

    logger.dbg("KoboKDRM: Processing book archive...")
    local input_arc = Archiver.Reader:new()
    if not input_arc:open(input_path) then
        return false, "Could not open input archive"
    end

    local output_arc = Archiver.Writer:new()
    if not output_arc:open(output_path, "zip") then
        input_arc:close()

        return false, "Could not create output archive"
    end

    local files_decrypted = 0
    local files_copied = 0
    local files_failed = 0

    for entry in input_arc:iterate() do
        local file_path = entry.path
        local file_content = input_arc:extractToMemory(entry.index)

        if not file_content then
            logger.warn("KoboKDRM: Could not read file:", file_path)
            files_failed = files_failed + 1
        else
            if decrypted_keys[file_path] then
                logger.dbg("KoboKDRM: Decrypting:", file_path)

                local decrypted_content = FileDecryptor:decryptFileContent(file_content, decrypted_keys[file_path])
                if decrypted_content then
                    output_arc:addFileFromMemory(file_path, decrypted_content)
                    files_decrypted = files_decrypted + 1
                else
                    logger.warn("KoboKDRM: Failed to decrypt:", file_path)
                    output_arc:addFileFromMemory(file_path, file_content)
                    files_failed = files_failed + 1
                end
            else
                output_arc:addFileFromMemory(file_path, file_content)
                files_copied = files_copied + 1
            end
        end
    end

    input_arc:close()
    output_arc:close()

    logger.info(
        "KoboKDRM: Decrypted book",
        book_id,
        "- files:",
        files_decrypted,
        "copied:",
        files_copied,
        "failed:",
        files_failed
    )

    if files_failed > 0 then
        return true, string.format("Decrypted with %d failures", files_failed)
    end

    return true, nil
end

return KoboKDRM
