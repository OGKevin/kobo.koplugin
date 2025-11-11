---
-- Kobo database state writer.
-- Writes reading progress and metadata to Kobo's SQLite database.

local logger = require("logger")
local SQ3 = require("lua-ljsqlite3/init")
local StatusConverter = require("lib/status_converter")

local KoboStateWriter = {}

---
-- Formats Unix timestamp as Kobo ISO 8601 datetime string.
-- @param timestamp number: Unix timestamp.
-- @return string: ISO 8601 formatted string, or empty string if timestamp is invalid.
local function formatKoboTimestamp(timestamp)
    if not timestamp or timestamp <= 0 then
        return ""
    end

    return os.date("!%Y-%m-%d %H:%M:%S.000+00:00", timestamp)
end

---
-- Calculates the progress percentage within a chapter.
--
-- Given an overall reading position and chapter boundaries, calculates
-- how far through the chapter the reader is as a percentage (0-100).
--
-- Example:
--   Target position: 20.5%
--   Chapter starts at: 20%
--   Chapter size: 1.37%
--   
--   Position within chapter = 20.5 - 20 = 0.5
--   Progress = (0.5 / 1.37) * 100 = 36.5%
--
-- @param percent_read number: Overall reading position (0-100).
-- @param chapter_start_percent number: Where chapter begins (0-100).
-- @param chapter_size_percent number: Size of chapter (0-100).
-- @param chapter_end_percent number: Where chapter ends (0-100).
-- @return number: Progress within chapter (0-100).
local function calculateChapterProgressPercent(
    percent_read,
    chapter_start_percent,
    chapter_size_percent,
    chapter_end_percent
)
    local within_chapter_percent = percent_read - chapter_start_percent
    local chapter_progress_percent = chapter_size_percent > 0 and (within_chapter_percent / chapter_size_percent) * 100 or 0

    logger.dbg(
        "KoboPlugin: Calculated chapter progress:",
        "overall_position:",
        percent_read,
        "chapter_range:",
        chapter_start_percent,
        "-",
        chapter_end_percent,
        "within_chapter:",
        within_chapter_percent,
        "chapter_percent:",
        math.floor(chapter_progress_percent)
    )

    return chapter_progress_percent
end

---
-- Retrieves the last chapter in the book.
--
-- Used when the reading position is beyond the end of the found chapter,
-- which can happen due to rounding differences or database inconsistencies.
--
-- @param conn table: SQLite connection.
-- @param book_id string: Book ContentID.
-- @return string|nil: ContentID of last chapter, or nil if not found.
local function getLastChapter(conn, book_id)
    local last_chapter = conn:exec(
        string.format(
            "SELECT ContentID FROM content WHERE ContentID LIKE '%s%%%%' AND ContentType = 9 ORDER BY ___FileOffset DESC LIMIT 1",
            book_id
        )
    )

    if not last_chapter or not last_chapter[1] or #last_chapter[1] == 0 then
        return nil
    end

    return last_chapter[1][1]
end

---
-- Extracts the filename portion from a ContentID.
--
-- Kobo ContentIDs are in format: "BOOKID!!filename.html"
-- This function extracts just "filename.html" for use in bookmarks.
--
-- @param content_id string: Full ContentID.
-- @return string: Filename portion of ContentID.
local function extractFilename(content_id)
    if not content_id:match("!!") then
        return content_id
    end

    return content_id:match("!!(.+)$")
end

---
-- Finds the appropriate chapter for a given reading percentage.
-- Uses SQL WHERE clause with ___FileOffset to efficiently find the chapter.
--
-- Example calculation:
--   Target overall progress: 20.5%
--   Query finds chapter starting at 20% (___FileOffset <= 20.5)
--   Chapter size is 1.37% (___FileSize = 1.36992)
--   Chapter range: [20%, 21.37%)
--   
--   Position within chapter = 20.5 - 20 = 0.5
--   Chapter progress = (0.5 / 1.36992) * 100 = 36.5%
--
-- @param conn table: SQLite connection.
-- @param book_id string: Book ContentID.
-- @param percent_read number: Target percentage (0-100).
-- @return string|nil: Chapter ID bookmark string, or nil if not found.
-- @return number: Chapter progress percentage (0-100).
-- @return string|nil: Chapter ContentID, or nil if not found.
local function findChapterForPercentage(conn, book_id, percent_read)
    local chapters_res = conn:exec(
        string.format(
            "SELECT ContentID, ___FileOffset, ___FileSize FROM content WHERE ContentID LIKE '%s%%%%' AND ContentType = 9 AND ___FileOffset <= %f ORDER BY ___FileOffset DESC LIMIT 1",
            book_id,
            percent_read
        )
    )

    if not chapters_res or not chapters_res[1] or #chapters_res[1] == 0 then
        return nil, 0
    end

    local target_content_id = chapters_res[1][1]
    local chapter_start_percent = tonumber(chapters_res[2][1]) or 0
    local chapter_size_percent = tonumber(chapters_res[3][1]) or 0
    local chapter_end_percent = chapter_start_percent + chapter_size_percent

    local chapter_progress_percent = calculateChapterProgressPercent(
        percent_read,
        chapter_start_percent,
        chapter_size_percent,
        chapter_end_percent
    )

    --[[
        FIXME: Handle edge case where percent_read > chapter_end_percent

        The current solution to just fetch the last chapter may not be ideal.
        e.g. there is a gap in the chapter offsets, or rounding issues.

        However, looking at this more carefully, this logic might be flawed.
        If the position is between chapters (e.g., at 45% when chapters are [0-30%], [50-80%]),
        the query would find the chapter at 30%, and percent_read > chapter_end_percent would be true,
        but we shouldn't jump to the last chapter.
    ]]
    if percent_read > chapter_end_percent then
        target_content_id = getLastChapter(conn, book_id)
        chapter_progress_percent = 100
    end

    if not target_content_id then
        return nil, 0
    end

    local filename = extractFilename(target_content_id)
    local chapter_id_bookmarked = string.format("%s#kobo.1.1", filename)

    return chapter_id_bookmarked, chapter_progress_percent, target_content_id
end

---
-- Updates chapter progress in the database.
-- @param conn table: SQLite connection.
-- @param content_id string: Chapter ContentID.
-- @param chapter_percent number: Chapter progress percentage.
-- @return boolean: True if update succeeded.
local function updateChapterProgress(conn, content_id, chapter_percent)
    local stmt = conn:prepare("UPDATE content SET ___PercentRead = ? WHERE ContentID = ? AND ContentType = 9")
    if not stmt then
        return false
    end

    local ok, err = pcall(function()
        stmt:reset():bind(math.floor(chapter_percent), content_id):step()
    end)

    if ok then
        logger.dbg("KoboPlugin: Updated chapter progress:", content_id, "chapter_percent:", math.floor(chapter_percent))
        return true
    end

    logger.warn("KoboPlugin: Error updating chapter progress for:", content_id, "error:", err)
    return false
end

---
-- Updates main book entry in the database.
-- @param conn table: SQLite connection.
-- @param book_id string: Book ContentID.
-- @param percent_read number: Overall progress percentage.
-- @param date_str string: ISO 8601 formatted timestamp.
-- @param read_status number: Kobo ReadStatus value.
-- @param chapter_id_bookmarked string: Current chapter bookmark.
-- @return boolean: True if update succeeded.
local function updateMainBookEntry(conn, book_id, percent_read, date_str, read_status, chapter_id_bookmarked)
    local stmt = conn:prepare(
        "UPDATE content SET ___PercentRead = ?, DateLastRead = ?, ReadStatus = ?, ChapterIDBookmarked = ? WHERE ContentID = ? AND ContentType = 6"
    )

    if not stmt then
        logger.warn("KoboPlugin: Failed to prepare update statement for book:", book_id)
        return false
    end

    local ok, err = pcall(function()
        stmt:reset():bind(math.floor(percent_read), date_str, read_status, chapter_id_bookmarked, book_id):step()
    end)

    if not ok then
        logger.warn("KoboPlugin: Error executing update for book:", book_id, "error:", err)
        return false
    end

    return true
end

---
-- Writes reading state to Kobo database for a specific book.
-- @param db_path string: Path to Kobo SQLite database.
-- @param book_id string: Book ContentID.
-- @param percent_read number: Progress percentage (0-100).
-- @param timestamp number: Unix timestamp of last read.
-- @param status string: KOReader status string.
-- @return boolean: True if write succeeded.
function KoboStateWriter.write(db_path, book_id, percent_read, timestamp, status)
    if not db_path then
        return false
    end

    local conn = SQ3.open(db_path)
    if not conn then
        logger.warn("KoboPlugin: Failed to open Kobo database for book:", book_id)
        return false
    end

    percent_read = tonumber(percent_read) or 0
    local date_str = formatKoboTimestamp(timestamp)
    local read_status = status and StatusConverter.koreaderToKobo(status) or 1

    local chapter_id_bookmarked, chapter_percent, target_content_id =
        findChapterForPercentage(conn, book_id, percent_read)

    chapter_id_bookmarked = chapter_id_bookmarked or ""
    chapter_percent = chapter_percent or 0

    if target_content_id and type(target_content_id) == "string" then
        updateChapterProgress(conn, target_content_id, chapter_percent)
    end

    local success = updateMainBookEntry(conn, book_id, percent_read, date_str, read_status, chapter_id_bookmarked)

    conn:close()

    if success then
        logger.dbg(
            "KoboPlugin: Wrote Kobo reading progress for book:",
            book_id,
            "percent:",
            percent_read,
            "chapter:",
            chapter_id_bookmarked,
            "chapter_percent:",
            math.floor(chapter_percent),
            "timestamp:",
            timestamp,
            "status:",
            status,
            "kobo_status:",
            read_status
        )
    else
        logger.warn("KoboPlugin: Failed to update Kobo database for book:", book_id, "percent:", percent_read)
    end

    return success
end

return KoboStateWriter
