---
-- Sync decision maker.
-- Handles user prompts and determines whether sync should proceed based on settings.

local logger = require("logger")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Trapper = require("ui/trapper")
local _ = require("gettext")

local SyncDecisionMaker = {}

---
-- Checks if both KOReader and Kobo have a book marked as complete.
-- @param kobo_state table: Kobo state with status and percent_read fields.
-- @param kr_percent number: KOReader progress (0-1).
-- @param kr_status string|nil: KOReader status string (complete/finished/reading/etc).
-- @return boolean: True if both sides are marked as complete.
function SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)
    if not kobo_state then
        return false
    end

    local kobo_is_complete = kobo_state.status == "complete" or kobo_state.percent_read >= 100
    local kr_is_complete = kr_percent >= 1.0

    if kr_status == "complete" or kr_status == "finished" then
        kr_is_complete = true
    end

    return kobo_is_complete and kr_is_complete
end

---
-- Formats sync details for user prompt.
-- @param sync_details table: Details with book_title, source_percent, dest_percent, source_time, dest_time.
-- @param is_pull_from_kobo boolean: True if pulling from Kobo.
-- @param is_newer boolean: True if source is newer.
-- @return string: Formatted dialog text.
local function formatSyncPrompt(sync_details, is_pull_from_kobo, is_newer)
    local direction_text = is_pull_from_kobo and "from Kobo" or "to Kobo"
    local state_text = is_newer and "newer" or "older"

    if not sync_details then
        return string.format("Sync %s reading progress %s?\n\n(%s state)", state_text, direction_text, state_text)
    end

    local book_title = sync_details.book_title or "Unknown Book"
    local source_percent = sync_details.source_percent or 0
    local dest_percent = sync_details.dest_percent or 0
    local source_time = sync_details.source_time or 0
    local dest_time = sync_details.dest_time or 0

    local source_time_str = source_time > 0 and os.date("%Y-%m-%d %H:%M", source_time) or "Never"
    local dest_time_str = dest_time > 0 and os.date("%Y-%m-%d %H:%M", dest_time) or "Never"

    return string.format(
        "Book: %s\n\n%s: %d%% (%s)\n%s: %d%% (%s)\n\nSync %s reading progress %s?",
        book_title,
        is_pull_from_kobo and "Kobo" or "KOReader",
        math.floor(source_percent),
        source_time_str,
        is_pull_from_kobo and "KOReader" or "Kobo",
        math.floor(dest_percent),
        dest_time_str,
        state_text,
        direction_text
    )
end

---
-- Shows user confirmation dialog and executes callback if approved.
-- Handles both Trapper (synchronous) and ConfirmBox (asynchronous) contexts.
-- @param is_pull_from_kobo boolean: True if pulling from Kobo.
-- @param is_newer boolean: True if source is newer.
-- @param sync_fn function: Callback to execute if sync is approved.
-- @param sync_details table|nil: Optional sync details for prompt.
local function promptUserForSyncAndExecute(is_pull_from_kobo, is_newer, sync_fn, sync_details)
    local dialog_text = formatSyncPrompt(sync_details, is_pull_from_kobo, is_newer)
    local direction_text = is_pull_from_kobo and "from Kobo" or "to Kobo"
    local state_text = is_newer and "newer" or "older"

    if Trapper:isWrapped() then
        local confirmed = Trapper:confirm(dialog_text, _("No"), _("Yes"))
        logger.dbg(
            "KoboPlugin: User sync confirmation (Trapper):",
            direction_text,
            state_text,
            "result:",
            tostring(confirmed)
        )

        if not confirmed or not sync_fn then
            return
        end

        sync_fn()
        return
    end

    UIManager:show(ConfirmBox:new({
        text = dialog_text,
        ok_text = _("Yes"),
        cancel_text = _("No"),
        ok_callback = function()
            if not sync_fn then
                return
            end

            logger.dbg("KoboPlugin: User approved sync:", direction_text, state_text)
            sync_fn()
        end,
        cancel_callback = function()
            logger.dbg("KoboPlugin: User rejected sync:", direction_text, state_text)
        end,
    }))
end

---
-- Determines if sync should proceed based on user settings.
-- Executes sync_fn if sync is approved.
-- @param plugin table: Plugin instance with settings.
-- @param sync_direction table: SYNC_DIRECTION constants.
-- @param is_pull_from_kobo boolean: True if pulling from Kobo.
-- @param is_newer boolean: True if source is newer.
-- @param sync_fn function: Callback to execute if sync is approved.
-- @param sync_details table|nil: Optional sync details for prompt.
-- @return boolean: True if sync was executed or initiated, false if denied.
function SyncDecisionMaker.syncIfApproved(plugin, sync_direction, is_pull_from_kobo, is_newer, sync_fn, sync_details)
    logger.dbg(
        "KoboPlugin: Evaluating sync approval:",
        is_pull_from_kobo and "FROM Kobo" or "TO Kobo",
        is_newer and "newer" or "older"
    )

    if not plugin or not sync_direction then
        logger.warn("KoboPlugin: Sync settings not configured, denying sync")
        return false
    end

    if is_pull_from_kobo then
        if not plugin.settings.enable_sync_from_kobo then
            logger.dbg("KoboPlugin: Sync FROM Kobo is disabled")
            return false
        end
    else
        if not plugin.settings.enable_sync_to_kobo then
            logger.dbg("KoboPlugin: Sync TO Kobo is disabled")
            return false
        end
    end

    local setting
    if is_pull_from_kobo then
        setting = is_newer and plugin.settings.sync_from_kobo_newer or plugin.settings.sync_from_kobo_older
    else
        setting = is_newer and plugin.settings.sync_to_kobo_newer or plugin.settings.sync_to_kobo_older
    end

    if setting == sync_direction.NEVER then
        logger.dbg("KoboPlugin: Sync denied by user settings")
        return false
    end

    if setting == sync_direction.SILENT then
        logger.dbg("KoboPlugin: Sync silently executed")

        if not sync_fn then
            return true
        end

        sync_fn()
        return true
    end

    if setting == sync_direction.PROMPT then
        logger.dbg(
            "KoboPlugin: Prompting user for sync confirmation. Is_pull_from_kobo:",
            tostring(is_pull_from_kobo),
            "is_newer:",
            tostring(is_newer)
        )

        promptUserForSyncAndExecute(is_pull_from_kobo, is_newer, sync_fn, sync_details)
        return true
    end

    logger.warn("KoboPlugin: Unknown sync direction setting, denying sync")
    return false
end

return SyncDecisionMaker
