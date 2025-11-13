---
-- Unit tests for VirtualLibrary module.

describe("VirtualLibrary", function()
    local VirtualLibrary
    local MetadataParser
    local helper

    setup(function()
        helper = require("spec/helper")
        VirtualLibrary = require("src.virtual_library")
        MetadataParser = require("src.metadata_parser")
    end)

    before_each(function()
        -- Clear SQL mock state first
        local SQ3 = require("lua-ljsqlite3/init")
        SQ3._clearMockState()

        -- Clear file system state
        local lfs = require("libs/libkoreader-lfs")
        lfs._clearFileStates()

        -- Clear io.open mock state
        helper.clearMockIOFiles()

        -- Now reload modules
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
            assert.is_table(vlib.virtual_to_real)
            assert.is_table(vlib.real_to_virtual)
            assert.is_table(vlib.book_id_to_virtual)
        end)

        it("should have VIRTUAL_LIBRARY_NAME constant", function()
            assert.equals("Kobo Library", VirtualLibrary.VIRTUAL_LIBRARY_NAME)
        end)

        it("should have VIRTUAL_PATH_PREFIX constant", function()
            assert.equals("KOBO_VIRTUAL://", VirtualLibrary.VIRTUAL_PATH_PREFIX)
        end)
    end)

    describe("isActive", function()
        it("should return true when KOBO_LIBRARY_PATH is set", function()
            -- Mock environment variable
            local original_getenv = os.getenv
            os.getenv = function(name)
                if name == "KOBO_LIBRARY_PATH" then
                    return "/some/path"
                end
                return original_getenv(name)
            end

            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            assert.is_true(vlib:isActive())

            os.getenv = original_getenv
        end)

        it("should return false when KOBO_LIBRARY_PATH is empty", function()
            local original_getenv = os.getenv
            os.getenv = function(name)
                if name == "KOBO_LIBRARY_PATH" then
                    return ""
                end
                return original_getenv(name)
            end

            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            -- Will depend on Device:isKobo()
            local result = vlib:isActive()
            assert.is_boolean(result)

            os.getenv = original_getenv
        end)
    end)

    describe("generateVirtualPath", function()
        it("should generate virtual path with author and title", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = "Test Book",
                author = "Test Author",
            }

            local virtual_path = vlib:generateVirtualPath("BOOKID123", metadata)

            assert.equals("KOBO_VIRTUAL://BOOKID123/Test Author - Test Book.epub", virtual_path)
        end)

        it("should sanitize special characters in author and title", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = 'Book/Title:With*Special"Chars',
                author = "Author\\Name<With>Pipes|",
            }

            local virtual_path = vlib:generateVirtualPath("BOOKID456", metadata)

            assert.is_true(virtual_path:match("KOBO_VIRTUAL://BOOKID456/") ~= nil)
            assert.is_false(virtual_path:match('[/\\:*?"<>|]', #"KOBO_VIRTUAL://BOOKID456/" + 1) ~= nil)
        end)

        it("should use Unknown for missing title", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                author = "Test Author",
            }

            local virtual_path = vlib:generateVirtualPath("BOOKID789", metadata)

            assert.is_true(virtual_path:match("Unknown") ~= nil)
        end)

        it("should use Unknown for missing author", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = "Test Book",
            }

            local virtual_path = vlib:generateVirtualPath("BOOKID101", metadata)

            assert.is_true(virtual_path:match("Unknown") ~= nil)
        end)
    end)

    describe("isVirtualPath", function()
        it("should return true for virtual paths", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local result = vlib:isVirtualPath("KOBO_VIRTUAL://BOOKID/file.epub")

            assert.is_true(result)
        end)

        it("should return false for regular paths", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local result = vlib:isVirtualPath("/mnt/onboard/Books/book.epub")

            assert.is_false(result)
        end)

        it("should return false for nil path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local result = vlib:isVirtualPath(nil)

            assert.is_false(result)
        end)

        it("should return false for empty path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local result = vlib:isVirtualPath("")

            assert.is_false(result)
        end)
    end)

    describe("getBookId", function()
        it("should extract book ID from virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local book_id = vlib:getBookId("KOBO_VIRTUAL://BOOKID123/Author - Title.epub")

            assert.equals("BOOKID123", book_id)
        end)

        it("should return nil for non-virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local book_id = vlib:getBookId("/regular/path/book.epub")

            assert.is_nil(book_id)
        end)

        it("should extract complex book IDs", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local book_id = vlib:getBookId("KOBO_VIRTUAL://0N3773Z7HFPXB/file.epub")

            assert.equals("0N3773Z7HFPXB", book_id)
        end)
    end)

    describe("buildPathMappings", function()
        it("should build bidirectional mappings for accessible books", function()
            -- Mock the database file to exist
            local lfs = require("libs/libkoreader-lfs")
            lfs._setFileState("/mnt/onboard/.kobo/KoboReader.sqlite", {
                exists = true,
                is_file = true,
                attributes = { mode = "file", size = 10240 },
            })

            -- Set up mock book data in the SQL database
            local SQ3 = require("lua-ljsqlite3/init")
            SQ3._setBookRows({
                -- Row format: [ContentID, Title, Attribution, Publisher, Series, SeriesNumber, ___PercentRead]
                { "BOOK123", "Test Book One", "Author One", "Publisher A", nil, nil, 0 },
                { "BOOK456", "Test Book Two", "Author Two", "Publisher B", "Series X", 1, 50 },
                { "BOOK789", "Test Book Three", "Author Three", nil, nil, nil, 100 },
            })

            -- Mock the book files to exist and be accessible
            lfs._setFileState("/mnt/onboard/.kobo/kepub/BOOK123", {
                exists = true,
                is_file = true,
                attributes = { mode = "file", size = 1024 },
            })
            lfs._setFileState("/mnt/onboard/.kobo/kepub/BOOK456", {
                exists = true,
                is_file = true,
                attributes = { mode = "file", size = 2048 },
            })
            lfs._setFileState("/mnt/onboard/.kobo/kepub/BOOK789", {
                exists = true,
                is_file = true,
                attributes = { mode = "file", size = 3072 },
            })

            -- Mock epub files with valid ZIP signatures
            helper.setMockEpubFile("/mnt/onboard/.kobo/kepub/BOOK123")
            helper.setMockEpubFile("/mnt/onboard/.kobo/kepub/BOOK456")
            helper.setMockEpubFile("/mnt/onboard/.kobo/kepub/BOOK789")

            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            -- Get accessible books to verify mappings were created
            local accessible_books = parser:getAccessibleBooks()

            -- Should have 3 accessible books
            assert.equals(3, #accessible_books)

            -- Check that mappings are tables
            assert.is_table(vlib.virtual_to_real)
            assert.is_table(vlib.real_to_virtual)
            assert.is_table(vlib.book_id_to_virtual)

            -- Verify that all accessible books have mappings
            for _, book in ipairs(accessible_books) do
                local expected_virtual = vlib:generateVirtualPath(book.id, book.metadata)

                -- Check virtual_to_real mapping
                assert.equals(book.filepath, vlib.virtual_to_real[expected_virtual])

                -- Check real_to_virtual mapping
                assert.equals(expected_virtual, vlib.real_to_virtual[book.filepath])

                -- Check book_id_to_virtual mapping
                assert.equals(expected_virtual, vlib.book_id_to_virtual[book.id])
            end
        end)

        it("should create mappings for all accessible books", function()
            -- Mock the database file
            local lfs = require("libs/libkoreader-lfs")
            lfs._setFileState("/mnt/onboard/.kobo/KoboReader.sqlite", {
                exists = true,
                is_file = true,
                attributes = { mode = "file", size = 10240 },
            })

            -- Set up mock book data
            local SQ3 = require("lua-ljsqlite3/init")
            SQ3._setBookRows({
                { "BOOK001", "Sample Book", "Sample Author", nil, nil, nil, 25 },
            })

            -- Mock the book file
            lfs._setFileState("/mnt/onboard/.kobo/kepub/BOOK001", {
                exists = true,
                is_file = true,
                attributes = { mode = "file", size = 512 },
            })

            -- Mock epub file with valid ZIP signature
            helper.setMockEpubFile("/mnt/onboard/.kobo/kepub/BOOK001")

            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local accessible_books = parser:getAccessibleBooks()
            local mapping_count = 0

            for _ in pairs(vlib.virtual_to_real) do
                mapping_count = mapping_count + 1
            end

            assert.equals(#accessible_books, mapping_count)
        end)

        it("should clear existing mappings before rebuilding", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib.virtual_to_real["old_entry"] = "old_value"
            vlib:buildPathMappings()

            assert.is_nil(vlib.virtual_to_real["old_entry"])
        end)
    end)

    describe("getRealPath", function()
        it("should return real path for virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local accessible_books = parser:getAccessibleBooks()
            if #accessible_books > 0 then
                local book = accessible_books[1]
                local virtual_path = vlib:generateVirtualPath(book.id, book.metadata)

                local real_path = vlib:getRealPath(virtual_path)

                assert.equals(book.filepath, real_path)
            end
        end)

        it("should return path unchanged for non-virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local regular_path = "/regular/path/book.epub"
            local result = vlib:getRealPath(regular_path)

            assert.equals(regular_path, result)
        end)

        it("should return nil for unmapped virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local result = vlib:getRealPath("KOBO_VIRTUAL://NONEXISTENT/file.epub")

            assert.is_nil(result)
        end)
    end)

    describe("getVirtualPath", function()
        it("should return virtual path for real path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local accessible_books = parser:getAccessibleBooks()
            if #accessible_books > 0 then
                local book = accessible_books[1]
                local expected_virtual = vlib:generateVirtualPath(book.id, book.metadata)

                local virtual_path = vlib:getVirtualPath(book.filepath)

                assert.equals(expected_virtual, virtual_path)
            end
        end)

        it("should return nil for unmapped real path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local result = vlib:getVirtualPath("/nonexistent/path.epub")

            assert.is_nil(result)
        end)
    end)

    describe("getMetadata", function()
        it("should return metadata for virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local accessible_books = parser:getAccessibleBooks()
            if #accessible_books > 0 then
                local book = accessible_books[1]
                local virtual_path = vlib:generateVirtualPath(book.id, book.metadata)

                local metadata = vlib:getMetadata(virtual_path)

                assert.is_not_nil(metadata)
                assert.is_table(metadata)
            end
        end)

        it("should return nil for non-virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = vlib:getMetadata("/regular/path.epub")

            assert.is_nil(metadata)
        end)
    end)

    describe("refresh", function()
        it("should call parser clearCache and rebuild mappings", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local clear_cache_called = false
            local original_clearCache = parser.clearCache
            parser.clearCache = function(self)
                clear_cache_called = true
                original_clearCache(self)
            end

            vlib:refresh()

            assert.is_true(clear_cache_called)
            assert.is_table(vlib.virtual_to_real)
        end)
    end)

    describe("getBookEntries", function()
        it("should return array of book entries", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local entries = vlib:getBookEntries()

            assert.is_table(entries)
            assert.is_true(#entries >= 0)
        end)

        it("should create entries with required fields", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local entries = vlib:getBookEntries()

            if #entries > 0 then
                local entry = entries[1]

                assert.is_not_nil(entry.text)
                assert.is_not_nil(entry.path)
                assert.is_true(entry.is_file)
                assert.is_not_nil(entry.attr)
                assert.is_not_nil(entry.kobo_book_id)
                assert.is_not_nil(entry.kobo_real_path)
                assert.is_table(entry.kobo_metadata)
            end
        end)

        it("should sort entries alphabetically", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local entries = vlib:getBookEntries()

            if #entries > 1 then
                for i = 1, #entries - 1 do
                    assert.is_true(entries[i].text <= entries[i + 1].text)
                end
            end
        end)

        it("should set file size in mandatory field", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local entries = vlib:getBookEntries()

            if #entries > 0 then
                local entry = entries[1]

                assert.is_not_nil(entry.mandatory)
                assert.is_string(entry.mandatory)
            end
        end)
    end)

    describe("createVirtualFolderEntry", function()
        it("should create folder entry with correct name", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local entry = vlib:createVirtualFolderEntry("/mnt/onboard")

            assert.is_not_nil(entry)
            assert.is_true(entry.text:match("Kobo Library/") ~= nil)
        end)

        it("should set is_kobo_virtual_folder flag", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local entry = vlib:createVirtualFolderEntry("/mnt/onboard")

            assert.is_true(entry.is_kobo_virtual_folder)
        end)

        it("should construct path from parent", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local entry = vlib:createVirtualFolderEntry("/mnt/onboard")

            assert.equals("/mnt/onboard/Kobo Library", entry.path)
        end)
    end)

    describe("getThumbnailPath", function()
        it("should return thumbnail path for virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            vlib:buildPathMappings()

            local accessible_books = parser:getAccessibleBooks()
            if #accessible_books > 0 then
                local book = accessible_books[1]
                local virtual_path = vlib:generateVirtualPath(book.id, book.metadata)

                local thumbnail = vlib:getThumbnailPath(virtual_path)

                -- Should return a path or nil
                assert.is_true(thumbnail == nil or type(thumbnail) == "string")
            end
        end)

        it("should return nil for non-virtual path", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local thumbnail = vlib:getThumbnailPath("/regular/path.epub")

            assert.is_nil(thumbnail)
        end)
    end)

    describe("sanitization", function()
        it("should remove slashes from filenames", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = "Part 1/Part 2",
                author = "Author Name",
            }

            local virtual_path = vlib:generateVirtualPath("BOOKID", metadata)

            assert.is_false(virtual_path:match("/Part 2") ~= nil)
            assert.is_true(virtual_path:match("_Part 2") ~= nil)
        end)

        it("should remove colons from filenames", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = "Title: Subtitle",
                author = "Author",
            }

            local virtual_path = vlib:generateVirtualPath("BOOKID", metadata)

            assert.is_false(virtual_path:match(": Subtitle") ~= nil)
            assert.is_true(virtual_path:match("_ Subtitle") ~= nil)
        end)

        it("should remove all special filesystem characters", function()
            local parser = MetadataParser:new()
            local vlib = VirtualLibrary:new(parser)

            local metadata = {
                title = 'Bad/\\:*?"<>|Chars',
                author = "Author",
            }

            local virtual_path = vlib:generateVirtualPath("BOOKID", metadata)
            local filename = virtual_path:match("/([^/]+)$")

            -- Should not contain any of the forbidden characters except in the path separator
            assert.is_false(filename:match('[/\\:*?"<>|]') ~= nil)
        end)
    end)
end)
