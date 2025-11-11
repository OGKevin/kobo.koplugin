---
-- Unit tests for SyncDecisionMaker module.
-- These tests use the enhanced UI mocks from helper.lua that capture call information.

describe("SyncDecisionMaker", function()
    local SyncDecisionMaker
    local helper
    local UIManager, ConfirmBox, Trapper

    setup(function()
        -- Load helper first to set up base mocks
        helper = require("spec/helper")
        -- Load UI mocks - they're enhanced with call tracking by helper.lua
        UIManager = require("ui/uimanager")
        ConfirmBox = require("ui/widget/confirmbox")
        Trapper = require("ui/trapper")
        -- Now load the module under test - it will use the mocks we just loaded
        SyncDecisionMaker = require("lib/sync_decision_maker")
    end)

    before_each(function()
        -- Reset UI mock call tracking before each test
        helper.resetUIMocks()
    end)

    describe("areBothSidesComplete", function()
        it("should return true when both sides are complete at 100%", function()
            local kobo_state = { status = "complete", percent_read = 100 }
            local kr_percent = 1.0
            local kr_status = "complete"

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_true(result)
        end)

        it("should return true when Kobo is complete and KOReader has status='complete' at 80%", function()
            local kobo_state = { status = "complete", percent_read = 100 }
            local kr_percent = 0.8
            local kr_status = "complete"

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_true(result)
        end)

        it("should return true when Kobo is complete and KOReader has status='finished'", function()
            local kobo_state = { status = "complete", percent_read = 100 }
            local kr_percent = 0.99
            local kr_status = "finished"

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_true(result)
        end)

        it("should return true when Kobo percent_read >= 100 even if status is not 'complete'", function()
            local kobo_state = { status = "reading", percent_read = 100 }
            local kr_percent = 1.0
            local kr_status = "complete"

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_true(result)
        end)

        it("should return false when only Kobo is complete", function()
            local kobo_state = { status = "complete", percent_read = 100 }
            local kr_percent = 0.5
            local kr_status = "reading"

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_false(result)
        end)

        it("should return false when only KOReader is complete", function()
            local kobo_state = { status = "reading", percent_read = 50 }
            local kr_percent = 1.0
            local kr_status = "complete"

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_false(result)
        end)

        it("should return false when neither side is complete", function()
            local kobo_state = { status = "reading", percent_read = 50 }
            local kr_percent = 0.6
            local kr_status = "reading"

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_false(result)
        end)

        it("should return false when kobo_state is nil", function()
            local result = SyncDecisionMaker.areBothSidesComplete(nil, 1.0, "complete")

            assert.is_false(result)
        end)

        it("should handle nil kr_status gracefully", function()
            local kobo_state = { status = "complete", percent_read = 100 }
            local kr_percent = 1.0
            local kr_status = nil

            local result = SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status)

            assert.is_true(result)
        end)
    end)

    describe("formatSyncPrompt text formatting (via Trapper.confirm)", function()
        it("should format prompt without sync_details", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1, -- PROMPT
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            local sync_fn = function()
                sync_called = true
            end

            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                true, -- is_pull_from_kobo
                true, -- is_newer
                sync_fn,
                nil -- no sync_details
            )

            -- Check that Trapper.confirm was called
            assert.equals(1, #Trapper._confirm_calls)
            local call = Trapper._confirm_calls[1]
            assert.is_not_nil(call.text)
            assert.is_true(call.text:match("Sync newer reading progress from Kobo%?") ~= nil)
            assert.is_true(call.text:match("%(newer state%)") ~= nil)
        end)

        it("should format prompt with full sync_details for newer pull from Kobo", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1, -- PROMPT
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_details = {
                book_title = "Test Book",
                source_percent = 75,
                dest_percent = 50,
                source_time = 1699500000,
                dest_time = 1699400000,
            }

            local sync_called = false
            local sync_fn = function()
                sync_called = true
            end

            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                true, -- is_pull_from_kobo
                true, -- is_newer
                sync_fn,
                sync_details
            )

            -- Check that Trapper.confirm was called with expected text
            assert.equals(1, #Trapper._confirm_calls)
            local call = Trapper._confirm_calls[1]
            assert.is_not_nil(call.text)
            assert.is_true(call.text:match("Book: Test Book") ~= nil)
            assert.is_true(call.text:match("Kobo: 75%%") ~= nil)
            assert.is_true(call.text:match("KOReader: 50%%") ~= nil)
            assert.is_true(call.text:match("Sync newer reading progress from Kobo%?") ~= nil)
        end)

        it("should format prompt for older push to Kobo", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1,
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1, -- PROMPT
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_details = {
                book_title = "Another Book",
                source_percent = 30,
                dest_percent = 60,
                source_time = 1699300000,
                dest_time = 1699500000,
            }

            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                false, -- is_pull_from_kobo (push TO Kobo)
                false, -- is_newer (older)
                function() end,
                sync_details
            )

            -- Check that Trapper.confirm was called with expected text
            assert.equals(1, #Trapper._confirm_calls)
            local call = Trapper._confirm_calls[1]
            assert.is_not_nil(call.text)
            assert.is_true(call.text:match("Book: Another Book") ~= nil)
            assert.is_true(call.text:match("KOReader: 30%%") ~= nil)
            assert.is_true(call.text:match("Kobo: 60%%") ~= nil)
            assert.is_true(call.text:match("Sync older reading progress to Kobo%?") ~= nil)
        end)

        it("should handle sync_details with zero timestamps gracefully", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1,
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_details = {
                book_title = "Never Read",
                source_percent = 0,
                dest_percent = 0,
                source_time = 0,
                dest_time = 0,
            }

            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                true, -- is_pull_from_kobo
                true, -- is_newer
                function() end,
                sync_details
            )

            -- Check the text was formatted
            assert.equals(1, #Trapper._confirm_calls)
            local call = Trapper._confirm_calls[1]
            assert.is_not_nil(call.text)
            assert.is_true(call.text:match("Never Read") ~= nil or call.text:match("0%%") ~= nil)
        end)
    end)

    describe("promptUserForSyncAndExecute via Trapper", function()
        it("should call Trapper.confirm when wrapped", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1, -- PROMPT
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            -- Trapper is wrapped by default in tests
            local sync_called = false
            SyncDecisionMaker.syncIfApproved(mock_plugin, SYNC_DIRECTION, true, true, function()
                sync_called = true
            end, nil)

            -- Verify Trapper.confirm was called
            assert.equals(1, #Trapper._confirm_calls)
            -- User confirmed (default mock behavior)
            assert.is_true(sync_called)
        end)

        it("should handle user rejection", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1, -- PROMPT
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            -- Configure Trapper to return false (user rejects)
            Trapper._confirm_return_value = false

            local sync_called = false
            local result = SyncDecisionMaker.syncIfApproved(mock_plugin, SYNC_DIRECTION, true, true, function()
                sync_called = true
            end, nil)

            -- Verify Trapper.confirm was called
            assert.equals(1, #Trapper._confirm_calls)
            -- User rejected, so sync should not be called
            assert.is_false(sync_called)
            -- But the prompt was shown, so result is true
            assert.is_true(result)
        end)
    end)

    describe("promptUserForSyncAndExecute via UIManager (not wrapped)", function()
        it("should use UIManager.show when not in Trapper context", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1, -- PROMPT
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            -- Configure Trapper to not be wrapped
            Trapper._is_wrapped = false

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(mock_plugin, SYNC_DIRECTION, true, true, function()
                sync_called = true
            end, nil)

            -- Verify UIManager.show was called instead of Trapper.confirm
            assert.equals(0, #Trapper._confirm_calls)
            assert.equals(1, #UIManager._show_calls)
            -- Verify a ConfirmBox was created
            assert.equals(1, #ConfirmBox._instances)
            local confirmbox = ConfirmBox._instances[1]
            assert.is_not_nil(confirmbox.text)
            assert.is_true(confirmbox.text:match("Sync") ~= nil)
        end)

        it("should execute ok_callback when user confirms via UIManager", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 1, -- PROMPT
                    sync_from_kobo_older = 1,
                    sync_to_kobo_newer = 1,
                    sync_to_kobo_older = 1,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            -- Configure Trapper to not be wrapped
            Trapper._is_wrapped = false

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(mock_plugin, SYNC_DIRECTION, true, true, function()
                sync_called = true
            end, nil)

            -- Get the ConfirmBox that was created
            assert.equals(1, #ConfirmBox._instances)
            local confirmbox = ConfirmBox._instances[1]
            assert.is_not_nil(confirmbox.ok_callback)

            -- Simulate user clicking OK
            confirmbox.ok_callback()

            -- Verify sync was called
            assert.is_true(sync_called)
        end)
    end)

    describe("syncIfApproved decision logic", function()
        it("should execute sync immediately with SILENT", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 2, -- SILENT
                    sync_from_kobo_older = 2,
                    sync_to_kobo_newer = 2,
                    sync_to_kobo_older = 2,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            local result = SyncDecisionMaker.syncIfApproved(mock_plugin, SYNC_DIRECTION, true, true, function()
                sync_called = true
            end, nil)

            -- No prompt should be shown
            assert.equals(0, #Trapper._confirm_calls)
            assert.equals(0, #UIManager._show_calls)
            -- Sync should be executed
            assert.is_true(sync_called)
            assert.is_true(result)
        end)

        it("should not execute sync with NEVER", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 3, -- NEVER
                    sync_from_kobo_older = 3,
                    sync_to_kobo_newer = 3,
                    sync_to_kobo_older = 3,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            local result = SyncDecisionMaker.syncIfApproved(mock_plugin, SYNC_DIRECTION, true, true, function()
                sync_called = true
            end, nil)

            -- No prompt should be shown
            assert.equals(0, #Trapper._confirm_calls)
            assert.equals(0, #UIManager._show_calls)
            -- Sync should NOT be executed
            assert.is_false(sync_called)
            assert.is_false(result)
        end)

        it("should respect sync_from_kobo_newer setting", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 2, -- SILENT for newer
                    sync_from_kobo_older = 3, -- NEVER for older
                    sync_to_kobo_newer = 2,
                    sync_to_kobo_older = 2,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                true, -- pull from Kobo
                true, -- newer
                function()
                    sync_called = true
                end,
                nil
            )

            -- Should sync silently (newer from Kobo)
            assert.is_true(sync_called)
        end)

        it("should respect sync_from_kobo_older setting", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 2, -- SILENT for newer
                    sync_from_kobo_older = 3, -- NEVER for older
                    sync_to_kobo_newer = 2,
                    sync_to_kobo_older = 2,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                true, -- pull from Kobo
                false, -- older
                function()
                    sync_called = true
                end,
                nil
            )

            -- Should NOT sync (older from Kobo set to NEVER)
            assert.is_false(sync_called)
        end)

        it("should respect sync_to_kobo_newer setting", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 2,
                    sync_from_kobo_older = 2,
                    sync_to_kobo_newer = 2, -- SILENT for newer to Kobo
                    sync_to_kobo_older = 3, -- NEVER for older to Kobo
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                false, -- push to Kobo
                true, -- newer
                function()
                    sync_called = true
                end,
                nil
            )

            -- Should sync silently (newer to Kobo)
            assert.is_true(sync_called)
        end)

        it("should respect sync_to_kobo_older setting", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 2,
                    sync_from_kobo_older = 2,
                    sync_to_kobo_newer = 2, -- SILENT for newer to Kobo
                    sync_to_kobo_older = 3, -- NEVER for older to Kobo
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                false, -- push to Kobo
                false, -- older
                function()
                    sync_called = true
                end,
                nil
            )

            -- Should NOT sync (older to Kobo set to NEVER)
            assert.is_false(sync_called)
        end)

        it("should not sync when enable_sync_from_kobo is false", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = false, -- Disabled
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = 2,
                    sync_from_kobo_older = 2,
                    sync_to_kobo_newer = 2,
                    sync_to_kobo_older = 2,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                true, -- pull from Kobo
                true,
                function()
                    sync_called = true
                end,
                nil
            )

            -- Should NOT sync (sync from Kobo is disabled)
            assert.is_false(sync_called)
        end)

        it("should not sync when enable_sync_to_kobo is false", function()
            local mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = false, -- Disabled
                    sync_from_kobo_newer = 2,
                    sync_from_kobo_older = 2,
                    sync_to_kobo_newer = 2,
                    sync_to_kobo_older = 2,
                },
            }
            local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

            local sync_called = false
            SyncDecisionMaker.syncIfApproved(
                mock_plugin,
                SYNC_DIRECTION,
                false, -- push to Kobo
                true,
                function()
                    sync_called = true
                end,
                nil
            )

            -- Should NOT sync (sync to Kobo is disabled)
            assert.is_false(sync_called)
        end)
    end)
end)
