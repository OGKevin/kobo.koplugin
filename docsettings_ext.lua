---
-- DocSettings extensions for Kobo kepub files.
-- Monkey patches DocSettings to handle virtual paths when creating sidecar directories.

local DataStorage = require("datastorage")
local logger = require("logger")
local util = require("util")

local DocSettingsExt = {}

---
-- Resolves a virtual path to its real file path.
-- @param doc_path string: Document path (may be virtual or real).
-- @param virtual_library table: Virtual library instance.
-- @return string|nil: Real file path if this is a kepub file, nil otherwise.
local function resolveKepubRealPath(doc_path, virtual_library)
    if virtual_library:isVirtualPath(doc_path) then
        return virtual_library:getRealPath(doc_path)
    end

    local virtual_path = virtual_library:getVirtualPath(doc_path)
    if virtual_path then
        return doc_path
    end

    if doc_path:match("/") then
        return nil
    end

    for real_p, _ in pairs(virtual_library.real_to_virtual) do
        if real_p:match("/([^/]+)$") == doc_path then
            logger.dbg("KoboPlugin: Matched basename to full path:", doc_path, "->", real_p)
            return real_p
        end
    end

    return nil
end

---
-- Builds sidecar directory path for 'dir' location.
-- @param real_path string: Real file path.
-- @return string: Sidecar directory path.
local function buildDirLocationPath(real_path)
    local DOCSETTINGS_DIR = DataStorage:getDocSettingsDir()
    local sidecar_path = DOCSETTINGS_DIR .. real_path
    logger.dbg("KoboPlugin: Using 'dir' location:", sidecar_path)
    return sidecar_path
end

---
-- Builds sidecar directory path for 'hash' location.
-- @param real_path string: Real file path.
-- @return string: Sidecar directory path, or real_path if hash fails.
local function buildHashLocationPath(real_path)
    local hsh = util.partialMD5(real_path)
    if not hsh then
        logger.warn("KoboPlugin: MD5 hash failed, falling back to 'doc' location")
        return real_path
    end

    local DOCSETTINGS_HASH_DIR = DataStorage:getDocSettingsHashDir()
    local subpath = string.format("/%s/", hsh:sub(1, 2))
    local sidecar_path = DOCSETTINGS_HASH_DIR .. subpath .. hsh
    logger.dbg("KoboPlugin: Using 'hash' location:", sidecar_path)
    return sidecar_path
end

---
-- Builds sidecar directory path based on user's preferred location.
-- @param real_path string: Real file path.
-- @param force_location string|nil: Forced location override.
-- @return string: Sidecar directory path with .sdr extension.
local function buildKepubSidecarPath(real_path, force_location)
    local location = force_location or G_reader_settings:readSetting("document_metadata_folder", "doc")
    local sidecar_path

    if location == "dir" then
        sidecar_path = buildDirLocationPath(real_path)

        return sidecar_path .. ".sdr"
    end

    if location == "hash" then
        sidecar_path = buildHashLocationPath(real_path)

        return sidecar_path .. ".sdr"
    end

    sidecar_path = real_path
    logger.dbg("KoboPlugin: Using 'doc' location:", sidecar_path)

    return sidecar_path .. ".sdr"
end

---
-- Extracts filename from virtual path for sidecar file naming.
-- @param virtual_path string: Virtual library path.
-- @return string|nil: Filename if extracted successfully.
local function extractFilenameFromVirtualPath(virtual_path)
    return virtual_path:match("KOBO_VIRTUAL://[^/]+/(.+)$")
end

---
-- Searches for a real path by basename match in virtual library mappings.
-- @param basename string: File basename to search for.
-- @param virtual_library table: Virtual library instance.
-- @return string|nil: Virtual path if found.
local function findVirtualPathByBasename(basename, virtual_library)
    for real_path, virt_path in pairs(virtual_library.real_to_virtual) do
        if real_path:match("/([^/]+)$") == basename then
            logger.dbg("KoboPlugin: Matched basename to full path:", basename, "->", real_path)
            return virt_path
        end
    end

    return nil
end

---
-- Initializes the DocSettingsExt module.
-- @param virtual_library table: Virtual library instance.
function DocSettingsExt:init(virtual_library)
    self.virtual_library = virtual_library
    self.original_methods = {}
end

---
-- Applies monkey patches to DocSettings.
-- Patches getSidecarDir, getSidecarFilename, and getHistoryPath for virtual kepub files.
-- @param DocSettings table: DocSettings module to patch.
function DocSettingsExt:apply(DocSettings)
    if not self.virtual_library:isActive() then
        logger.info("KoboPlugin: Kobo plugin not active, skipping DocSettings patches")
        return
    end

    logger.info("KoboPlugin: Applying DocSettings monkey patches for Kobo kepub files")

    self.original_methods.getSidecarDir = DocSettings.getSidecarDir
    DocSettings.getSidecarDir = function(ds_self, doc_path, force_location)
        local real_path = resolveKepubRealPath(doc_path, self.virtual_library)

        if not real_path then
            return self.original_methods.getSidecarDir(ds_self, doc_path, force_location)
        end

        logger.dbg("KoboPlugin: Building sidecar dir for kepub:", doc_path, "->", real_path)
        return buildKepubSidecarPath(real_path, force_location)
    end

    self.original_methods.getSidecarFilename = DocSettings.getSidecarFilename
    DocSettings.getSidecarFilename = function(doc_path)
        local actual_path = doc_path

        if self.virtual_library:isVirtualPath(doc_path) then
            local filename = extractFilenameFromVirtualPath(doc_path)
            if filename then
                actual_path = filename
                logger.dbg("KoboPlugin: Using filename for sidecar:", filename)
            end

            local result = self.original_methods.getSidecarFilename(actual_path)
            logger.dbg("KoboPlugin: getSidecarFilename result:", result)

            return result
        end

        local virtual_path = self.virtual_library:getVirtualPath(doc_path)

        if not virtual_path and not doc_path:match("/") then
            virtual_path = findVirtualPathByBasename(doc_path, self.virtual_library)
        end

        if not virtual_path then
            logger.dbg("KoboPlugin: getSidecarFilename called with non-kepub path:", doc_path)

            local result = self.original_methods.getSidecarFilename(actual_path)
            logger.dbg("KoboPlugin: getSidecarFilename result:", result)

            return result
        end

        local filename = extractFilenameFromVirtualPath(virtual_path)
        if filename then
            actual_path = filename
            logger.dbg("KoboPlugin: Reverse mapping to virtual filename:", doc_path, "->", filename)
        end

        local result = self.original_methods.getSidecarFilename(actual_path)
        logger.dbg("KoboPlugin: getSidecarFilename result:", result)

        return result
    end

    self.original_methods.getHistoryPath = DocSettings.getHistoryPath
    DocSettings.getHistoryPath = function(ds_self, doc_path)
        if not self.virtual_library:isVirtualPath(doc_path) then
            return self.original_methods.getHistoryPath(ds_self, doc_path)
        end

        local actual_path = self.virtual_library:getRealPath(doc_path)
        if not actual_path then
            logger.err("KoboPlugin: Failed to resolve virtual path for history:", doc_path)
            return ""
        end

        logger.dbg("KoboPlugin: Translating virtual path for history:", doc_path, "->", actual_path)
        return self.original_methods.getHistoryPath(ds_self, actual_path)
    end
end

---
-- Removes all monkey patches and restores original methods.
-- @param DocSettings table: DocSettings module to restore.
function DocSettingsExt:unapply(DocSettings)
    logger.info("KoboPlugin: Removing DocSettings monkey patches")

    for method_name, original_method in pairs(self.original_methods) do
        DocSettings[method_name] = original_method
    end

    self.original_methods = {}
end

return DocSettingsExt
