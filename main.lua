---
--- Kobo Plugin Entry Point.
--- Provides access to Kobo Nickel library books in KOReader.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local T = require("ffi/util").template
local CacheManager = require("src/lib/drm/cache_manager")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local KoboBluetooth = require("src/kobo_bluetooth")
local MetadataParser = require("src/metadata_parser")
local PathChooser = require("ui/widget/pathchooser")
local ReadingStateSync = require("src/reading_state_sync")
local UIManager = require("ui/uimanager")
local VirtualLibrary = require("src/virtual_library")
local util = require("util")

local SYNC_DIRECTION = {
    PROMPT = 1,
    SILENT = 2,
    NEVER = 3,
}

---
--- Gets localized name for a sync direction.
--- @param direction number: SYNC_DIRECTION constant.
--- @return string: Localized direction name.
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
--- Applies ShowReader extensions for virtual library support.
--- @param virtual_library table: Virtual library instance.
local function applyShowReaderExtensions(virtual_library)
    local ShowReaderExt = require("src/showreader_ext")
    local sr_ext = ShowReaderExt
    sr_ext:init({ virtual_library = virtual_library })
    sr_ext:apply()
end

---
--- Applies filesystem extensions for virtual path support.
--- @param virtual_library table: Virtual library instance.
local function applyFilesystemExtensions(virtual_library)
    local FilesystemExt = require("src/filesystem_ext")
    local fs_ext = FilesystemExt
    fs_ext:init(virtual_library)
    fs_ext:apply()
end

---
--- Applies document provider extensions for kepub files.
--- @param virtual_library table: Virtual library instance.
local function applyDocumentExtensions(virtual_library)
    local DocumentRegistry = require("document/documentregistry")
    local DocumentExt = require("src/document_ext")
    local doc_ext = DocumentExt
    doc_ext:init(virtual_library)
    doc_ext:apply(DocumentRegistry)
end

---
--- Applies DocSettings extensions for sidecar file support.
--- @param virtual_library table: Virtual library instance.
local function applyDocSettingsExtensions(virtual_library)
    local DocSettings = require("docsettings")
    local DocSettingsExt = require("src/docsettings_ext")
    local ds_ext = DocSettingsExt
    ds_ext:init(virtual_library)
    ds_ext:apply(DocSettings)
end

---
--- Applies FileChooser extensions for virtual library.
--- @param virtual_library table: Virtual library instance.
--- @param reading_state_sync table: Reading state sync instance.
local function applyFileChooserExtensions(virtual_library, reading_state_sync)
    local FileChooser = require("ui/widget/filechooser")
    local FileChooserExt = require("src/filechooser_ext")
    local fc_ext = FileChooserExt
    fc_ext:init(virtual_library, reading_state_sync)
    fc_ext:apply(FileChooser)
end

---
--- Applies PathChooser extensions for bypassing virtual library.
--- @param virtual_library table: Virtual library instance.
local function applyPathChooserExtensions(virtual_library)
    local PathChooserExt = require("src/pathchooser_ext")
    local pc_ext = PathChooserExt
    pc_ext:init({ virtual_library = virtual_library })
    pc_ext:apply()
end

---
--- Applies ReaderPageMap extensions for kepub compatibility.
local function applyReaderPageMapExtensions()
    local ok_rpm, ReaderPageMap = pcall(require, "apps/reader/modules/readerpagemap")
    if not ok_rpm or not ReaderPageMap then
        return
    end

    local ReaderPageMapExt = require("src/readerpagemap_ext")
    local rpm_ext = ReaderPageMapExt:new()
    rpm_ext:apply(ReaderPageMap)
    logger.info("KoboPlugin: ReaderPageMap patches applied for kepub compatibility")
end

---
--- Applies ReaderUI extensions for kepub navigation.
--- @param virtual_library table: Virtual library instance.
--- @param reading_state_sync table: Reading state sync instance.
local function applyReaderUIExtensions(virtual_library, reading_state_sync)
    local ok_rui, ReaderUI = pcall(require, "apps/reader/readerui")
    if not ok_rui or not ReaderUI then
        return
    end

    local ReaderUIExt = require("src/readerui_ext")
    local rui_ext = ReaderUIExt
    rui_ext:init(virtual_library, reading_state_sync)
    rui_ext:apply(ReaderUI)
    logger.info("KoboPlugin: ReaderUI patches applied for kepub navigation")
end

local metadata_parser = MetadataParser:new()
local virtual_library = VirtualLibrary:new(metadata_parser)
local reading_state_sync = ReadingStateSync:new(metadata_parser)

local default_settings = {
    enable_virtual_library = true,
    sync_reading_state = false,
    enable_auto_sync = false,
    enable_sync_from_kobo = false,
    enable_sync_to_kobo = true,
    sync_from_kobo_newer = SYNC_DIRECTION.PROMPT,
    sync_from_kobo_older = SYNC_DIRECTION.NEVER,
    sync_to_kobo_newer = SYNC_DIRECTION.SILENT,
    sync_to_kobo_older = SYNC_DIRECTION.NEVER,
    paired_devices = {},
    enable_bluetooth_auto_resume = false,
    enable_auto_detection_polling = false,
    disable_auto_detection_after_connect = true,
    enable_auto_connect_polling = false,
    disable_auto_connect_after_connect = true,
    dismiss_widgets_on_button = true,
    enable_drm_decryption = false,
    drm_cache_dir = "/tmp/kobo.koplugin.cache",
}

local plugin_settings = G_reader_settings:readSetting("kobo_plugin") or default_settings
local enable_virtual_library = plugin_settings.enable_virtual_library ~= false

if virtual_library:isActive() and enable_virtual_library then
    logger.info("KoboPlugin: virtual library is active, applying patches")
    applyShowReaderExtensions(virtual_library)
    applyFilesystemExtensions(virtual_library)
    applyDocumentExtensions(virtual_library)
    applyDocSettingsExtensions(virtual_library)
    applyFileChooserExtensions(virtual_library, reading_state_sync)
    applyPathChooserExtensions(virtual_library)
    applyReaderPageMapExtensions()
    applyReaderUIExtensions(virtual_library, reading_state_sync)
end

local KoboPlugin = WidgetContainer:extend({
    name = "kobo_plugin",
    is_doc_only = false,
    default_settings = default_settings,
})

--- The way KOReader works, when UI is changed from reader to filemanager,
--- init is called again. To avoid having n times KoboBluetooth instances
--- that are managing the stack, we use a singleton pattern here.
---
--- @type KoboBluetooth instance cache.
local kobo_bluetooth_instance = nil

--- Initializes the plugin and loads settings.
function KoboPlugin:init()
    self.metadata_parser = metadata_parser
    self.virtual_library = virtual_library
    self.reading_state_sync = reading_state_sync

    self:loadSettings()

    self.metadata_parser:setPlugin(self)

    -- Use singleton pattern to avoid multiple KoboBluetooth instances
    -- when KOReader switches between reader and file manager
    if not kobo_bluetooth_instance then
        kobo_bluetooth_instance = KoboBluetooth:create()
    end

    self.kobo_bluetooth = kobo_bluetooth_instance

    -- Add Bluetooth InputContainer to widget hierarchy so it can receive key events
    -- This is essential for Bluetooth key bindings to work
    table.insert(self, self.kobo_bluetooth)

    self.kobo_bluetooth:initWithPlugin(self)

    self.reading_state_sync:setPlugin(self, SYNC_DIRECTION)
    self:addMenuItems()
    self:onDispatcherRegisterActions()
end

---
--- Loads plugin settings from persistent storage.
function KoboPlugin:loadSettings()
    self.settings = G_reader_settings:readSetting("kobo_plugin") or {}

    for key, default_value in pairs(self.default_settings) do
        if self.settings[key] == nil then
            self.settings[key] = default_value
        end
    end

    self.reading_state_sync:setEnabled(self.settings.sync_reading_state)
end

---
--- Saves plugin settings to persistent storage.
function KoboPlugin:saveSettings()
    self.settings.sync_reading_state = self.reading_state_sync:isEnabled()
    G_reader_settings:saveSetting("kobo_plugin", self.settings)
    G_reader_settings:flush()
end

---
--- Registers menu items with the file browser.
function KoboPlugin:addMenuItems()
    self.ui.menu:registerToMainMenu(self)
end

---
--- Creates virtual library enable/disable menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createVirtualLibraryToggleMenuItem()
    return {
        text = _("Enable virtual library"),
        help_text = _(
            "When enabled, access your Kobo library from within KOReader. When disabled, the virtual library will not be shown."
        ),
        checked_func = function()
            return self.settings.enable_virtual_library
        end,
        callback = function()
            self.settings.enable_virtual_library = not self.settings.enable_virtual_library
            self:saveSettings()

            UIManager:askForRestart()
        end,
        separator = true,
    }
end

---
--- Creates sync enable/disable menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createSyncToggleMenuItem()
    return {
        text = _("Sync reading state with Kobo"),
        checked_func = function()
            return self.reading_state_sync:isEnabled()
        end,
        callback = function()
            local enabled = not self.reading_state_sync:isEnabled()
            self.reading_state_sync:setEnabled(enabled)
            self:saveSettings()

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
--- Creates auto-sync menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createAutoSyncMenuItem()
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
--- Creates manual sync menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createManualSyncMenuItem()
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
--- Creates sync direction choice submenu.
--- @param direction_key string: Settings key ('sync_from_kobo_newer', etc.).
--- @param label string: Menu label.
--- @param help_text string: Help text for the menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createSyncDirectionChoiceMenu(direction_key, label, help_text)
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
--- Creates FROM Kobo sync settings submenu.
--- @return table: Menu item configuration.
function KoboPlugin:createFromKoboSyncSettingsMenu()
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
--- Creates FROM KOReader sync settings submenu.
--- @return table: Menu item configuration.
function KoboPlugin:createFromKOReaderSyncSettingsMenu()
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
--- Creates sync behavior menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createSyncBehaviorMenuItem()
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
--- Creates refresh library menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createRefreshLibraryMenuItem()
    return {
        text = _("Refresh library"),
        callback = function()
            self.virtual_library:refresh()

            UIManager:show(InfoMessage:new({
                text = _("Kobo library refreshed"),
                timeout = 2,
            }))
        end,
    }
end

---
--- Creates DRM decryption enable/disable menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createDrmDecryptionMenuItem()
    return {
        text = _("Enable DRM decryption"),
        help_text = _(
            "When enabled, encrypted books will be automatically decrypted and made accessible. Decrypted books are cached to avoid re-decrypting on each access."
        ),
        checked_func = function()
            return self.settings.enable_drm_decryption
        end,
        callback = function()
            self.settings.enable_drm_decryption = not self.settings.enable_drm_decryption
            self:saveSettings()

            self.virtual_library:refresh()
        end,
        separator = true,
    }
end

---
--- Creates clear DRM cache menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createClearDrmCacheMenuItem()
    return {
        text = _("Clear decrypted book cache"),
        help_text = _("Removes all cached decrypted books. Books will be re-decrypted on next access."),
        enabled_func = function()
            return self.settings.enable_drm_decryption
        end,
        callback = function()
            local cache_dir = self.settings.drm_cache_dir

            local stats = CacheManager:getCacheStats(cache_dir)

            if stats.count == 0 then
                UIManager:show(InfoMessage:new({
                    text = _("Cache is already empty"),
                    timeout = 2,
                }))

                return
            end

            UIManager:show(ConfirmBox:new({
                text = T(_("Clear %1 decrypted books (%2)?"), stats.count, util.getFriendlySize(stats.total_size)),
                ok_text = _("Clear cache"),
                ok_callback = function()
                    local deleted, errors = CacheManager:clearAll(cache_dir)

                    UIManager:show(InfoMessage:new({
                        text = T(_("Cleared %1 books from cache"), deleted),
                        timeout = 3,
                    }))

                    if errors > 0 then
                        logger.warn("KoboPlugin: Failed to clear", errors, "books from cache")
                    end

                    self.virtual_library:refresh()
                end,
            }))
        end,
        separator = true,
    }
end

---
--- Creates cache directory picker menu item.
--- @return table: Menu item configuration.
function KoboPlugin:createDrmCacheDirectoryMenuItem()
    return {
        text = _("Cache directory"),
        help_text = _(
            string.format(
                "Select the directory where decrypted books will be cached. Default is %s",
                self.settings.drm_cache_dir
            )
        ),
        enabled_func = function()
            return self.settings.enable_drm_decryption
        end,
        callback = function()
            local cache_dir = self.settings.drm_cache_dir

            local path_chooser = PathChooser:new({
                title = _("Select cache directory"),
                path = cache_dir,
                bypass_virtual_library = true,
                onConfirm = function(path)
                    if not path or path == "" then
                        return
                    end

                    self.settings.drm_cache_dir = path
                    self:saveSettings()

                    UIManager:show(InfoMessage:new({
                        text = T(_("Cache directory set to:\n%1"), path),
                        timeout = 3,
                    }))
                end,
            })
            UIManager:show(path_chooser)
        end,
    }
end

---
--- Creates DRM settings submenu.
--- @return table: Menu item configuration with submenu.
function KoboPlugin:createDrmSettingsMenu()
    return {
        text = _("DRM Settings"),
        sub_item_table = {
            self:createDrmDecryptionMenuItem(),
            self:createDrmCacheDirectoryMenuItem(),
            self:createClearDrmCacheMenuItem(),
        },
        separator = true,
    }
end

---
--- Creates about menu item showing library statistics.
--- @return table: Menu item configuration.
function KoboPlugin:createAboutMenuItem()
    return {
        text = _("About Kobo Library"),
        callback = function()
            local parser = self.metadata_parser
            local total_in_db = parser:getBookCount()
            local kepub_files = parser:scanKepubDirectory()
            local accessible_books = parser:getAccessibleBooks()

            local encrypted_count = 0

            for _, book in ipairs(accessible_books) do
                if book.is_encrypted then
                    encrypted_count = encrypted_count + 1
                end
            end

            UIManager:show(InfoMessage:new({
                text = string.format(
                    "Kobo Library\n\n"
                        .. "Books in database: %d\n"
                        .. "Books in kepub folder: %d\n"
                        .. "Unencrypted books: %d\n"
                        .. "Encrypted books: %d\n"
                        .. "Accessible books: %d\n\n"
                        .. "Books are synced from Kobo Nickel and appear "
                        .. "in the 'Kobo Library' folder in the file browser.",
                    total_in_db,
                    #kepub_files,
                    #accessible_books - encrypted_count,
                    encrypted_count,
                    self.settings.enable_drm_decryption and #accessible_books or #accessible_books - encrypted_count
                ),
            }))
        end,
    }
end

---
--- Adds plugin menu items to the file manager main menu.
--- Creates a hierarchical menu structure for library management and sync settings.
--- Only adds menu items when in file manager (not in reader) and when plugin is active.
--- @param menu_items table: Main menu items table to populate.
function KoboPlugin:addToMainMenu(menu_items)
    -- Add Bluetooth menu item (independent of virtual library, works in reader too)
    self.kobo_bluetooth:addToMainMenu(menu_items)

    if not self.virtual_library:isActive() then
        return
    end

    if self.ui.document then
        return
    end

    local sub_item_table = {
        self:createVirtualLibraryToggleMenuItem(),
    }

    if self.settings.enable_virtual_library then
        table.insert(sub_item_table, self:createSyncToggleMenuItem())
        table.insert(sub_item_table, self:createAutoSyncMenuItem())
        table.insert(sub_item_table, self:createManualSyncMenuItem())
        table.insert(sub_item_table, self:createSyncBehaviorMenuItem())
        table.insert(sub_item_table, self:createDrmSettingsMenu())
        table.insert(sub_item_table, self:createRefreshLibraryMenuItem())
    end

    table.insert(sub_item_table, self:createAboutMenuItem())

    menu_items.kobo_plugin = {
        text = _("Kobo Library"),
        sorting_hint = "filemanager_settings",
        separator = true,
        sub_item_table = sub_item_table,
    }
end

---
--- Called when a document is closed.
--- Currently no special handling needed.
function KoboPlugin:onCloseDocument() end

---
--- Called when device resumes from suspend.
function KoboPlugin:onResume() end

---
--- Registers dispatcher actions for connecting to paired Bluetooth devices.
function KoboPlugin:onDispatcherRegisterActions()
    if not self.kobo_bluetooth then
        return
    end

    self.kobo_bluetooth:registerPairedDevicesWithDispatcher()
    self.kobo_bluetooth:registerBluetoothActionsWithDispatcher()
end

return KoboPlugin
