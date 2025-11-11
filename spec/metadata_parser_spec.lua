-- Tests for MetadataParser module

describe("MetadataParser", function()
    local MetadataParser

    setup(function()
        -- Load the real MetadataParser (mocks for dependencies are in helper.lua)
        require("spec.helper")
        MetadataParser = require("metadata_parser")
    end)

    before_each(function()
        -- Clear require cache to ensure fresh loads
        package.loaded["metadata_parser"] = nil
        MetadataParser = require("metadata_parser")
    end)

    describe("initialization", function()
        it("should create a new instance", function()
            local parser = MetadataParser:new()
            assert.is_not_nil(parser)
        end)

        it("should initialize with nil metadata", function()
            local parser = MetadataParser:new()
            assert.is_nil(parser.metadata)
        end)

        it("should initialize with nil db_path", function()
            local parser = MetadataParser:new()
            assert.is_nil(parser.db_path)
        end)
    end)

    describe("getKoboPath", function()
        it("should return default Kobo path", function()
            local parser = MetadataParser:new()
            local path = parser:getKoboPath()
            assert.is_not_nil(path)
            assert.is_string(path)
        end)

        it("should return .kobo directory path", function()
            local parser = MetadataParser:new()
            local path = parser:getKoboPath()
            assert.is_true(path:match("%.kobo$") ~= nil or path:match("%.kobo/") ~= nil or path:match(".kobo") ~= nil)
        end)
    end)

    describe("getDatabasePath", function()
        it("should return a database path", function()
            local parser = MetadataParser:new()
            local path = parser:getDatabasePath()
            assert.is_not_nil(path)
            assert.is_string(path)
        end)

        it("should end with KoboReader.sqlite", function()
            local parser = MetadataParser:new()
            local path = parser:getDatabasePath()
            assert.is_true(path:match("KoboReader%.sqlite$") ~= nil)
        end)

        it("should cache the database path", function()
            local parser = MetadataParser:new()
            local path1 = parser:getDatabasePath()
            local path2 = parser:getDatabasePath()
            assert.equals(path1, path2)
        end)
    end)

    describe("getKepubPath", function()
        it("should return a kepub path", function()
            local parser = MetadataParser:new()
            local path = parser:getKepubPath()
            assert.is_not_nil(path)
            assert.is_string(path)
        end)

        it("should end with /kepub", function()
            local parser = MetadataParser:new()
            local path = parser:getKepubPath()
            assert.is_true(path:match("kepub$") ~= nil)
        end)

        it("should be consistent across calls", function()
            local parser = MetadataParser:new()
            local path1 = parser:getKepubPath()
            local path2 = parser:getKepubPath()
            assert.equals(path1, path2)
        end)
    end)

    describe("path relationships", function()
        it("database path should be under kobo path", function()
            local parser = MetadataParser:new()
            local kobo_path = parser:getKoboPath()
            local db_path = parser:getDatabasePath()
            assert.is_true(db_path:sub(1, #kobo_path) == kobo_path)
        end)

        it("kepub path should be under kobo path", function()
            local parser = MetadataParser:new()
            local kobo_path = parser:getKoboPath()
            local kepub_path = parser:getKepubPath()
            assert.is_true(kepub_path:sub(1, #kobo_path) == kobo_path)
        end)
    end)

    describe("needsReload", function()
        local lfs, SQ3

        before_each(function()
            lfs = require("libs/libkoreader-lfs")
            lfs._clearFileStates()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
        end)

        it("should return true if metadata is nil", function()
            local parser = MetadataParser:new()
            assert.is_true(parser:needsReload())
        end)

        it("should return true if last_mtime is nil but metadata exists", function()
            local parser = MetadataParser:new()
            parser.metadata = {}
            parser.last_mtime = nil
            assert.is_true(parser:needsReload())
        end)

        it("should return true if database file is missing but metadata present", function()
            local parser = MetadataParser:new()
            parser.metadata = { book1 = {} }
            local db_path = parser:getDatabasePath()
            lfs._setFileState(db_path, { exists = false, attributes = nil })
            assert.is_true(parser:needsReload())
        end)

        it("should return true if file mtime is newer than last_mtime", function()
            local parser = MetadataParser:new()
            parser.metadata = {}
            parser.last_mtime = 1000000000
            local db_path = parser:getDatabasePath()
            lfs._setFileState(db_path, {
                exists = true,
                attributes = { size = 100, mode = "file", modification = 2000000000 },
            })
            assert.is_true(parser:needsReload())
        end)

        it("should return false if file mtime equals last_mtime", function()
            local parser = MetadataParser:new()
            local last_mtime = 1500000000

            parser.metadata = {}
            parser.last_mtime = last_mtime
            local db_path = parser:getDatabasePath()
            lfs._setFileState(db_path, {
                exists = true,
                attributes = { size = 100, mode = "file", modification = last_mtime },
            })
            assert.is_false(parser:needsReload())
        end)

        it("should return false if file mtime is older than last_mtime", function()
            local parser = MetadataParser:new()
            parser.metadata = {}
            parser.last_mtime = 2000000000
            local db_path = parser:getDatabasePath()
            lfs._setFileState(db_path, {
                exists = true,
                attributes = { size = 100, mode = "file", modification = 1000000000 },
            })
            assert.is_false(parser:needsReload())
        end)
    end)

    describe("parseMetadata", function()
        local lfs, SQ3

        before_each(function()
            lfs = require("libs/libkoreader-lfs")
            lfs._clearFileStates()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
        end)

        it("should return empty table if database file is missing", function()
            local parser = MetadataParser:new()
            local db_path = parser:getDatabasePath()
            lfs._setFileState(db_path, { exists = false, attributes = nil })

            local metadata = parser:parseMetadata()
            assert.is_table(metadata)
            assert.equals(0, #metadata)
            for _ in pairs(metadata) do
                assert.is_true(false, "metadata should be empty")
            end
        end)

        it("should return empty table if database open fails", function()
            local parser = MetadataParser:new()
            SQ3._setFailOpen(true)

            local metadata = parser:parseMetadata()
            assert.is_table(metadata)
            assert.equals(0, #metadata)
            for _ in pairs(metadata) do
                assert.is_true(false, "metadata should be empty")
            end
        end)

        it("should return empty table if query prepare fails", function()
            local parser = MetadataParser:new()
            SQ3._setFailPrepare(true)

            local metadata = parser:parseMetadata()
            assert.is_table(metadata)
            assert.equals(0, #metadata)
            for _ in pairs(metadata) do
                assert.is_true(false, "metadata should be empty")
            end
        end)

        it("should parse and map fields correctly from rows", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Test Title", "Test Author", "Test Publisher", "Test Series", "1", 50 },
            })

            local metadata = parser:parseMetadata()
            assert.is_table(metadata)
            assert.is_not_nil(metadata["BOOK001"])
            assert.equals("Test Title", metadata["BOOK001"].title)
            assert.equals("Test Author", metadata["BOOK001"].author)
            assert.equals("Test Publisher", metadata["BOOK001"].publisher)
            assert.equals("Test Series", metadata["BOOK001"].series)
            assert.equals("1", metadata["BOOK001"].series_number)
            assert.equals(50, metadata["BOOK001"].percent_read)
        end)

        it("should handle empty title and use 'Unknown' as fallback", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK002", "", "Author", "", "", "", 0 },
            })

            local metadata = parser:parseMetadata()
            assert.equals("Unknown", metadata["BOOK002"].title)
        end)

        it("should handle empty author and use 'Unknown' as fallback", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK003", "Title", "", "", "", "", 0 },
            })

            local metadata = parser:parseMetadata()
            assert.equals("Unknown", metadata["BOOK003"].author)
        end)

        it("should handle nil percent_read and default to 0", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK004", "Title", "Author", "", "", "", nil },
            })

            local metadata = parser:parseMetadata()
            assert.equals(0, metadata["BOOK004"].percent_read)
        end)

        it("should parse multiple books correctly", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title 1", "Author 1", "", "", "", 25 },
                { "BOOK002", "Title 2", "Author 2", "", "", "", 75 },
                { "BOOK003", "Title 3", "Author 3", "", "", "", 100 },
            })

            local metadata = parser:parseMetadata()
            assert.equals(3, parser:getBookCount())
            assert.is_not_nil(metadata["BOOK001"])
            assert.is_not_nil(metadata["BOOK002"])
            assert.is_not_nil(metadata["BOOK003"])
        end)

        it("should update last_mtime after successful parse", function()
            local parser = MetadataParser:new()
            local db_path = parser:getDatabasePath()
            lfs._setFileState(db_path, {
                exists = true,
                attributes = { size = 100, mode = "file", modification = 1234567890 },
            })
            SQ3._setBookRows({
                { "BOOK001", "Title", "Author", "", "", "", 0 },
            })

            parser:parseMetadata()
            assert.equals(1234567890, parser.last_mtime)
        end)
    end)

    describe("getMetadata", function()
        local lfs, SQ3

        before_each(function()
            lfs = require("libs/libkoreader-lfs")
            lfs._clearFileStates()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
        end)

        it("should call parseMetadata if needsReload returns true", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title", "Author", "", "", "", 0 },
            })

            assert.is_nil(parser.metadata)
            local metadata = parser:getMetadata()
            assert.is_not_nil(parser.metadata)
            assert.is_table(metadata)
        end)

        it("should return cached metadata if up-to-date", function()
            local parser = MetadataParser:new()
            parser.metadata = { cached = true }
            parser.last_mtime = 9999999999
            local db_path = parser:getDatabasePath()
            lfs._setFileState(db_path, {
                exists = true,
                attributes = { size = 100, mode = "file", modification = 1000000000 },
            })

            local metadata = parser:getMetadata()
            assert.is_true(metadata.cached)
        end)

        it("should return empty table if metadata is nil and parse fails", function()
            local parser = MetadataParser:new()
            SQ3._setFailOpen(true)

            local metadata = parser:getMetadata()
            assert.is_table(metadata)
        end)
    end)

    describe("getBookMetadata", function()
        local SQ3

        before_each(function()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
        end)

        it("should return correct metadata for known book_id", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title 1", "Author 1", "", "", "", 50 },
                { "BOOK002", "Title 2", "Author 2", "", "", "", 75 },
            })
            parser:parseMetadata()

            local book_meta = parser:getBookMetadata("BOOK001")
            assert.is_not_nil(book_meta)
            assert.equals("Title 1", book_meta.title)
            assert.equals("Author 1", book_meta.author)
            assert.equals(50, book_meta.percent_read)
        end)

        it("should return nil for unknown book_id", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title", "Author", "", "", "", 0 },
            })
            parser:parseMetadata()

            local book_meta = parser:getBookMetadata("UNKNOWN_BOOK")
            assert.is_nil(book_meta)
        end)
    end)

    describe("getBookIds", function()
        local SQ3

        before_each(function()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
        end)

        it("should return empty list for empty metadata", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({})
            parser:parseMetadata()

            local ids = parser:getBookIds()
            assert.is_table(ids)
            assert.equals(0, #ids)
        end)

        it("should return correct list for non-empty metadata", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title 1", "Author 1", "", "", "", 0 },
                { "BOOK002", "Title 2", "Author 2", "", "", "", 0 },
                { "BOOK003", "Title 3", "Author 3", "", "", "", 0 },
            })
            parser:parseMetadata()

            local ids = parser:getBookIds()
            assert.equals(3, #ids)
            -- Check that all IDs are present
            local id_set = {}
            for _, id in ipairs(ids) do
                id_set[id] = true
            end
            assert.is_true(id_set["BOOK001"])
            assert.is_true(id_set["BOOK002"])
            assert.is_true(id_set["BOOK003"])
        end)
    end)

    describe("getBookCount", function()
        local SQ3

        before_each(function()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
        end)

        it("should return 0 for empty metadata", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({})
            parser:parseMetadata()

            assert.equals(0, parser:getBookCount())
        end)

        it("should return correct count for non-empty metadata", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title 1", "Author 1", "", "", "", 0 },
                { "BOOK002", "Title 2", "Author 2", "", "", "", 0 },
                { "BOOK003", "Title 3", "Author 3", "", "", "", 0 },
            })
            parser:parseMetadata()

            assert.equals(3, parser:getBookCount())
        end)
    end)

    describe("getBookFilePath", function()
        local lfs

        before_each(function()
            lfs = require("libs/libkoreader-lfs")
            lfs._clearFileStates()
        end)

        it("should return path if file exists and is a file", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/BOOK001"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "file" },
            })

            local filepath = parser:getBookFilePath("BOOK001")
            assert.is_not_nil(filepath)
            assert.equals(book_path, filepath)
        end)

        it("should return nil if file does not exist", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/MISSING_BOOK"
            lfs._setFileState(book_path, {
                exists = false,
                attributes = { mode = "directory" },
            })

            local filepath = parser:getBookFilePath("MISSING_BOOK")
            assert.is_nil(filepath)
        end)

        it("should return nil if path is a directory", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/BOOK_DIR"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "directory" },
            })

            local filepath = parser:getBookFilePath("BOOK_DIR")
            assert.is_nil(filepath)
        end)
    end)

    describe("getThumbnailPath", function()
        it("should return correct thumbnail path for book_id", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local expected_path = kepub_path .. "/.thumbnail-previews/BOOK001.png"

            local thumb_path = parser:getThumbnailPath("BOOK001")
            assert.equals(expected_path, thumb_path)
        end)

        it("should handle different book IDs correctly", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()

            local thumb1 = parser:getThumbnailPath("ABC123")
            local thumb2 = parser:getThumbnailPath("XYZ789")

            assert.equals(kepub_path .. "/.thumbnail-previews/ABC123.png", thumb1)
            assert.equals(kepub_path .. "/.thumbnail-previews/XYZ789.png", thumb2)
        end)
    end)

    describe("isBookAccessible", function()
        local lfs

        before_each(function()
            lfs = require("libs/libkoreader-lfs")
            lfs._clearFileStates()
        end)

        it("should return true if file exists and is a file", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/BOOK001"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "file" },
            })

            assert.is_true(parser:isBookAccessible("BOOK001"))
        end)

        it("should return false if file does not exist", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/MISSING"
            lfs._setFileState(book_path, {
                exists = false,
                attributes = nil,
            })

            assert.is_false(parser:isBookAccessible("MISSING"))
        end)

        it("should return false if path is not a file", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/DIR"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "directory" },
            })

            assert.is_false(parser:isBookAccessible("DIR"))
        end)
    end)

    describe("isBookEncrypted", function()
        local lfs
        local mock_io_files = {}

        before_each(function()
            lfs = require("libs/libkoreader-lfs")
            lfs._clearFileStates()
            mock_io_files = {}

            -- Mock io.open for file reading
            _G._original_io_open = _G._original_io_open or io.open
            io.open = function(path, mode)
                if mock_io_files[path] then
                    return mock_io_files[path]
                end
                return _G._original_io_open(path, mode)
            end
        end)

        after_each(function()
            if _G._original_io_open then
                io.open = _G._original_io_open
            end
        end)

        it("should return true if file is missing", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/MISSING"
            lfs._setFileState(book_path, {
                exists = false,
                attributes = nil,
            })

            assert.is_true(parser:isBookEncrypted("MISSING"))
        end)

        it("should return true if file cannot be opened", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/UNREADABLE"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "file" },
            })
            mock_io_files[book_path] = nil -- Simulate open failure

            assert.is_true(parser:isBookEncrypted("UNREADABLE"))
        end)

        it("should return true if file is too short", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/SHORT"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "file" },
            })
            mock_io_files[book_path] = {
                read = function()
                    return "ab"
                end, -- Only 2 bytes
                close = function() end,
            }

            assert.is_true(parser:isBookEncrypted("SHORT"))
        end)

        it("should return false if file has correct ZIP signature", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/VALID_EPUB"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "file" },
            })
            -- ZIP/EPUB signature: PK\x03\x04
            mock_io_files[book_path] = {
                read = function()
                    return string.char(0x50, 0x4B, 0x03, 0x04)
                end,
                close = function() end,
            }

            assert.is_false(parser:isBookEncrypted("VALID_EPUB"))
        end)

        it("should return true if file does not have ZIP signature", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()
            local book_path = kepub_path .. "/ENCRYPTED"
            lfs._setFileState(book_path, {
                exists = true,
                attributes = { mode = "file" },
            })
            -- Non-ZIP signature
            mock_io_files[book_path] = {
                read = function()
                    return "ABCD"
                end,
                close = function() end,
            }

            assert.is_true(parser:isBookEncrypted("ENCRYPTED"))
        end)
    end)

    describe("getAccessibleBooks", function()
        local lfs, SQ3
        local mock_io_files = {}

        before_each(function()
            lfs = require("libs/libkoreader-lfs")
            lfs._clearFileStates()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
            mock_io_files = {}

            -- Mock io.open for file reading
            _G._original_io_open = _G._original_io_open or io.open
            io.open = function(path, mode)
                if mock_io_files[path] then
                    return mock_io_files[path]
                end
                return _G._original_io_open(path, mode)
            end
        end)

        after_each(function()
            if _G._original_io_open then
                io.open = _G._original_io_open
            end
        end)

        it("should return only accessible and unencrypted books", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()

            SQ3._setBookRows({
                { "ACCESSIBLE", "Accessible Book", "Author 1", "", "", "", 50 },
                { "ENCRYPTED", "Encrypted Book", "Author 2", "", "", "", 25 },
                { "MISSING", "Missing Book", "Author 3", "", "", "", 0 },
            })

            -- Setup file states
            lfs._setFileState(kepub_path .. "/ACCESSIBLE", {
                exists = true,
                attributes = { mode = "file" },
            })
            lfs._setFileState(kepub_path .. "/ENCRYPTED", {
                exists = true,
                attributes = { mode = "file" },
            })
            lfs._setFileState(kepub_path .. "/MISSING", {
                exists = false,
                attributes = nil,
            })

            -- Setup file contents
            mock_io_files[kepub_path .. "/ACCESSIBLE"] = {
                read = function()
                    return string.char(0x50, 0x4B, 0x03, 0x04)
                end, -- Valid ZIP
                close = function() end,
            }
            mock_io_files[kepub_path .. "/ENCRYPTED"] = {
                read = function()
                    return "ABCD"
                end, -- Not a ZIP
                close = function() end,
            }

            local accessible = parser:getAccessibleBooks()

            assert.equals(1, #accessible)
            assert.equals("ACCESSIBLE", accessible[1].id)
            assert.equals("Accessible Book", accessible[1].metadata.title)
            assert.equals(kepub_path .. "/ACCESSIBLE", accessible[1].filepath)
        end)

        it("should return empty list if all books are encrypted or missing", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()

            SQ3._setBookRows({
                { "ENCRYPTED", "Encrypted Book", "Author", "", "", "", 0 },
                { "MISSING", "Missing Book", "Author", "", "", "", 0 },
            })

            lfs._setFileState(kepub_path .. "/ENCRYPTED", {
                exists = true,
                attributes = { mode = "file" },
            })
            lfs._setFileState(kepub_path .. "/MISSING", {
                exists = false,
                attributes = nil,
            })

            mock_io_files[kepub_path .. "/ENCRYPTED"] = {
                read = function()
                    return "ABCD"
                end,
                close = function() end,
            }

            local accessible = parser:getAccessibleBooks()
            assert.equals(0, #accessible)
        end)

        it("should include thumbnail paths for accessible books", function()
            local parser = MetadataParser:new()
            local kepub_path = parser:getKepubPath()

            SQ3._setBookRows({
                { "BOOK001", "Test Book", "Author", "", "", "", 0 },
            })

            lfs._setFileState(kepub_path .. "/BOOK001", {
                exists = true,
                attributes = { mode = "file" },
            })

            mock_io_files[kepub_path .. "/BOOK001"] = {
                read = function()
                    return string.char(0x50, 0x4B, 0x03, 0x04)
                end,
                close = function() end,
            }

            local accessible = parser:getAccessibleBooks()

            assert.equals(1, #accessible)
            assert.equals(kepub_path .. "/.thumbnail-previews/BOOK001.png", accessible[1].thumbnail)
        end)
    end)

    describe("clearCache", function()
        local SQ3

        before_each(function()
            SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearMockState()
        end)

        it("should set metadata to nil", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title", "Author", "", "", "", 0 },
            })
            parser:parseMetadata()
            assert.is_not_nil(parser.metadata)

            parser:clearCache()
            assert.is_nil(parser.metadata)
        end)

        it("should set last_mtime to nil", function()
            local parser = MetadataParser:new()
            parser.last_mtime = 1234567890

            parser:clearCache()
            assert.is_nil(parser.last_mtime)
        end)

        it("should force reload on next getMetadata call", function()
            local parser = MetadataParser:new()
            SQ3._setBookRows({
                { "BOOK001", "Title 1", "Author", "", "", "", 0 },
            })
            parser:parseMetadata()

            parser:clearCache()

            SQ3._setBookRows({
                { "BOOK002", "Title 2", "Author", "", "", "", 0 },
            })

            local metadata = parser:getMetadata()
            assert.is_nil(metadata["BOOK001"])
            assert.is_not_nil(metadata["BOOK002"])
        end)
    end)
end)
