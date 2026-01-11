--- Kobo DRM Cache Manager
--- Manages cached decrypted books to avoid re-decrypting on every access.
---
--- This module handles:
--- 1. Checking if a decrypted book exists in cache
--- 2. Getting cache path for a book
--- 3. Clearing cache (all or specific books)

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local CacheManager = {}

---
--- Ensure cache directory exists, create if necessary.
--- @param cache_dir string: Cache directory path
--- @return boolean: True if directory exists or was created successfully
function CacheManager:ensureCacheDir(cache_dir)
    local attr = lfs.attributes(cache_dir)

    if attr and attr.mode == "directory" then
        return true
    end

    if attr then
        logger.warn("CacheManager: Cache path exists but is not a directory:", cache_dir)
        return false
    end

    logger.dbg("CacheManager: Creating cache directory:", cache_dir)

    local parent = cache_dir:match("^(.+)/[^/]+$")
    if parent and not lfs.attributes(parent) then
        local success = self:ensureCacheDir(parent)
        if not success then
            return false
        end
    end

    local success, err = lfs.mkdir(cache_dir)
    if not success then
        logger.warn("CacheManager: Failed to create cache directory:", err)
        return false
    end

    return true
end

---
--- Get cache path for a book.
--- @param book_id string: Book Content ID
--- @param cache_dir string: Cache directory path
--- @return string: Full path to cached book file
function CacheManager:getCachePath(book_id, cache_dir)
    cache_dir = cache_dir or self:get_default_cache_dir()
    return cache_dir .. "/" .. book_id
end

---
--- Ensure cache file path exists, create directories if necessary.
--- @param book_id string: Book Content ID
--- @param cache_dir string|nil: Cache directory path (optional)
--- @return string|nil: Full path to cached book file or nil on failure
function CacheManager:ensureCachePath(book_id, cache_dir)
    cache_dir = cache_dir or self:get_default_cache_dir()
    local full_path = self:getCachePath(book_id, cache_dir)

    local success = self:ensureCacheDir(cache_dir)
    if not success then
        return nil
    end

    logger.dbg("CacheManager: Ensuring cache file exists:", full_path)

    local file = io.open(full_path, "w")
    if file then
        file:close()
    end

    return full_path
end

---
--- Check if a decrypted book exists in cache.
--- @param book_id string: Book UUID
--- @param cache_dir string|nil: Cache directory path (optional)
--- @return boolean: True if cached file exists
--- @return string|nil: Cache file path if exists
function CacheManager:hasCachedBook(book_id, cache_dir)
    local cache_path = self:getCachePath(book_id, cache_dir)
    local attr = lfs.attributes(cache_path)

    if attr and attr.mode == "file" and attr.size > 0 then
        logger.dbg("CacheManager: Found cached book:", cache_path)
        return true, cache_path
    end

    return false, nil
end

---
--- Get cache statistics.
--- @param cache_dir string|nil: Cache directory path (optional)
--- @return table: Statistics with count and total_size
function CacheManager:getCacheStats(cache_dir)
    cache_dir = cache_dir or self:get_default_cache_dir()

    local stats = {
        count = 0,
        total_size = 0,
        books = {},
    }

    local attr = lfs.attributes(cache_dir)
    if not attr or attr.mode ~= "directory" then
        return stats
    end

    for file in lfs.dir(cache_dir) do
        if file ~= "." and file ~= ".." then
            local file_path = cache_dir .. "/" .. file
            local file_attr = lfs.attributes(file_path)

            if file_attr and file_attr.mode == "file" then
                stats.count = stats.count + 1
                stats.total_size = stats.total_size + file_attr.size

                table.insert(stats.books, {
                    id = file,
                    path = file_path,
                    size = file_attr.size,
                })
            end
        end
    end

    logger.dbg("CacheManager: Cache stats - count:", stats.count, "total_size:", stats.total_size)
    return stats
end

---
--- Clear all books from cache.
--- @param cache_dir string|nil: Cache directory path (optional)
--- @return number: Number of files deleted
--- @return number: Number of errors
function CacheManager:clearAll(cache_dir)
    cache_dir = cache_dir or self:get_default_cache_dir()

    local deleted_count = 0
    local error_count = 0

    local attr = lfs.attributes(cache_dir)
    if not attr or attr.mode ~= "directory" then
        logger.dbg("CacheManager: Cache directory doesn't exist, nothing to clear")
        return 0, 0
    end

    logger.dbg("CacheManager: Clearing all cached books from:", cache_dir)

    for file in lfs.dir(cache_dir) do
        if file ~= "." and file ~= ".." then
            local file_path = cache_dir .. "/" .. file
            local file_attr = lfs.attributes(file_path)

            if file_attr and file_attr.mode == "file" then
                local success, err = os.remove(file_path)
                if success then
                    deleted_count = deleted_count + 1
                else
                    logger.warn("CacheManager: Failed to delete:", file_path, err)
                    error_count = error_count + 1
                end
            end
        end
    end

    logger.info("CacheManager: Cleared", deleted_count, "cached books")
    if error_count > 0 then
        logger.warn("CacheManager:", error_count, "errors during cache clear")
    end

    return deleted_count, error_count
end

return CacheManager
