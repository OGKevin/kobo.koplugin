---
-- Unit tests for FilesystemExt module.

describe("FilesystemExt", function()
    local FilesystemExt
    local VirtualLibrary
    local MetadataParser
    local lfs

    setup(function()
        require("spec/helper")
        FilesystemExt = require("src/filesystem_ext")
        VirtualLibrary = require("src/virtual_library")
        MetadataParser = require("src/metadata_parser")
        lfs = require("libs/libkoreader-lfs")
    end)

    before_each(function()
        -- Clear SQL mock state
        local SQ3 = require("lua-ljsqlite3/init")
        SQ3._clearMockState()

        -- Clear file system state
        lfs._clearFileStates()

        -- Reload modules
        package.loaded["src/filesystem_ext"] = nil
        package.loaded["src/virtual_library"] = nil
        package.loaded["src/metadata_parser"] = nil
        FilesystemExt = require("src/filesystem_ext")
        VirtualLibrary = require("src/virtual_library")
        MetadataParser = require("src/metadata_parser")
        lfs = require("libs/libkoreader-lfs")
    end)

    describe("lfs.attributes interception", function()
        local virtual_library
        local parser
        local filesystem_ext
        local original_lfs_attributes

        before_each(function()
            -- Save original lfs.attributes
            original_lfs_attributes = lfs.attributes

            -- Create virtual library with parser
            parser = MetadataParser:new()
            virtual_library = VirtualLibrary:new(parser)

            -- Initialize FilesystemExt
            filesystem_ext = FilesystemExt
            filesystem_ext:init(virtual_library)

            -- Mock virtual library to be active
            virtual_library.isActive = function()
                return true
            end
        end)

        after_each(function()
            -- Restore original lfs.attributes
            lfs.attributes = original_lfs_attributes
        end)

        it("should return directory attributes for KOBO_VIRTUAL:// root", function()
            -- Apply patches
            filesystem_ext:apply()

            -- Check attributes of virtual library root
            local attr = lfs.attributes("KOBO_VIRTUAL://")

            assert.is_not_nil(attr)
            assert.equals("directory", attr.mode)
        end)

        it("should return mode directly when called with attribute name parameter", function()
            -- Apply patches
            filesystem_ext:apply()

            -- Check mode attribute directly (two-parameter form)
            local mode = lfs.attributes("KOBO_VIRTUAL://", "mode")

            assert.equals("directory", mode)
        end)

        it("should handle KOBO_VIRTUAL:// with trailing slash", function()
            -- Apply patches
            filesystem_ext:apply()

            -- Check both forms work
            local attr1 = lfs.attributes("KOBO_VIRTUAL://")
            local attr2 = lfs.attributes("KOBO_VIRTUAL:///")
            local mode1 = lfs.attributes("KOBO_VIRTUAL://", "mode")
            local mode2 = lfs.attributes("KOBO_VIRTUAL:///", "mode")

            assert.is_not_nil(attr1)
            assert.equals("directory", attr1.mode)
            assert.is_not_nil(attr2)
            assert.equals("directory", attr2.mode)
            assert.equals("directory", mode1)
            assert.equals("directory", mode2)
        end)

        it("should redirect virtual book paths to real paths (case-sensitive)", function()
            -- Mock buildPathMappings to create a mapping
            -- Note: Virtual paths are case-sensitive and must match KOBO_VIRTUAL:// exactly
            virtual_library.virtual_to_real = {
                ["KOBO_VIRTUAL://shelf1/book.kepub.epub"] = "/mnt/onboard/.kobo/kepub/ABC123",
            }

            -- Mock the real file to exist
            lfs._setFileState("/mnt/onboard/.kobo/kepub/ABC123", {
                exists = true,
                attributes = {
                    mode = "file",
                    size = 1024,
                },
            })

            -- Apply patches
            filesystem_ext:apply()

            -- Check attributes of virtual book path
            local attr = lfs.attributes("KOBO_VIRTUAL://shelf1/book.kepub.epub")

            assert.is_not_nil(attr)
            assert.equals("file", attr.mode)
            assert.equals(1024, attr.size)
        end)

        it("should return nil for virtual paths with no real counterpart", function()
            -- Apply patches
            filesystem_ext:apply()

            -- Check attributes of non-existent virtual path
            local attr = lfs.attributes("KOBO_VIRTUAL://nonexistent/book.epub")

            assert.is_nil(attr)
        end)

        it("should not intercept non-virtual paths", function()
            -- Mock a real file
            lfs._setFileState("/mnt/onboard/Books/test.epub", {
                exists = true,
                attributes = {
                    mode = "file",
                    size = 2048,
                },
            })

            -- Apply patches
            filesystem_ext:apply()

            -- Check attributes of real path
            local attr = lfs.attributes("/mnt/onboard/Books/test.epub")

            assert.is_not_nil(attr)
            assert.equals("file", attr.mode)
            assert.equals(2048, attr.size)
        end)
    end)
end)
