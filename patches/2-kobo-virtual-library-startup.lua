-- User patch to support Kobo kepub files on startup
-- Priority: 2

-- Get the absolute path of this patch file to determine plugin location
local patch_info = debug.getinfo(1, "S")
local patch_path = patch_info.source:match("^@(.+)$")
local koreader_root = patch_path:match("^(.+)/patches/[^/]+$")

local PatternUtils = dofile(koreader_root .. "/plugins/kobo.koplugin/src/lib/pattern_utils.lua")
local logger = require("logger")

local plugin_settings = G_reader_settings:readSetting("kobo_plugin") or { enable_virtual_library = true }

logger.dbg("KoboPlugin Startup Patch: plugin_settings", plugin_settings)

if not plugin_settings.enable_virtual_library then
    logger.info("KoboPlugin Startup Patch: skipping virtual library patch due to disabled setting")

    return
end

--- Get kepub directory path
local function getKepubPath()
    local env_path = os.getenv("KOBO_LIBRARY_PATH")
    if env_path and env_path ~= "" then
        return env_path:gsub("/kepub$", "") .. "/kepub"
    end

    return "/mnt/onboard/.kobo/kepub"
end

-- Get all possible kepub paths
local function getAllKepubPaths()
    local paths = {}

    -- Environment variable path
    local env_path = os.getenv("KOBO_LIBRARY_PATH")
    if env_path and env_path ~= "" then
        table.insert(paths, env_path:gsub("/kepub$", "") .. "/kepub")
    end

    -- Default device path
    table.insert(paths, "/mnt/onboard/.kobo/kepub")

    return paths
end

-- Check if a file is a kepub file (extensionless file in kepub directory)
local function isKepubFile(file)
    if not file or type(file) ~= "string" then
        return false
    end

    -- Check against all possible kepub paths
    for _, kepub_path in ipairs(getAllKepubPaths()) do
        local escaped_kepub_path = PatternUtils.escape(kepub_path)

        -- Match files in kepub directory with no extension
        local is_in_kepub_dir = file:match("^" .. escaped_kepub_path .. "/[^/]+$")
        local has_no_extension = not file:match("%.[^/]+$")

        if is_in_kepub_dir and has_no_extension then
            return true
        end
    end

    return false
end

-- Patch require() to intercept DocumentRegistry and ReaderPageMap
local original_require = require
_G.require = function(modname)
    local result = original_require(modname)

    -- When DocumentRegistry is required, patch it immediately
    if modname == "document/documentregistry" and type(result) == "table" then
        local DocumentRegistry = result

        -- Patch hasProvider (only patch once)
        if not DocumentRegistry._kepub_patched_hasProvider then
            local original_hasProvider = DocumentRegistry.hasProvider
            DocumentRegistry.hasProvider = function(self, file, provider_name)
                if isKepubFile(file) then
                    logger.dbg("KoboPlugin Startup Patch: Opening kepub file:", file)
                    return true
                end
                return original_hasProvider(self, file, provider_name)
            end
            DocumentRegistry._kepub_patched_hasProvider = true
        end

        -- Patch getProvider (only patch once)
        if not DocumentRegistry._kepub_patched_getProvider then
            local original_getProvider = DocumentRegistry.getProvider
            DocumentRegistry.getProvider = function(self, file, force_provider)
                if not isKepubFile(file) then
                    return original_getProvider(self, file, force_provider)
                end

                -- Get the kepubdocument provider directly from known providers
                local kepub_provider = self.known_providers["kepubdocument"] or self.known_providers["crengine"]
                if kepub_provider then
                    return kepub_provider
                end

                -- Fallback to getting provider for a dummy .kepub.epub file
                return original_getProvider(self, "dummy.kepub.epub", force_provider)
            end
            DocumentRegistry._kepub_patched_getProvider = true
        end
    end

    -- When DocSettings is required, patch it for kepub compatibility
    if modname == "docsettings" and type(result) == "table" then
        local DocSettings = result
        if not DocSettings._kepub_patched_getSidecarFilename then
            local original_getSidecarFilename = DocSettings.getSidecarFilename

            DocSettings.getSidecarFilename = function(doc_path)
                -- Check if this is a kepub file in kepub directory
                if doc_path and type(doc_path) == "string" then
                    for _, kepub_path in ipairs(getAllKepubPaths()) do
                        local escaped_kepub_path = PatternUtils.escape(kepub_path)
                        local is_in_kepub_dir = doc_path:match("^" .. escaped_kepub_path .. "/[^/]+$")
                        local has_no_extension = not doc_path:match("%.[^/]+$")

                        if is_in_kepub_dir and has_no_extension then
                            -- Add .kepub.epub extension for sidecar lookup
                            local doc_with_ext = doc_path .. ".kepub.epub"
                            return original_getSidecarFilename(doc_with_ext)
                        end
                    end
                end

                return original_getSidecarFilename(doc_path)
            end

            DocSettings._kepub_patched_getSidecarFilename = true
        end
    end

    -- When ReaderPageMap is required, patch it for kepub compatibility
    if modname == "apps/reader/modules/readerpagemap" and type(result) == "table" then
        local ReaderPageMap = result

        if not ReaderPageMap._kepub_patched_postInit then
            local original_postInit = ReaderPageMap._postInit

            ReaderPageMap._postInit = function(rp_self)
                -- Try to call original, but catch errors for kepub compatibility
                local ok = pcall(function()
                    if rp_self.ui.document.hasPageMapDocumentProvided then
                        return original_postInit(rp_self)
                    end
                end)

                if ok then
                    return
                end

                -- Fallback for documents without this method (kepub files)
                rp_self.initialized = true
                rp_self.has_pagemap_document_provided = false
            end
            ReaderPageMap._kepub_patched_postInit = true
        end
    end

    if modname == "ffi/util" and type(result) == "table" then
        local ffiUtil = result

        if not ffiUtil._kepub_patched_realpath then
            local original_realpath = ffiUtil.realpath

            ffiUtil.realpath = function(path)
                if type(path) ~= "string" then
                    return original_realpath(path)
                end

                -- Debug: Log all realpath calls to understand what paths are being checked
                logger.dbg("KoboPlugin Startup Patch: realpath called with:", path)

                local virtual_name = "Kobo Library"
                local virtual_prefix = "KOBO_VIRTUAL://"
                local escaped_name = PatternUtils.escape(virtual_name)
                local kepub_path = getKepubPath()

                -- Check if path uses KOBO_VIRTUAL:// prefix (virtual path format)
                if path:sub(1, #virtual_prefix) == virtual_prefix then
                    -- Extract the part after KOBO_VIRTUAL://
                    local virtual_suffix = path:sub(#virtual_prefix + 1)

                    -- If it's just the base KOBO_VIRTUAL:// or KOBO_VIRTUAL:/// return kepub root
                    if virtual_suffix == "" or virtual_suffix == "/" then
                        logger.dbg(
                            "KoboPlugin Startup Patch: realpath intercepted KOBO_VIRTUAL root:",
                            path,
                            "->",
                            kepub_path
                        )

                        return kepub_path
                    end

                    -- Otherwise append the suffix to kepub path, removing leading slashes
                    local normalized_suffix = virtual_suffix:gsub("^/+", "")
                    local translated_path = kepub_path .. "/" .. normalized_suffix

                    logger.dbg(
                        "KoboPlugin Startup Patch: realpath intercepted KOBO_VIRTUAL path:",
                        path,
                        "->",
                        translated_path
                    )

                    return translated_path
                end

                -- Check if path is exactly the virtual library name (with or without trailing slash)
                if path == virtual_name or path == virtual_name .. "/" then
                    logger.dbg(
                        "KoboPlugin Startup Patch: realpath intercepted virtual library folder:",
                        path,
                        "->",
                        kepub_path
                    )

                    return kepub_path
                end

                -- Check if path starts with the virtual library name (e.g., "Kobo Library/file.epub")
                local starts_with_pattern = "^" .. escaped_name .. "/(.*)$"
                local suffix = path:match(starts_with_pattern)

                if suffix then
                    local translated_path = kepub_path .. "/" .. suffix

                    logger.dbg(
                        "KoboPlugin Startup Patch: realpath intercepted virtual library path:",
                        path,
                        "->",
                        translated_path
                    )

                    return translated_path
                end

                -- Check if path contains /virtual_library_name/ in the middle
                local prefix, path_suffix = path:match("^(.+)/" .. escaped_name .. "/(.+)$")

                if prefix and path_suffix then
                    local translated_path = kepub_path .. "/" .. path_suffix

                    logger.dbg(
                        "KoboPlugin Startup Patch: realpath intercepted virtual library path:",
                        path,
                        "->",
                        translated_path
                    )

                    return translated_path
                end

                -- Check if path ends with /virtual_library_name (folder itself, no trailing content)
                local matches_at_end = path:match("/" .. escaped_name .. "/?$") ~= nil

                if matches_at_end then
                    logger.dbg(
                        "KoboPlugin Startup Patch: realpath intercepted virtual library folder:",
                        path,
                        "->",
                        kepub_path
                    )

                    return kepub_path
                end

                return original_realpath(path)
            end

            ffiUtil._kepub_patched_realpath = true
            logger.info("KoboPlugin Startup Patch: Applied ffi/util.realpath patch for virtual library folder support")
        end
    end

    return result
end
