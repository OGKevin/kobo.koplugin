---
-- Kobo Kepub Plugin Entry Point.
-- Provides access to Kobo Nickel library books in KOReader.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local T = require("ffi/util").template
local MetadataParser = require("src.metadata_parser")
local ReadingStateSync = require("src.reading_state_sync")
local VirtualLibrary = require("src.virtual_library")

local SYNC_DIRECTION = {
    PROMPT = 1,
    SILENT = 2,
    NEVER = 3,
}

---
-- Gets localized name for a sync direction.
-- @param direction number: SYNC_DIRECTION constant.
-- @return string: Localized direction name.
local function getNameDirection(direction)
    if direction == SYNC_DIRECTION.PROMPT then
        return _("Prompt")
    end

    if direction == SYNC_DIRECTION.SILENT then
        return _("Silent")
    end

    return _("Never")
end

---
-- Applies ShowReader extensions for virtual library support.
-- @param virtual_library table: Virtual library instance.
local function applyShowReaderExtensions(virtual_library)
    local ShowReaderExt = require("src.showreader_ext")
    local sr_ext = ShowReaderExt
    sr_ext:init({ virtual_library = virtual_library })
    sr_ext:apply()
end

---
-- Applies filesystem extensions for virtual path support.
-- @param virtual_library table: Virtual library instance.
local function applyFilesystemExtensions(virtual_library)
    local FilesystemExt = require("src.filesystem_ext")
    local fs_ext = FilesystemExt
    fs_ext:init(virtual_library)
    fs_ext:apply()
end

---
-- Applies document provider extensions for kepub files.
-- @param virtual_library table: Virtual library instance.
local function applyDocumentExtensions(virtual_library)
    local DocumentRegistry = require("document/documentregistry")
    local DocumentExt = require("src.document_ext")
    local doc_ext = DocumentExt
    doc_ext:init(virtual_library)
    doc_ext:apply(DocumentRegistry)
end

---
-- Applies DocSettings extensions for sidecar file support.
-- @param virtual_library table: Virtual library instance.
local function applyDocSettingsExtensions(virtual_library)
    local DocSettings = require("docsettings")
    local DocSettingsExt = require("src.docsettings_ext")
    local ds_ext = DocSettingsExt
    ds_ext:init(virtual_library)
    ds_ext:apply(DocSettings)
end

---
-- Applies FileChooser extensions for virtual library.
-- @param virtual_library table: Virtual library instance.
-- @param reading_state_sync table: Reading state sync instance.
local function applyFileChooserExtensions(virtual_library, reading_state_sync)
    local FileChooser = require("ui/widget/filechooser")
    local FileChooserExt = require("src.filechooser_ext")
    local fc_ext = FileChooserExt
    fc_ext:init(virtual_library, reading_state_sync)
    fc_ext:apply(FileChooser)
end

---
-- Applies BookInfoManager extensions if CoverBrowser is available.
-- @param virtual_library table: Virtual library instance.
local function applyBookInfoManagerExtensions(virtual_library)
    local ok, BookInfoManager = pcall(require, "plugins/coverbrowser.koplugin/bookinfomanager")
    if not ok or not BookInfoManager then
        return
    end

    local BookInfoManagerExt = require("src.bookinfomanager_ext")
    local bim_ext = BookInfoManagerExt
    bim_ext:init(virtual_library)
    bim_ext:apply(BookInfoManager)
    logger.info("KoboPlugin: BookInfoManager patches applied for CoverBrowser integration")
end

---
-- Applies ReaderPageMap extensions for kepub compatibility.
local function applyReaderPageMapExtensions()
    local ok_rpm, ReaderPageMap = pcall(require, "apps/reader/modules/readerpagemap")
    if not ok_rpm or not ReaderPageMap then
        return
    end

    local ReaderPageMapExt = require("src.readerpagemap_ext")
    local rpm_ext = ReaderPageMapExt:new()
    rpm_ext:apply(ReaderPageMap)
    logger.info("KoboPlugin: ReaderPageMap patches applied for kepub compatibility")
end

---
-- Applies ReaderUI extensions for kepub navigation.
-- @param virtual_library table: Virtual library instance.
-- @param reading_state_sync table: Reading state sync instance.
local function applyReaderUIExtensions(virtual_library, reading_state_sync)
    local ok_rui, ReaderUI = pcall(require, "apps/reader/readerui")
    if not ok_rui or not ReaderUI then
        return
    end

    local ReaderUIExt = require("src.readerui_ext")
    local rui_ext = ReaderUIExt
    rui_ext:init(virtual_library, reading_state_sync)
    rui_ext:apply(ReaderUI)
    logger.info("KoboPlugin: ReaderUI patches applied for kepub navigation")
end

local metadata_parser = MetadataParser:new()
local virtual_library = VirtualLibrary:new(metadata_parser)
local reading_state_sync = ReadingStateSync:new(metadata_parser)

if virtual_library:isActive() then
    logger.info("KoboPlugin: Kobo Kepub plugin is active, applying patches")
    applyShowReaderExtensions(virtual_library)
    applyFilesystemExtensions(virtual_library)
    applyDocumentExtensions(virtual_library)
    applyDocSettingsExtensions(virtual_library)
    applyFileChooserExtensions(virtual_library, reading_state_sync)
    applyBookInfoManagerExtensions(virtual_library)
    applyReaderPageMapExtensions()
    applyReaderUIExtensions(virtual_library, reading_state_sync)
end

local KoboKepubPlugin = WidgetContainer:extend({
    name = "kobo_kepub",
    is_doc_only = false,
    default_settings = {
        sync_reading_state = false,
        enable_auto_sync = false,
        enable_sync_from_kobo = false,
        enable_sync_to_kobo = true,
        sync_from_kobo_newer = SYNC_DIRECTION.PROMPT,
        sync_from_kobo_older = SYNC_DIRECTION.NEVER,
        sync_to_kobo_newer = SYNC_DIRECTION.SILENT,
        sync_to_kobo_older = SYNC_DIRECTION.NEVER,
    },
})

---
-- Initializes the plugin and loads settings.
function KoboKepubPlugin:init()
    self.metadata_parser = metadata_parser
    self.virtual_library = virtual_library
    self.reading_state_sync = reading_state_sync

    if not self.virtual_library:isActive() then
        return
    end

    self:loadSettings()
    self.reading_state_sync:setPlugin(self, SYNC_DIRECTION)
    self:addMenuItems()
end

---
-- Loads plugin settings from persistent storage.
function KoboKepubPlugin:loadSettings()
    self.settings = G_reader_settings:readSetting("kobo_kepub") or {}

    for key, default_value in pairs(self.default_settings) do
        if self.settings[key] == nil then
            self.settings[key] = default_value
        end
    end

    self.reading_state_sync:setEnabled(self.settings.sync_reading_state)
end

---
-- Saves plugin settings to persistent storage.
function KoboKepubPlugin:saveSettings()
    self.settings.sync_reading_state = self.reading_state_sync:isEnabled()
    G_reader_settings:saveSetting("kobo_kepub", self.settings)
    G_reader_settings:flush()
end

---
-- Registers menu items with the file browser.
function KoboKepubPlugin:addMenuItems()
    self.ui.menu:registerToMainMenu(self)
end

---
-- Creates sync enable/disable menu item.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createSyncToggleMenuItem()
    return {
        text = _("Sync reading state with Kobo"),
        checked_func = function()
            return self.reading_state_sync:isEnabled()
        end,
        callback = function()
            local enabled = not self.reading_state_sync:isEnabled()
            self.reading_state_sync:setEnabled(enabled)
            self:saveSettings()

            local InfoMessage = require("ui/widget/infomessage")
            local UIManager = require("ui/uimanager")
            UIManager:show(InfoMessage:new({
                text = enabled
                        and _("Reading state sync enabled\n\nKOReader and Kobo reading positions will be synced.")
                    or _("Reading state sync disabled"),
                timeout = 4,
            }))
        end,
        separator = true,
    }
end

---
-- Creates auto-sync menu item.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createAutoSyncMenuItem()
    return {
        text = _("Enable automatic sync on virtual library"),
        help_text = _(
            "When enabled, sync automatically when opening the virtual library (once per KOReader startup). Manual sync can always be triggered from the menu."
        ),
        checked_func = function()
            return self.settings.enable_auto_sync
        end,
        enabled_func = function()
            return self.reading_state_sync:isEnabled()
        end,
        callback = function()
            self.settings.enable_auto_sync = not self.settings.enable_auto_sync
            self:saveSettings()
        end,
        separator = true,
    }
end

---
-- Creates manual sync menu item.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createManualSyncMenuItem()
    return {
        text = _("Sync reading state now"),
        enabled_func = function()
            return self.reading_state_sync:isEnabled()
        end,
        callback = function()
            self.reading_state_sync:syncAllBooksManual()
        end,
        separator = true,
    }
end

---
-- Creates sync direction choice submenu.
-- @param direction_key string: Settings key ('sync_from_kobo_newer', etc.).
-- @param label string: Menu label.
-- @param help_text string: Help text for the menu item.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createSyncDirectionChoiceMenu(direction_key, label, help_text)
    return {
        text_func = function()
            return T(label, getNameDirection(self.settings[direction_key]))
        end,
        help_text = help_text,
        sub_item_table = {
            {
                text = _("Always sync"),
                checked_func = function()
                    return self.settings[direction_key] == SYNC_DIRECTION.SILENT
                end,
                callback = function()
                    self.settings[direction_key] = SYNC_DIRECTION.SILENT
                    self:saveSettings()
                end,
            },
            {
                text = _("Ask me"),
                checked_func = function()
                    return self.settings[direction_key] == SYNC_DIRECTION.PROMPT
                end,
                callback = function()
                    self.settings[direction_key] = SYNC_DIRECTION.PROMPT
                    self:saveSettings()
                end,
            },
            {
                text = _("Never"),
                checked_func = function()
                    return self.settings[direction_key] == SYNC_DIRECTION.NEVER
                end,
                callback = function()
                    self.settings[direction_key] = SYNC_DIRECTION.NEVER
                    self:saveSettings()
                end,
            },
        },
    }
end

---
-- Creates FROM Kobo sync settings submenu.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createFromKoboSyncSettingsMenu()
    return {
        text = _("FROM Kobo sync settings"),
        enabled_func = function()
            return self.settings.enable_sync_from_kobo
        end,
        sub_item_table = {
            self:createSyncDirectionChoiceMenu(
                "sync_from_kobo_newer",
                _("Sync to a newer state (%1)"),
                _("What to do when Kobo has newer progress than KOReader.")
            ),
            self:createSyncDirectionChoiceMenu(
                "sync_from_kobo_older",
                _("Sync to an older state (%1)"),
                _("What to do when Kobo has older progress than KOReader.")
            ),
        },
    }
end

---
-- Creates FROM KOReader sync settings submenu.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createFromKOReaderSyncSettingsMenu()
    return {
        text = _("FROM KOReader sync settings"),
        enabled_func = function()
            return self.settings.enable_sync_to_kobo
        end,
        sub_item_table = {
            self:createSyncDirectionChoiceMenu(
                "sync_to_kobo_newer",
                _("Sync to a newer state (%1)"),
                _("What to do when KOReader has newer progress than Kobo.")
            ),
            self:createSyncDirectionChoiceMenu(
                "sync_to_kobo_older",
                _("Sync to an older state (%1)"),
                _("What to do when KOReader has older progress than Kobo.")
            ),
        },
    }
end

---
-- Creates sync behavior menu item.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createSyncBehaviorMenuItem()
    return {
        text = _("Sync behavior"),
        enabled_func = function()
            return self.reading_state_sync:isEnabled()
        end,
        sub_item_table = {
            {
                text = _("Enable sync FROM Kobo TO KOReader"),
                checked_func = function()
                    return self.settings.enable_sync_from_kobo
                end,
                callback = function()
                    self.settings.enable_sync_from_kobo = not self.settings.enable_sync_from_kobo
                    self:saveSettings()
                end,
            },
            {
                text = _("Enable sync FROM KOReader TO Kobo"),
                checked_func = function()
                    return self.settings.enable_sync_to_kobo
                end,
                callback = function()
                    self.settings.enable_sync_to_kobo = not self.settings.enable_sync_to_kobo
                    self:saveSettings()
                end,
                separator = true,
            },
            self:createFromKoboSyncSettingsMenu(),
            self:createFromKOReaderSyncSettingsMenu(),
        },
        separator = true,
    }
end

---
-- Creates refresh library menu item.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createRefreshLibraryMenuItem()
    return {
        text = _("Refresh library"),
        callback = function()
            self.virtual_library:refresh()

            local InfoMessage = require("ui/widget/infomessage")
            local UIManager = require("ui/uimanager")
            UIManager:show(InfoMessage:new({
                text = _("Kobo library refreshed"),
                timeout = 2,
            }))
        end,
    }
end

---
-- Creates about menu item.
-- @return table: Menu item configuration.
function KoboKepubPlugin:createAboutMenuItem()
    return {
        text = _("About Kobo Library"),
        callback = function()
            local book_count = self.metadata_parser:getBookCount()
            local accessible_books = self.virtual_library.parser:getAccessibleBooks()

            local InfoMessage = require("ui/widget/infomessage")
            local UIManager = require("ui/uimanager")
            UIManager:show(InfoMessage:new({
                text = string.format(
                    "Kobo Library\n\n"
                        .. "Total books in metadata: %d\n"
                        .. "Accessible (unencrypted) books: %d\n\n"
                        .. "Books are synced from Kobo Nickel and appear "
                        .. "in the 'Kobo Library' folder in the file browser.",
                    book_count,
                    #accessible_books
                ),
            }))
        end,
    }
end

---
-- Adds plugin menu items to the file manager main menu.
-- Creates a hierarchical menu structure for library management and sync settings.
-- Only adds menu items when in file manager (not in reader) and when plugin is active.
-- @param menu_items table: Main menu items table to populate.
function KoboKepubPlugin:addToMainMenu(menu_items)
    if not self.virtual_library:isActive() then
        return
    end

    if self.ui.document then
        return
    end

    menu_items.kobo_kepub = {
        text = _("Kobo Library"),
        sorting_hint = "filemanager_settings",
        separator = true,
        sub_item_table = {
            self:createSyncToggleMenuItem(),
            self:createAutoSyncMenuItem(),
            self:createManualSyncMenuItem(),
            self:createSyncBehaviorMenuItem(),
            self:createRefreshLibraryMenuItem(),
            self:createAboutMenuItem(),
        },
    }
end

---
-- Called when a document is closed.
-- Currently no special handling needed.
function KoboKepubPlugin:onCloseDocument() end

---
-- Called when device is suspended.
-- Currently no special handling needed.
function KoboKepubPlugin:onSuspend() end

---
-- Called when device resumes from suspend.
-- Refreshes virtual library to pick up any changes made in Kobo Nickel.
function KoboKepubPlugin:onResume()
    if not self.virtual_library or not self.virtual_library:isActive() then
        return
    end

    self.virtual_library:refresh()
end

return KoboKepubPlugin
