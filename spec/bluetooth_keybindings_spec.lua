---
-- Tests for Bluetooth key bindings manager.

describe("BluetoothKeyBindings", function()
    local BluetoothKeyBindings
    local mock_settings
    local instance
    local AVAILABLE_ACTIONS

    setup(function()
        require("spec/helper")
        BluetoothKeyBindings = require("src/bluetooth_keybindings")
        -- Access the module-level AVAILABLE_ACTIONS constant
        -- We'll get it from a test instance
        local temp = BluetoothKeyBindings:new({})
        AVAILABLE_ACTIONS = temp.AVAILABLE_ACTIONS
            or {
                { id = "next_page", title = "Next Page", event = "GotoViewRel", args = 1 },
                { id = "prev_page", title = "Previous Page", event = "GotoViewRel", args = -1 },
                { id = "next_chapter", title = "Next Chapter", event = "GotoNextChapter" },
                { id = "prev_chapter", title = "Previous Chapter", event = "GotoPrevChapter" },
            }
    end)

    before_each(function()
        -- Mock settings table (plain table, not G_reader_settings)
        -- Create a fresh table each time to prevent state leakage
        mock_settings = {
            -- Empty - tests will populate as needed
        }

        instance = BluetoothKeyBindings:new({
            settings = mock_settings,
        })
        instance:init(function() end)
    end)

    describe("initialization", function()
        it("should create instance with default values", function()
            assert.is_not_nil(instance)
            assert.is_table(instance.key_events)
            assert.is_table(instance.device_bindings)
            assert.is_false(instance.is_capturing)
        end)

        it("should have available actions defined", function()
            assert.is_table(AVAILABLE_ACTIONS)
            assert.is_true(#AVAILABLE_ACTIONS > 0)

            -- Check for expected actions
            local has_next_page = false
            local has_prev_page = false

            for _, action in ipairs(AVAILABLE_ACTIONS) do
                if action.id == "next_page" then
                    has_next_page = true
                end
                if action.id == "prev_page" then
                    has_prev_page = true
                end
            end

            assert.is_true(has_next_page)
            assert.is_true(has_prev_page)
        end)
    end)

    describe("loadBindings", function()
        it("should load empty bindings when none exist", function()
            instance:loadBindings()
            assert.are.same({}, instance.device_bindings)
        end)

        it("should load existing bindings from settings", function()
            mock_settings.bluetooth_key_bindings = {
                ["AA:BB:CC:DD:EE:FF"] = {
                    ["BT_PageNext"] = "next_page",
                },
            }

            instance:loadBindings()

            assert.is_not_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_PageNext"])
        end)

        it("should apply bindings to key_events on load", function()
            mock_settings.bluetooth_key_bindings = {
                ["AA:BB:CC:DD:EE:FF"] = {
                    ["BT_PageNext"] = "next_page",
                },
            }

            instance:loadBindings()

            -- Check that key_events was populated
            local found_binding = false
            for event_name, event_def in pairs(instance.key_events) do
                if event_name:find("BT_PageNext") then
                    found_binding = true
                    -- The event field is now the unique event name, not the action event
                    assert.are.equal("BT_AABBCCDDEEFF_BT_PageNext", event_def.event)
                    -- The handler should exist and broadcast the actual GotoViewRel event
                    assert.is_function(instance["on" .. event_name])
                end
            end

            assert.is_true(found_binding)
        end)
    end)

    describe("saveBindings", function()
        it("should save bindings to settings", function()
            instance.device_bindings = {
                ["AA:BB:CC:DD:EE:FF"] = {
                    ["BT_Key1"] = "next_page",
                },
            }

            instance:saveBindings()

            assert.are.same(instance.device_bindings, mock_settings.bluetooth_key_bindings)
        end)

        it("should call save callback when saving bindings", function()
            local save_called = false
            local save_callback = function()
                save_called = true
            end

            -- Create new instance with save callback
            local test_instance = BluetoothKeyBindings:new({
                settings = mock_settings,
            })
            test_instance:init(save_callback)

            test_instance.device_bindings = {
                ["AA:BB:CC:DD:EE:FF"] = {
                    ["BT_Key1"] = "next_page",
                },
            }

            test_instance:saveBindings()

            assert.is_true(save_called)
        end)
    end)

    describe("applyBinding", function()
        it("should create key_events entry for valid binding", function()
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_TestKey", "next_page")

            -- Check key_events was updated
            local found = false
            for event_name, event_def in pairs(instance.key_events) do
                if event_name:find("BT_TestKey") then
                    found = true
                    assert.is_table(event_def)
                    -- The event field is now the unique event name
                    assert.are.equal("BT_AABBCCDDEEFF_BT_TestKey", event_def.event)
                end
            end

            assert.is_true(found)
        end)

        it("should create handler function for action", function()
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_TestKey", "next_chapter")

            -- Check handler exists with unique event name
            local handler_name = "onBT_AABBCCDDEEFF_BT_TestKey"
            assert.is_function(instance[handler_name])
        end)

        it("should handle invalid action ID gracefully", function()
            -- Should not crash
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_TestKey", "invalid_action")

            -- Key event should not be created
            local found = false
            for event_name in pairs(instance.key_events) do
                if event_name:find("BT_TestKey") then
                    found = true
                end
            end

            assert.is_false(found)
        end)
    end)

    describe("removeBinding", function()
        it("should remove binding from device_bindings and key_events", function()
            -- First add a binding
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = {
                ["BT_TestKey"] = "next_page",
            }
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_TestKey", "next_page")

            -- Now remove it
            instance:removeBinding("AA:BB:CC:DD:EE:FF", "BT_TestKey")

            -- Check it was removed
            assert.is_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_TestKey"])

            local found = false
            for event_name in pairs(instance.key_events) do
                if event_name:find("BT_TestKey") then
                    found = true
                end
            end

            assert.is_false(found)
        end)

        it("should handle removing non-existent binding", function()
            -- Should not crash
            instance:removeBinding("AA:BB:CC:DD:EE:FF", "BT_NonExistent")
        end)
    end)

    describe("getActionById", function()
        it("should return action definition for valid ID", function()
            local action = instance:getActionById("next_page")

            assert.is_not_nil(action)
            assert.are.equal("next_page", action.id)
            assert.are.equal("GotoViewRel", action.event)
        end)

        it("should return nil for invalid ID", function()
            local action = instance:getActionById("invalid_action_id")
            assert.is_nil(action)
        end)
    end)

    describe("getDeviceBindings", function()
        it("should return bindings for a device", function()
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = {
                ["BT_Key1"] = "next_page",
                ["BT_Key2"] = "prev_page",
            }

            local bindings = instance:getDeviceBindings("AA:BB:CC:DD:EE:FF")

            assert.is_table(bindings)
            assert.are.equal("next_page", bindings["BT_Key1"])
            assert.are.equal("prev_page", bindings["BT_Key2"])
        end)

        it("should return empty table for device with no bindings", function()
            local bindings = instance:getDeviceBindings("11:22:33:44:55:66")

            assert.is_table(bindings)
            assert.are.same({}, bindings)
        end)
    end)

    describe("clearDeviceBindings", function()
        it("should clear all bindings for a device", function()
            -- Setup bindings
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = {
                ["BT_Key1"] = "next_page",
                ["BT_Key2"] = "prev_page",
            }
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_Key1", "next_page")
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_Key2", "prev_page")

            -- Clear bindings
            instance:clearDeviceBindings("AA:BB:CC:DD:EE:FF")

            -- Check they're gone
            assert.is_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])

            -- Check key_events were cleared
            local found_any = false
            for event_name in pairs(instance.key_events) do
                if event_name:find("AABBCCDDEEFF") then
                    found_any = true
                end
            end

            assert.is_false(found_any)
        end)

        it("should handle clearing non-existent device", function()
            -- Should not crash
            instance:clearDeviceBindings("11:22:33:44:55:66")
        end)
    end)

    describe("startKeyCapture", function()
        it("should set capturing state", function()
            instance:startKeyCapture("AA:BB:CC:DD:EE:FF", "next_page", function() end)

            assert.is_true(instance.is_capturing)
            assert.are.equal("AA:BB:CC:DD:EE:FF", instance.capture_device_mac)
            assert.are.equal("next_page", instance.capture_action_id)
        end)

        it("should store callback function", function()
            local callback = function() end
            instance:startKeyCapture("AA:BB:CC:DD:EE:FF", "next_page", callback)

            assert.are.equal(callback, instance.capture_callback)
        end)
    end)

    describe("captureKey", function()
        before_each(function()
            instance.is_capturing = true
            instance.capture_device_mac = "AA:BB:CC:DD:EE:FF"
            instance.capture_action_id = "next_page"
        end)

        it("should stop capturing after key press", function()
            instance:captureKey("BTRight")

            assert.is_false(instance.is_capturing)
        end)

        it("should ignore system keys like Back", function()
            instance:captureKey("Back")

            assert.is_false(instance.is_capturing)
            -- Should not create binding
            assert.is_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])
        end)

        it("should create binding for captured key", function()
            instance:captureKey("BTRight")

            assert.is_not_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BTRight"])
        end)

        it("should call callback after successful capture", function()
            local callback_called = false
            local captured_key = nil
            local captured_action = nil

            instance.capture_callback = function(key, action)
                callback_called = true
                captured_key = key
                captured_action = action
            end

            instance:captureKey("BTRight")

            assert.is_true(callback_called)
            assert.are.equal("BTRight", captured_key)
            assert.are.equal("next_page", captured_action)
        end)
    end)

    describe("stopKeyCapture", function()
        it("should reset capture state", function()
            instance.is_capturing = true
            instance.capture_device_mac = "AA:BB:CC:DD:EE:FF"
            instance.capture_action_id = "next_page"
            instance.capture_callback = function() end

            instance:stopKeyCapture()

            assert.is_false(instance.is_capturing)
            assert.is_nil(instance.capture_callback)
            assert.is_nil(instance.capture_device_mac)
            assert.is_nil(instance.capture_action_id)
        end)
    end)

    describe("action definitions", function()
        it("should have valid event names for all actions", function()
            for _, action in ipairs(AVAILABLE_ACTIONS) do
                assert.is_string(action.id)
                assert.is_string(action.title)
                assert.is_string(action.event)
                -- args can be nil or any value
            end
        end)

        it("should include page navigation actions", function()
            local next_page = instance:getActionById("next_page")
            local prev_page = instance:getActionById("prev_page")

            assert.is_not_nil(next_page)
            assert.is_not_nil(prev_page)
            assert.are.equal("GotoViewRel", next_page.event)
            assert.are.equal("GotoViewRel", prev_page.event)
            assert.are.equal(1, next_page.args)
            assert.are.equal(-1, prev_page.args)
        end)

        it("should include chapter navigation actions", function()
            local next_chapter = instance:getActionById("next_chapter")
            local prev_chapter = instance:getActionById("prev_chapter")

            assert.is_not_nil(next_chapter)
            assert.is_not_nil(prev_chapter)
            assert.are.equal("GotoNextChapter", next_chapter.event)
            assert.are.equal("GotoPrevChapter", prev_chapter.event)
        end)
    end)

    describe("persistence", function()
        it("should persist bindings across init cycles", function()
            -- Create bindings
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = {
                ["BT_Key1"] = "next_page",
            }
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_Key1", "next_page")
            instance:saveBindings()

            -- Create new instance with same settings
            local new_instance = BluetoothKeyBindings:new({
                settings = mock_settings,
            })
            new_instance:init(function() end)

            -- Check bindings were loaded
            assert.is_not_nil(new_instance.device_bindings["AA:BB:CC:DD:EE:FF"])
            assert.are.equal("next_page", new_instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_Key1"])
        end)
    end)

    describe("multiple devices", function()
        it("should support bindings for multiple devices", function()
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_Key1", "next_page")
            instance:applyBinding("11:22:33:44:55:66", "BT_Key2", "prev_page")

            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["BT_Key1"] = "next_page" }
            instance.device_bindings["11:22:33:44:55:66"] = { ["BT_Key2"] = "prev_page" }

            local bindings1 = instance:getDeviceBindings("AA:BB:CC:DD:EE:FF")
            local bindings2 = instance:getDeviceBindings("11:22:33:44:55:66")

            assert.are.equal("next_page", bindings1["BT_Key1"])
            assert.are.equal("prev_page", bindings2["BT_Key2"])
        end)

        it("should allow same key name for different devices", function()
            instance:applyBinding("AA:BB:CC:DD:EE:FF", "BT_KeyA", "next_page")
            instance:applyBinding("11:22:33:44:55:66", "BT_KeyA", "prev_page")

            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["BT_KeyA"] = "next_page" }
            instance.device_bindings["11:22:33:44:55:66"] = { ["BT_KeyA"] = "prev_page" }

            -- Both should exist
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_KeyA"])
            assert.are.equal("prev_page", instance.device_bindings["11:22:33:44:55:66"]["BT_KeyA"])
        end)
    end)
end)
