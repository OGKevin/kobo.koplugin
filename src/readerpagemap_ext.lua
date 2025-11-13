-- ReaderPageMap extensions for compatibility
-- Adds defensive checks for hasPageMapDocumentProvided method

local logger = require("logger")

local ReaderPageMapExt = {}

---
-- Creates a new ReaderPageMapExt instance.
-- @param o table: Optional initialization table.
-- @return table: A new ReaderPageMapExt instance.
function ReaderPageMapExt:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.original_methods = {}
    return o
end

---
-- Handles synthetic page map initialization for new documents.
-- @param rp_self table: ReaderPageMap instance.
-- @param chars_per_synthetic_page number: Characters per synthetic page.
local function handleNewDocumentPageMap(rp_self, chars_per_synthetic_page)
    if chars_per_synthetic_page then
        rp_self.chars_per_synthetic_page = chars_per_synthetic_page
        rp_self.ui.doc_settings:saveSetting("pagemap_chars_per_synthetic_page", chars_per_synthetic_page)
        if rp_self.ui.document.buildSyntheticPageMap then
            rp_self.ui.document:buildSyntheticPageMap(chars_per_synthetic_page)
        end
    end
end

---
-- Handles synthetic page map initialization for existing documents.
-- @param rp_self table: ReaderPageMap instance.
local function handleExistingDocumentPageMap(rp_self)
    local chars_per_synthetic_page = rp_self.ui.doc_settings:readSetting("pagemap_chars_per_synthetic_page")
    if chars_per_synthetic_page then
        rp_self.chars_per_synthetic_page = chars_per_synthetic_page
        if rp_self.ui.document.buildSyntheticPageMap then
            rp_self.ui.document:buildSyntheticPageMap(chars_per_synthetic_page)
        end
    end
end

---
-- Gets characters per synthetic page from document or global settings.
-- @param rp_self table: ReaderPageMap instance.
-- @return number: Characters per synthetic page, or 0 if not available.
local function getCharsPerSyntheticPage(rp_self)
    if rp_self.ui.document.getSyntheticPageMapCharsPerPage then
        return rp_self.ui.document:getSyntheticPageMapCharsPerPage()
    end
    return 0
end

---
-- Fallback initialization for documents without hasPageMapDocumentProvided method.
-- Handles synthetic page map setup for both new and existing documents.
-- @param rp_self table: ReaderPageMap instance.
local function fallbackPostInit(rp_self)
    rp_self.initialized = true
    rp_self.has_pagemap_document_provided = false

    local chars_per_synthetic_page = getCharsPerSyntheticPage(rp_self)

    if chars_per_synthetic_page > 0 then
        rp_self.chars_per_synthetic_page = chars_per_synthetic_page
        rp_self.ui.doc_settings:saveSetting("pagemap_chars_per_synthetic_page", chars_per_synthetic_page)

        return
    end

    local G_reader_settings = require("frontend/luasettings"):open()

    if rp_self.ui.document.is_new then
        local saved_chars = G_reader_settings:readSetting("pagemap_chars_per_synthetic_page")
        handleNewDocumentPageMap(rp_self, saved_chars)

        return
    end

    handleExistingDocumentPageMap(rp_self)
end

---
-- Creates patched _postInit method with fallback for missing hasPageMapDocumentProvided.
-- @param original_postInit function: Original _postInit method.
-- @return function: Patched _postInit method.
local function createPatchedPostInit(original_postInit)
    return function(rp_self)
        if rp_self.ui.document.hasPageMapDocumentProvided then
            return original_postInit(rp_self)
        end

        logger.warn("KoboPlugin: Document does not have hasPageMapDocumentProvided method, using fallback")
        fallbackPostInit(rp_self)
    end
end

---
-- Applies ReaderPageMap monkey patches for Kobo kepub compatibility.
-- Patches _postInit to handle documents without hasPageMapDocumentProvided method.
-- @param ReaderPageMap table: ReaderPageMap module to patch.
function ReaderPageMapExt:apply(ReaderPageMap)
    logger.info("KoboPlugin: Applying ReaderPageMap monkey patches for Kobo kepub compatibility")

    self.original_methods._postInit = ReaderPageMap._postInit
    ReaderPageMap._postInit = createPatchedPostInit(self.original_methods._postInit)
end

---
-- Removes ReaderPageMap monkey patches.
-- Restores original methods to their unpatched state.
-- @param ReaderPageMap table: ReaderPageMap module to unpatch.
function ReaderPageMapExt:unapply(ReaderPageMap)
    logger.info("KoboPlugin: Removing ReaderPageMap monkey patches")

    for method_name, original_method in pairs(self.original_methods) do
        ReaderPageMap[method_name] = original_method
    end

    self.original_methods = {}
end

return ReaderPageMapExt
