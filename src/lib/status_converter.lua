---
-- Status format conversion between Kobo and KOReader.
-- Handles bidirectional conversion of reading status values.

local StatusConverter = {}

---
-- Converts Kobo ReadStatus value to KOReader status string.
-- Kobo uses numeric values: 0=unopened, 1=reading, 2=finished.
-- KOReader uses strings: abandoned, reading, complete.
-- @param kobo_status number: Kobo ReadStatus value.
-- @return string: KOReader status string.
function StatusConverter.koboToKoreader(kobo_status)
    local status_num = tonumber(kobo_status) or 0

    if status_num == 0 then
        return ""
    end

    if status_num == 1 then
        return "reading"
    end

    if status_num == 2 then
        return "complete"
    end

    return "abandoned"
end

---
-- Converts KOReader status string to Kobo ReadStatus value.
-- KOReader uses strings: abandoned, reading, complete, on-hold.
-- Kobo uses numeric values: 0=unopened, 1=reading, 2=finished.
-- @param kr_status string: KOReader status string.
-- @return number: Kobo ReadStatus value.
function StatusConverter.koreaderToKobo(kr_status)
    if kr_status == "reading" or kr_status == "in-progress" then
        return 1
    end

    if kr_status == "complete" or kr_status == "finished" then
        return 2
    end

    return 1
end

return StatusConverter
