---
--- Kobo database state reader.
--- Reads reading progress and metadata from Kobo's SQLite database.

local SQ3 = require("lua-ljsqlite3/init")
local StatusConverter = require("src/lib/status_converter")
local logger = require("logger")

local KoboStateReader = {}

---
--- Returns the local timezone offset (local - UTC) in seconds.
---
--- This function uses os.date's "*t" and "!*t" formats
--- (see more [here](https://www.lua.org/manual/5.4/manual.html#pdf-os.date))
--- to calculate the difference between local time and UTC for a given timestamp.
---
--- Due to the way os.time works, this function has to override the isdst field to false to avoid
--- incorrect offsets during daylight saving time. This is because os.time will interpret the isdst
--- field and adjust the time accordingly, which will give always the standard offset regardless of whether
--- the timestamp is in DST or not. With isdst set to false, os.time will treat the time as standard time,
--- and the difference between local and UTC will be the actual offset for that timestamp, which is what we want.
--- @param ts number|nil: Optional timestamp to calculate offset for. Defaults to current time.
--- @return number: Local timezone offset (local - UTC) in seconds.
local function localUtcOffset(ts)
    ts = ts or os.time()

    local local_dt = os.date("*t", ts) --[[@as osdate]]
    local utc_dt = os.date("!*t", ts) --[[@as osdate]]

    local_dt.isdst = false
    utc_dt.isdst = false

    return os.difftime(os.time(local_dt), os.time(utc_dt))
end

---
--- Converts a timestamp interpreted in a source timezone into a local timestamp.
--- @param ts number: Timestamp obtained by interpreting the datetime as local time.
--- @param local_offset number: Local timezone offset (local - UTC) in seconds.
--- @param tz_offset number|nil: Timezone offset from the ISO 8601 suffix (+HH:MM or -HH:MM), in seconds. Defaults to 0 (UTC).
--- @return number: Timestamp representing the same instant in local time.
local function toLocalTimestamp(ts, local_offset, tz_offset)
    return ts - (tz_offset or 0) + local_offset
end

---
--- Parses ISO 8601 datetime string to Unix timestamp.
--- Handles formats:
---     YYYY-MM-DDTHH:MM:SS
---     YYYY-MM-DDTHH:MM:SSZ
---     YYYY-MM-DD HH:MM:SS.SSS+00:00
--- Datetimes without a timezone are interpreted as local time.
--- @param date_string string: ISO 8601 datetime string.
--- @return number: Unix timestamp, or 0 if parsing fails.
local function parseKoboTimestamp(date_string)
    if not date_string or date_string == "" then
        return 0
    end

    local _, end_pos, year, month, day, hour, min, sec = date_string:find("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
    if not year then
        return 0
    end

    local dt = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })

    if not dt then
        return 0
    end

    local remainder = date_string:sub(end_pos + 1):gsub("^%.%d+", "")

    if remainder == "" then
        return dt
    end

    local local_offset = localUtcOffset(dt)

    if remainder == "Z" then
        return toLocalTimestamp(dt, local_offset)
    end

    local sign, hour_offset, min_offset = remainder:match("^([+-])(%d+):(%d+)$")
    if sign then
        local tz_offset = tonumber(hour_offset) * 3600 + tonumber(min_offset) * 60
        if sign == "-" then
            tz_offset = -tz_offset
        end
        return toLocalTimestamp(dt, local_offset, tz_offset)
    end

    return dt
end

---
--- Calculates reading progress from chapter data.
--- Uses ___FileOffset (chapter start position) directly from Kobo database.
---
--- Example calculation:
---   Chapter starts at 20% (___FileOffset = 20)
---   Chapter size is 1.37% (___FileSize = 1.36992)
---   Chapter is 46% complete (___PercentRead = 46)
---
---   Overall progress = 20 + (1.36992 * 46 / 100)
---                    = 20 + 0.63
---                    = 20.63%
---
--- @param conn table: SQLite connection.
--- @param book_id string: Book ContentID.
--- @param chapter_id_bookmarked string: Current bookmarked chapter.
--- @return number: Progress percentage (0-100).
local function calculateChapterProgress(conn, book_id, chapter_id_bookmarked)
    if not chapter_id_bookmarked or chapter_id_bookmarked == "" then
        return 0
    end

    local filename = chapter_id_bookmarked:match("^([^#]+)") or chapter_id_bookmarked
    local chapter_lookup = conn:exec(
        string.format(
            "SELECT ContentID, ___FileOffset, ___FileSize, ___PercentRead FROM content WHERE ContentID LIKE '%s%%' AND ContentType = 9 AND (ContentID LIKE '%%%s' OR ContentID LIKE '%%%s#%%') LIMIT 1",
            book_id,
            filename,
            filename
        )
    )

    if not chapter_lookup or not chapter_lookup[1] or not chapter_lookup[1][1] then
        logger.warn("KoboPlugin: Could not find ContentID for bookmarked chapter:", chapter_id_bookmarked)
        return 0
    end

    local chapter_start_percent = tonumber(chapter_lookup[2][1]) or 0
    local chapter_size_percent = tonumber(chapter_lookup[3][1]) or 0
    local chapter_progress_percent = tonumber(chapter_lookup[4][1]) or 0

    local chapter_contribution_percent = (chapter_size_percent * chapter_progress_percent) / 100.0

    return chapter_start_percent + chapter_contribution_percent
end

---
--- Reads reading state from Kobo database for a specific book.
--- @param db_path string: Path to Kobo SQLite database.
--- @param book_id string: Book ContentID.
--- @return table|nil: State table with percent_read, timestamp, status, kobo_status, or nil on error.
function KoboStateReader.read(db_path, book_id)
    if not db_path then
        return nil
    end

    local conn = SQ3.open(db_path)
    if not conn then
        logger.warn("KoboPlugin: Failed to open Kobo database for book:", book_id)
        return nil
    end

    local res = conn:exec(
        string.format(
            "SELECT DateLastRead, ReadStatus, ChapterIDBookmarked, ___PercentRead FROM content WHERE ContentID = '%s' AND ContentType = 6 LIMIT 1",
            book_id
        )
    )

    if not res or not res[1] or not res[1][1] then
        conn:close()
        logger.dbg("KoboPlugin: No Kobo reading progress found for book:", book_id)
        return nil
    end

    local date_last_read = res[1] and res[1][1]
    local read_status = tonumber((res[2] and res[2][1]) or 0)
    local chapter_id_bookmarked = res[3] and res[3][1]
    local fallback_percent = tonumber((res[4] and res[4][1]) or 0)

    logger.dbg(
        "KoboPlugin: Retrieved main entry for book:",
        book_id,
        "date_last_read:",
        date_last_read,
        "read_status:",
        read_status,
        "chapter_id_bookmarked:",
        chapter_id_bookmarked,
        "fallback_percent:",
        fallback_percent
    )

    local percent_read = 0

    if chapter_id_bookmarked and type(chapter_id_bookmarked) == "string" and chapter_id_bookmarked ~= "" then
        percent_read = calculateChapterProgress(conn, book_id, chapter_id_bookmarked)
    end

    if read_status == 2 and fallback_percent and fallback_percent > 0 then
        percent_read = fallback_percent
        logger.dbg(
            "KoboPlugin: Book marked as finished (ReadStatus=2), using main entry ___PercentRead:",
            percent_read,
            "%"
        )
    end

    if percent_read == 0 and fallback_percent and fallback_percent > 0 then
        percent_read = fallback_percent
        logger.dbg("KoboPlugin: Using fallback ___PercentRead from main entry:", percent_read, "%")
    end

    if read_status == 2 and percent_read == 0 then
        percent_read = 100
        logger.dbg("KoboPlugin: Book marked as finished (ReadStatus=2), defaulting to 100%")
    end

    conn:close()

    local kobo_timestamp = parseKoboTimestamp(date_last_read)
    local status_str = StatusConverter.koboToKoreader(read_status)

    logger.dbg(
        "KoboPlugin: Loaded Kobo reading progress for book:",
        book_id,
        "percent:",
        percent_read,
        "last_read:",
        date_last_read,
        "timestamp:",
        kobo_timestamp,
        "kobo_status:",
        read_status,
        "kr_status:",
        status_str
    )

    return {
        percent_read = percent_read,
        timestamp = kobo_timestamp,
        status = status_str,
        kobo_status = read_status,
    }
end

return KoboStateReader
