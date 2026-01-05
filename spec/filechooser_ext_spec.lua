---
-- Unit tests for FileChooserExt module.

describe("FileChooserExt", function()
    local FileChooserExt
    local VirtualLibrary
    local MetadataParser

    setup(function()
        require("spec/helper")
        FileChooserExt = require("src/filechooser_ext")
        VirtualLibrary = require("src/virtual_library")
        MetadataParser = require("src/metadata_parser")
    end)

    before_each(function()
        -- Clear SQL mock state
        local SQ3 = require("lua-ljsqlite3/init")
        SQ3._clearMockState()

        -- Clear file system state
        local lfs = require("libs/libkoreader-lfs")
        lfs._clearFileStates()

        -- Reload modules
        package.loaded["src/filechooser_ext"] = nil
        package.loaded["src/virtual_library"] = nil
        package.loaded["src/metadata_parser"] = nil
        FileChooserExt = require("src/filechooser_ext")
        VirtualLibrary = require("src/virtual_library")
        MetadataParser = require("src/metadata_parser")

        -- Reset G_reader_settings
        G_reader_settings._settings = {}
    end)

    describe("createBackEntry via showKoboVirtualLibrary", function()
        local virtual_library
        local parser
        local mock_file_chooser

        before_each(function()
            -- Create virtual library with parser
            parser = MetadataParser:new()
            virtual_library = VirtualLibrary:new(parser)

            -- Initialize FileChooserExt
            FileChooserExt:init(virtual_library, nil)

            -- Mock FileChooser object
            mock_file_chooser = {
                path = "/some/path",
                switchItemTable = function(self, arg1, book_entries, arg3, arg4, arg5)
                    self.last_book_entries = book_entries
                end,
                init = function() end,
                changeToPath = function() end,
                refreshPath = function() end,
                genItemTable = function()
                    return {}
                end,
                onMenuSelect = function()
                    return false
                end,
            }

            -- Mock Device
            local Device = require("device")
            Device.home_dir = "/mnt/onboard"

            -- Mock virtual library to be active
            virtual_library.isActive = function()
                return true
            end

            -- Mock buildPathMappings and getBookEntries
            virtual_library.buildPathMappings = function() end
            virtual_library.getBookEntries = function()
                return {
                    { text = "Test Book 1", path = "/test/book1.epub" },
                }
            end
        end)

        it("should use Device.home_dir when home_dir is set to real kepub path", function()
            -- Set home_dir to real kepub path
            G_reader_settings:saveSetting("home_dir", "/mnt/onboard/.kobo/kepub")

            -- Apply patches
            FileChooserExt:apply(mock_file_chooser)

            -- Call showKoboVirtualLibrary
            mock_file_chooser:showKoboVirtualLibrary()

            -- Check that back entry was created with Device.home_dir
            local back_entry = mock_file_chooser.last_book_entries[1]
            assert.is_not_nil(back_entry)
            assert.is_true(back_entry.is_go_up)
            assert.equals("/mnt/onboard", back_entry.path)
        end)

        it("should use Device.home_dir when home_dir is set to virtual path prefix", function()
            -- Set home_dir to virtual path prefix
            G_reader_settings:saveSetting("home_dir", "KOBO_VIRTUAL://")

            -- Apply patches
            FileChooserExt:apply(mock_file_chooser)

            -- Call showKoboVirtualLibrary
            mock_file_chooser:showKoboVirtualLibrary()

            -- Check that back entry was created with Device.home_dir
            local back_entry = mock_file_chooser.last_book_entries[1]
            assert.is_not_nil(back_entry)
            assert.is_true(back_entry.is_go_up)
            assert.equals("/mnt/onboard", back_entry.path)
        end)

        it("should use Device.home_dir when home_dir is subpath of virtual path prefix", function()
            -- Set home_dir to a subpath inside the virtual library (e.g., a specific book path)
            G_reader_settings:saveSetting("home_dir", "KOBO_VIRTUAL://BOOKID123/somebook.epub")

            -- Apply patches
            FileChooserExt:apply(mock_file_chooser)

            -- Call showKoboVirtualLibrary
            mock_file_chooser:showKoboVirtualLibrary()

            -- Check that back entry was created with Device.home_dir
            local back_entry = mock_file_chooser.last_book_entries[1]
            assert.is_not_nil(back_entry)
            assert.is_true(back_entry.is_go_up)
            assert.equals("/mnt/onboard", back_entry.path)
        end)

        it("should use Device.home_dir when home_dir is subpath of kepub directory", function()
            -- Set home_dir to subpath of kepub directory
            G_reader_settings:saveSetting("home_dir", "/mnt/onboard/.kobo/kepub/subfolder")

            -- Apply patches
            FileChooserExt:apply(mock_file_chooser)

            -- Call showKoboVirtualLibrary
            mock_file_chooser:showKoboVirtualLibrary()

            -- Check that back entry was created with Device.home_dir
            local back_entry = mock_file_chooser.last_book_entries[1]
            assert.is_not_nil(back_entry)
            assert.is_true(back_entry.is_go_up)
            assert.equals("/mnt/onboard", back_entry.path)
        end)

        it("should use custom home_dir when it's not related to kepub or virtual path", function()
            -- Set home_dir to a normal directory
            G_reader_settings:saveSetting("home_dir", "/mnt/onboard/Books")

            -- Apply patches
            FileChooserExt:apply(mock_file_chooser)

            -- Call showKoboVirtualLibrary
            mock_file_chooser:showKoboVirtualLibrary()

            -- Check that back entry uses the custom home_dir
            local back_entry = mock_file_chooser.last_book_entries[1]
            assert.is_not_nil(back_entry)
            assert.is_true(back_entry.is_go_up)
            assert.equals("/mnt/onboard/Books", back_entry.path)
        end)

        it("should use Device.home_dir when home_dir is not set", function()
            -- Don't set home_dir
            G_reader_settings._settings = {}

            -- Apply patches
            FileChooserExt:apply(mock_file_chooser)

            -- Call showKoboVirtualLibrary
            mock_file_chooser:showKoboVirtualLibrary()

            -- Check that back entry uses Device.home_dir as fallback
            local back_entry = mock_file_chooser.last_book_entries[1]
            assert.is_not_nil(back_entry)
            assert.is_true(back_entry.is_go_up)
            assert.equals("/mnt/onboard", back_entry.path)
        end)

        it("should use root as fallback when Device.home_dir is not set", function()
            -- Mock Device with no home_dir
            local Device = require("device")
            Device.home_dir = nil

            -- Don't set home_dir
            G_reader_settings._settings = {}

            -- Apply patches
            FileChooserExt:apply(mock_file_chooser)

            -- Call showKoboVirtualLibrary
            mock_file_chooser:showKoboVirtualLibrary()

            -- Check that back entry uses root as fallback
            local back_entry = mock_file_chooser.last_book_entries[1]
            assert.is_not_nil(back_entry)
            assert.is_true(back_entry.is_go_up)
            assert.equals("/", back_entry.path)
        end)
    end)

    describe("changeToPath interception", function()
        local virtual_library
        local parser
        local MockFileChooser
        local show_virtual_called

        before_each(function()
            -- Create virtual library with parser
            parser = MetadataParser:new()
            virtual_library = VirtualLibrary:new(parser)

            -- Initialize FileChooserExt
            FileChooserExt:init(virtual_library, nil)

            -- Reset call tracking
            show_virtual_called = false

            -- Mock FileChooser class
            MockFileChooser = {
                init = function() end,
                changeToPath = function() end,
                refreshPath = function() end,
                genItemTable = function()
                    return {}
                end,
                onMenuSelect = function()
                    return false
                end,
            }

            -- Mock Device
            local Device = require("device")
            Device.home_dir = "/mnt/onboard"

            -- Mock virtual library to be active
            virtual_library.isActive = function()
                return true
            end
        end)

        it("should intercept navigation to KOBO_VIRTUAL:// path", function()
            -- Apply patches to the class
            FileChooserExt:apply(MockFileChooser)

            -- Create instance and set showKoboVirtualLibrary
            local instance = { path = "/some/path" }
            setmetatable(instance, { __index = MockFileChooser })
            instance.showKoboVirtualLibrary = function()
                show_virtual_called = true
            end

            -- Try to navigate to virtual path
            MockFileChooser.changeToPath(instance, "KOBO_VIRTUAL://")

            -- Check that showKoboVirtualLibrary was called
            assert.is_true(show_virtual_called)
        end)

        it("should intercept navigation to KOBO_VIRTUAL:// subpath", function()
            -- Reset tracking
            show_virtual_called = false

            -- Apply patches to the class
            FileChooserExt:apply(MockFileChooser)

            -- Create instance and set showKoboVirtualLibrary
            local instance = { path = "/some/path" }
            setmetatable(instance, { __index = MockFileChooser })
            instance.showKoboVirtualLibrary = function()
                show_virtual_called = true
            end

            -- Try to navigate to virtual subpath
            MockFileChooser.changeToPath(instance, "KOBO_VIRTUAL://BOOKID123/somebook.epub")

            -- Check that showKoboVirtualLibrary was called
            assert.is_true(show_virtual_called)
        end)

        it("should intercept navigation to real kepub directory", function()
            -- Reset tracking
            show_virtual_called = false

            -- Apply patches to the class
            FileChooserExt:apply(MockFileChooser)

            -- Create instance and set showKoboVirtualLibrary
            local instance = { path = "/some/path" }
            setmetatable(instance, { __index = MockFileChooser })
            instance.showKoboVirtualLibrary = function()
                show_virtual_called = true
            end

            -- Try to navigate to real kepub path
            MockFileChooser.changeToPath(instance, "/mnt/onboard/.kobo/kepub")

            -- Check that showKoboVirtualLibrary was called
            assert.is_true(show_virtual_called)
        end)
    end)
end)
