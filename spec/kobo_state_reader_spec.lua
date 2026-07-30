-- Tests for KoboStateReader

describe("KoboStateReader timestamp parsing", function()
    local KoboStateReader
    local SQ3

    setup(function()
        require("spec/helper")
        SQ3 = require("lua-ljsqlite3/init")
    end)

    before_each(function()
        package.loaded["src/lib/kobo_state_reader"] = nil
        KoboStateReader = require("src/lib/kobo_state_reader")
        SQ3._clearMockState()
    end)

    after_each(function()
        SQ3._clearMockState()
    end)

    local function readTimestamp(date_string)
        SQ3._setDateLastRead(date_string)
        local state = KoboStateReader.read("/fake/db.sqlite", "test_book_1")
        assert.is_not_nil(state)
        return state.timestamp
    end

    it("returns 0 when DateLastRead is empty", function()
        assert.equals(0, readTimestamp(""))
    end)

    it("returns 0 when DateLastRead does not match a known date format", function()
        assert.equals(0, readTimestamp("not-a-date"))
    end)

    it("treats a datetime without a timezone as local time", function()
        -- Local time with no suffix: os.time() should parse the fields as
        -- local wall-clock time.
        local expected = os.time({ year = 2025, month = 11, day = 8, hour = 15, min = 30, sec = 45 })
        assert.equals(expected, readTimestamp("2025-11-08T15:30:45"))
    end)

    it("accepts a space separator instead of 'T'", function()
        local expected = os.time({ year = 2025, month = 11, day = 8, hour = 15, min = 30, sec = 45 })
        assert.equals(expected, readTimestamp("2025-11-08 15:30:45"))
    end)

    it("treats the legacy '+00:00' offset with milliseconds the same as 'Z'", function()
        local z_ts = readTimestamp("2025-11-08T15:30:45Z")
        local legacy_ts = readTimestamp("2025-11-08 15:30:45.000+00:00")
        assert.equals(z_ts, legacy_ts)
    end)

    it("applies a positive UTC offset relative to 'Z'", function()
        local z_ts = readTimestamp("2025-11-08T15:30:45Z")
        local plus_two_ts = readTimestamp("2025-11-08T15:30:45+02:00")

        -- 15:30:45+02:00 is 2 hours *earlier* in UTC than 15:30:45Z,
        -- so its resulting local timestamp should be 2 hours behind.
        assert.equals(2 * 3600, z_ts - plus_two_ts)
    end)

    it("applies a negative UTC offset relative to 'Z'", function()
        local z_ts = readTimestamp("2025-11-08T15:30:45Z")
        local minus_five_ts = readTimestamp("2025-11-08T15:30:45-05:00")

        -- 15:30:45-05:00 is 5 hours *later* in UTC than 15:30:45Z,
        -- so its resulting local timestamp should be 5 hours ahead.
        assert.equals(5 * 3600, minus_five_ts - z_ts)
    end)

    it("keeps offsets consistent across the day boundary", function()
        local z_ts = readTimestamp("2025-11-08T00:30:00Z")
        local plus_two_ts = readTimestamp("2025-11-08T00:30:00+02:00")

        assert.equals(2 * 3600, z_ts - plus_two_ts)
    end)
end)
