-- Tests for BookInfoManagerExt module

describe("BookInfoManagerExt", function()
    local BookInfoManagerExt, VirtualLibrary, MetadataParser, SQ3, lfs

    local BOOK_ID = "0b3c7a52-1111-2222-3333-444455556666"
    local VIRTUAL_PATH = "KOBO_VIRTUAL://" .. BOOK_ID .. "/Author - Title.epub"
    local REAL_PATH = "/mnt/onboard/.kobo/kepub/" .. BOOK_ID

    setup(function()
        require("spec/helper")
    end)

    before_each(function()
        package.loaded["src/bookinfomanager_ext"] = nil
        package.loaded["src/virtual_library"] = nil
        package.loaded["src/metadata_parser"] = nil

        BookInfoManagerExt = require("src/bookinfomanager_ext")
        VirtualLibrary = require("src/virtual_library")
        MetadataParser = require("src/metadata_parser")
        SQ3 = require("lua-ljsqlite3/init")
        lfs = require("libs/libkoreader-lfs")

        SQ3._clearMockState()
        lfs._clearFileStates()
    end)

    ---
    -- Loads one Nickel `content` record through the real MetadataParser and VirtualLibrary and
    -- returns the book info CoverBrowser would receive for it. Only the database is mocked.
    -- @param record table: Nickel content columns to store for the book, keyed by column name.
    -- @return table|nil: Book info for the book.
    local function getBookInfo(record)
        record.ContentID = BOOK_ID
        record.Title = record.Title or "Title"
        record.Attribution = record.Attribution or "Author"
        SQ3._setBookRecords({ record })

        local virtual_library = VirtualLibrary:new(MetadataParser:new())
        virtual_library.virtual_to_real[VIRTUAL_PATH] = REAL_PATH
        BookInfoManagerExt:init(virtual_library)

        return BookInfoManagerExt:getVirtualBookInfo(VIRTUAL_PATH, false)
    end

    describe("getVirtualBookInfo", function()
        it("should use the Kobo series number as the series index", function()
            local info = getBookInfo({ Series = "Dune", SeriesNumber = "2" })

            assert.equals("Dune", info.series)
            assert.equals(2, info.series_index)
        end)

        it("should keep fractional series numbers", function()
            local info = getBookInfo({ Series = "Dune", SeriesNumber = "1.5" })

            assert.equals(1.5, info.series_index)
        end)

        it("should leave the series index unset when the series number is empty", function()
            local info = getBookInfo({ Series = "", SeriesNumber = "" })

            assert.is_nil(info.series_index)
        end)

        it("should pass the book description through to book info", function()
            local info = getBookInfo({ Description = "<p>A blurb</p>" })

            assert.equals("<p>A blurb</p>", info.description)
        end)

        it("should pass the book language through to book info", function()
            local info = getBookInfo({ Language = "en" })

            assert.equals("en", info.language)
        end)
    end)
end)
