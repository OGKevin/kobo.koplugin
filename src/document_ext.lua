---
-- Document provider extensions for Kobo kepub files.
-- Monkey patches DocumentRegistry to handle virtual kepub files as EPUBs.

local logger = require("logger")

local DocumentExt = {}

---
-- Wraps a document method in a safe pcall wrapper.
-- Returns safe defaults on error instead of crashing.
-- @param doc table: Document instance.
-- @param method_name string: Name of the method to wrap.
-- @param original_method function: Original method implementation.
local function wrapPageMapMethod(doc, method_name, original_method)
    doc[method_name] = function(self, ...)
        local ok, result = pcall(original_method, self, ...)
        if ok then
            return result
        end

        logger.warn("KoboPlugin:", method_name, "crashed, returning safe default")

        if method_name:match("^has") or method_name:match("^is") then
            return false
        end

        if method_name == "getSyntheticPageMapCharsPerPage" then
            return 0
        end
    end
end

---
-- Adds safe fallback wrappers for page map methods.
-- Prevents crashes from unstable pagemap functionality.
-- @param doc table: Document instance.
local function addPageMapSafeguards(doc)
    local pagemap_methods = {
        "hasPageMapDocumentProvided",
        "isPageMapDocumentProvided",
        "isPageMapSynthetic",
        "getSyntheticPageMapCharsPerPage",
        "buildSyntheticPageMap",
        "hasPageMap",
    }

    for _, method_name in ipairs(pagemap_methods) do
        if not doc[method_name] then
            goto continue
        end

        local original_method = doc[method_name]
        wrapPageMapMethod(doc, method_name, original_method)

        ::continue::
    end
end

---
-- Initializes the DocumentExt module.
-- @param virtual_library table: Virtual library instance.
function DocumentExt:init(virtual_library)
    self.virtual_library = virtual_library
    self.original_methods = {}
end

---
-- Applies monkey patches to DocumentRegistry.
-- Patches hasProvider, getProvider, and openDocument for virtual kepub files.
-- @param DocumentRegistry table: DocumentRegistry module to patch.
function DocumentExt:apply(DocumentRegistry)
    if not self.virtual_library:isActive() then
        logger.info("KoboPlugin: Kobo plugin not active, skipping DocumentRegistry patches")
        return
    end

    logger.info("KoboPlugin: Applying DocumentRegistry monkey patches for Kobo kepub files")

    self.original_methods.hasProvider = DocumentRegistry.hasProvider
    DocumentRegistry.hasProvider = function(dr_self, file)
        if not self.virtual_library:isVirtualPath(file) then
            return self.original_methods.hasProvider(dr_self, file)
        end

        return true
    end

    self.original_methods.getProvider = DocumentRegistry.getProvider
    DocumentRegistry.getProvider = function(dr_self, file)
        if not self.virtual_library:isVirtualPath(file) then
            return self.original_methods.getProvider(dr_self, file)
        end

        local CreDocument = require("document/credocument")
        return CreDocument
    end

    self.original_methods.openDocument = DocumentRegistry.openDocument
    DocumentRegistry.openDocument = function(dr_self, file, provider)
        local actual_file = file
        local virtual_path = nil

        if self.virtual_library:isVirtualPath(file) then
            virtual_path = file
            actual_file = self.virtual_library:getRealPath(file)

            if not actual_file then
                logger.err("KoboPlugin: Failed to resolve virtual path:", file)
                return nil
            end

            logger.dbg("KoboPlugin: Opening virtual kepub file:", file, "->", actual_file)

            if not provider then
                provider = require("document/credocument")
            end
        end

        local doc = self.original_methods.openDocument(dr_self, actual_file, provider)

        if not doc or not virtual_path then
            return doc
        end

        doc.virtual_path = virtual_path
        logger.dbg("KoboPlugin: Stored virtual_path in document:", virtual_path)
        logger.dbg("KoboPlugin: Opened document type:", type(doc), "provider:", doc.provider or "unknown")

        addPageMapSafeguards(doc)

        return doc
    end
end

---
-- Removes all monkey patches and restores original methods.
-- @param DocumentRegistry table: DocumentRegistry module to restore.
function DocumentExt:unapply(DocumentRegistry)
    logger.info("KoboPlugin: Removing DocumentRegistry monkey patches")

    for method_name, original_method in pairs(self.original_methods) do
        DocumentRegistry[method_name] = original_method
    end

    self.original_methods = {}
end

return DocumentExt
