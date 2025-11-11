-- User patch to support Kobo kepub files on startup
-- This patch runs late, after modules are loaded but before reader starts
-- Priority: 2 (late)

local logger = require("logger")

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
        local escaped_kepub_path = kepub_path:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")

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
                if isKepubFile(file) then
                    -- Get the kepubdocument provider directly from known providers
                    local kepub_provider = self.known_providers["kepubdocument"] or self.known_providers["crengine"]
                    if kepub_provider then
                        return kepub_provider
                    else
                        -- Fallback to getting provider for a dummy .kepub.epub file
                        return original_getProvider(self, "dummy.kepub.epub", force_provider)
                    end
                end
                return original_getProvider(self, file, force_provider)
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
                        local escaped_kepub_path = kepub_path:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
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
                local ok, err = pcall(function()
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

    return result
end
