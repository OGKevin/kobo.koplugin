-- Tests for KoboStateWriter

describe("KoboStateWriter timestamp formatting", function()
    local KoboStateWriter
    local SQ3

    setup(function()
        require("spec/helper")
        SQ3 = require("lua-ljsqlite3/init")
    end)

    before_each(function()
        package.loaded["src/lib/kobo_state_writer"] = nil
        KoboStateWriter = require("src/lib/kobo_state_writer")
        SQ3._clearMockState()
        SQ3._clearSqlQueries()
    end)

    after_each(function()
        SQ3._clearMockState()
    end)

    local function findMainEntryUpdateDateParam()
        local queries = SQ3._getSqlQueries()

        for _, captured in ipairs(queries) do
            if captured.query:match("ContentType = 6") and captured.query:match("DateLastRead") then
                return captured.params[2]
            end
        end

        return nil
    end

    it("writes the timestamp as 'YYYY-MM-DDTHH:MM:SSZ'", function()
        local timestamp = os.time({ year = 2025, month = 11, day = 8, hour = 15, min = 30, sec = 45 })

        KoboStateWriter.write("/fake/db.sqlite", "test_book_1", 35, timestamp, "reading")

        local date_str = findMainEntryUpdateDateParam()
        assert.is_not_nil(date_str)
        assert.matches("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$", date_str)
    end)

    it("does not write the legacy '+00:00' millisecond format", function()
        local timestamp = os.time({ year = 2025, month = 11, day = 8, hour = 15, min = 30, sec = 45 })

        KoboStateWriter.write("/fake/db.sqlite", "test_book_1", 35, timestamp, "reading")

        local date_str = findMainEntryUpdateDateParam()
        assert.is_not_nil(date_str)
        assert.is_nil(date_str:match("%+00:00"))
        assert.is_nil(date_str:match("%."))
    end)

    it("writes an empty DateLastRead when the timestamp is invalid", function()
        KoboStateWriter.write("/fake/db.sqlite", "test_book_1", 35, 0, "reading")

        local date_str = findMainEntryUpdateDateParam()
        assert.equals("", date_str)
    end)
end)
