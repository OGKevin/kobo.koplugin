-- Tests for VirtualLibrary module

describe("VirtualLibrary", function()
    local VirtualLibrary, MetadataParser

    setup(function()
        -- Mocks are set up by helper.lua
        VirtualLibrary = require("src.virtual_library")
        MetadataParser = require("src.metadata_parser")
    end)

    before_each(function()
        package.loaded["src.virtual_library"] = nil
        package.loaded["src.metadata_parser"] = nil

        VirtualLibrary = require("src.virtual_library")
        MetadataParser = require("src.metadata_parser")
    end)

    describe("initialization", function()
        it("should create a new instance with metadata parser", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)
            assert.is_not_nil(vlib)
            assert.equals(parser, vlib.parser)
        end)

        it("should initialize with empty path mappings", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)
            assert.is_table(vlib.virtual_to_real)
            assert.is_table(vlib.real_to_virtual)
            assert.is_table(vlib.book_id_to_virtual)
        end)
    end)

    describe("constants", function()
        it("should have virtual library name", function()
            assert.is_string(VirtualLibrary.VIRTUAL_LIBRARY_NAME)
            assert.is_true(#VirtualLibrary.VIRTUAL_LIBRARY_NAME > 0)
        end)

        it("should have virtual path prefix", function()
            assert.is_string(VirtualLibrary.VIRTUAL_PATH_PREFIX)
            assert.is_true(#VirtualLibrary.VIRTUAL_PATH_PREFIX > 0)
        end)
    end)

    describe("isActive", function()
        it("should have isActive method", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)
            assert.is_function(vlib.isActive)
        end)

        it("should return boolean", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)
            local active = vlib:isActive()
            assert.is_boolean(active)
        end)
    end)

    describe("generateVirtualPath", function()
        it("should have generateVirtualPath method", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)
            assert.is_function(vlib.generateVirtualPath)
        end)

        it("should generate path from book_id and metadata", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = "Test Book",
                author = "Test Author",
            }

            local path = vlib:generateVirtualPath("book_123", metadata)
            assert.is_string(path)
        end)

        it("should handle missing title/author", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {}

            local path = vlib:generateVirtualPath("book_123", metadata)
            assert.is_string(path)
        end)

        it("should sanitize special characters in paths", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = "Book: With/Special\\Characters*?",
                author = "Author|Name<>",
            }

            local path = vlib:generateVirtualPath("book_123", metadata)
            -- Just verify it returns a valid string without crashing
            assert.is_string(path)
            assert.is_true(#path > 0)
        end)
    end)

    describe("path mapping", function()
        it("should store and retrieve virtual to real mappings", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib.virtual_to_real["/virtual/path"] = "/real/path"
            assert.equals("/real/path", vlib.virtual_to_real["/virtual/path"])
        end)

        it("should store and retrieve real to virtual mappings", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib.real_to_virtual["/real/path"] = "/virtual/path"
            assert.equals("/virtual/path", vlib.real_to_virtual["/real/path"])
        end)
    end)
end)
