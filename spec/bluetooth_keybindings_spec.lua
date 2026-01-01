---
-- Tests for Bluetooth key bindings manager.

describe("BluetoothKeyBindings", function()
    local BluetoothKeyBindings
    local mock_settings
    local instance
    local available_actions_module
    local AVAILABLE_ACTIONS

    setup(function()
        require("spec/helper")
        BluetoothKeyBindings = require("src/bluetooth_keybindings")
        -- Access the available actions module
        available_actions_module = require("src/lib/bluetooth/available_actions")
        AVAILABLE_ACTIONS = available_actions_module.get_all_actions()
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
        instance:setup(function() end, nil)
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

            for _, category in ipairs(AVAILABLE_ACTIONS) do
                for _, action in ipairs(category.actions) do
                    if action.id == "next_page" then
                        has_next_page = true
                    end
                    if action.id == "prev_page" then
                        has_prev_page = true
                    end
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

        it("should load bindings into device_bindings on load", function()
            mock_settings.bluetooth_key_bindings = {
                ["AA:BB:CC:DD:EE:FF"] = {
                    ["BT_PageNext"] = "next_page",
                },
            }

            instance:loadBindings()

            -- Bindings should be in device_bindings
            assert.is_not_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_PageNext"])
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
            test_instance:setup(save_callback, nil)

            test_instance.device_bindings = {
                ["AA:BB:CC:DD:EE:FF"] = {
                    ["BT_Key1"] = "next_page",
                },
            }

            test_instance:saveBindings()

            assert.is_true(save_called)
        end)
    end)

    describe("removeBinding", function()
        it("should remove binding from device_bindings", function()
            -- First add a binding
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = {
                ["BT_TestKey"] = "next_page",
            }

            -- Now remove it
            instance:removeBinding("AA:BB:CC:DD:EE:FF", "BT_TestKey")

            -- Check it was removed
            assert.is_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_TestKey"])
        end)

        it("should handle removing non-existent binding", function()
            -- Should not crash
            instance:removeBinding("AA:BB:CC:DD:EE:FF", "BT_NonExistent")
        end)
    end)

    describe("getActionById", function()
        it("should return action definition for valid ID", function()
            local action = instance:getActionById("Reader:next_page")

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

            -- Clear bindings
            instance:clearDeviceBindings("AA:BB:CC:DD:EE:FF")

            -- Check they're gone
            assert.is_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])
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

        it("should show info message without timeout", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            instance:startKeyCapture("AA:BB:CC:DD:EE:FF", "next_page", function() end)

            assert.is_not_nil(instance.capture_info_message)
            assert.is_table(instance.capture_info_message)
            assert.is_string(instance.capture_info_message.text)
            -- Should have no timeout set
            assert.is_nil(instance.capture_info_message.timeout)
        end)

        it("should track shown message in UIManager", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            instance:startKeyCapture("AA:BB:CC:DD:EE:FF", "next_page", function() end)

            assert.is_true(#UIManager._show_calls > 0)
            local last_show = UIManager._show_calls[#UIManager._show_calls]
            assert.is_not_nil(last_show.widget)
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

        it("should create binding for captured key", function()
            instance:captureKey("BTRight")

            assert.is_not_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BTRight"])
        end)

        it("should set up callback in dismiss_callback and call it when dismissed", function()
            local callback_called = false
            local captured_key = nil
            local captured_action = nil

            instance.capture_callback = function(key, action)
                callback_called = true
                captured_key = key
                captured_action = action
            end

            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            instance:captureKey("BTRight")

            -- Callback should not be called immediately (it's in dismiss_callback)
            assert.is_false(callback_called)
            -- Get the InfoMessage that was shown
            assert.is_true(#UIManager._shown_widgets > 0)
            local info_message = UIManager._shown_widgets[#UIManager._shown_widgets]
            assert.is_not_nil(info_message)
            assert.is_not_nil(info_message.dismiss_callback)

            -- Simulate dismissing the message
            info_message.dismiss_callback()

            -- Now callback should be called
            assert.is_true(callback_called)
            assert.are.equal("BTRight", captured_key)
            assert.are.equal("next_page", captured_action)
        end)

        it("should close info message when key is captured", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            -- Setup capture message
            local msg = { text = "waiting..." }
            instance.capture_info_message = msg
            instance.is_capturing = true
            instance.capture_device_mac = "AA:BB:CC:DD:EE:FF"
            instance.capture_action_id = "next_page"

            instance:captureKey("BTRight")

            -- Check that UIManager:close was called with the message
            assert.is_true(#UIManager._close_calls > 0)
            local close_call = UIManager._close_calls[#UIManager._close_calls]
            assert.are.equal(msg, close_call.widget)
            assert.is_nil(instance.capture_info_message)
        end)

        it("should accept any key including Back when capturing from Bluetooth", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            -- Setup capture message
            local msg = { text = "waiting..." }
            instance.capture_info_message = msg
            instance.is_capturing = true
            instance.capture_device_mac = "AA:BB:CC:DD:EE:FF"
            instance.capture_action_id = "next_page"

            -- Back key from Bluetooth device should be captured as a valid key
            instance:captureKey("Back")

            -- Check that the capture stopped
            assert.is_false(instance.is_capturing)
            -- Back key should be bound since it's from the Bluetooth device
            assert.is_not_nil(instance.device_bindings["AA:BB:CC:DD:EE:FF"])
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["Back"])
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

        it("should close info message when stopping capture", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            instance.is_capturing = true
            local msg = { text = "waiting..." }
            instance.capture_info_message = msg

            instance:stopKeyCapture()

            -- Check that UIManager:close was called with the message
            assert.is_true(#UIManager._close_calls > 0)
            local close_call = UIManager._close_calls[#UIManager._close_calls]
            assert.are.equal(msg, close_call.widget)
            assert.is_nil(instance.capture_info_message)
        end)

        it("should handle stopping capture without message", function()
            instance.is_capturing = true
            instance.capture_info_message = nil

            -- Should not crash
            instance:stopKeyCapture()

            assert.is_false(instance.is_capturing)
            assert.is_nil(instance.capture_info_message)
        end)
    end)

    describe("action definitions", function()
        it("should have valid event names for all actions", function()
            for _, category in ipairs(AVAILABLE_ACTIONS) do
                for _, action in ipairs(category.actions) do
                    assert.is_string(action.id)
                    assert.is_string(action.title)
                    assert.is_string(action.event)
                    -- args can be nil or any value
                end
            end
        end)

        it("should include page navigation actions", function()
            local next_page = instance:getActionById("Reader:next_page")
            local prev_page = instance:getActionById("Reader:prev_page")

            assert.is_not_nil(next_page)
            assert.is_not_nil(prev_page)
            assert.are.equal("GotoViewRel", next_page.event)
            assert.are.equal("GotoViewRel", prev_page.event)
            assert.are.equal(1, next_page.args)
            assert.are.equal(-1, prev_page.args)
        end)

        it("should include chapter navigation actions", function()
            local next_chapter = instance:getActionById("Reader:next_chapter")
            local prev_chapter = instance:getActionById("Reader:prev_chapter")

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
            instance:saveBindings()

            -- Create new instance with same settings
            local new_instance = BluetoothKeyBindings:new({
                settings = mock_settings,
            })
            new_instance:setup(function() end, nil)

            -- Check bindings were loaded
            assert.is_not_nil(new_instance.device_bindings["AA:BB:CC:DD:EE:FF"])
            assert.are.equal("next_page", new_instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_Key1"])
        end)
    end)

    describe("multiple devices", function()
        it("should support bindings for multiple devices", function()
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["BT_Key1"] = "next_page" }
            instance.device_bindings["11:22:33:44:55:66"] = { ["BT_Key2"] = "prev_page" }

            local bindings1 = instance:getDeviceBindings("AA:BB:CC:DD:EE:FF")
            local bindings2 = instance:getDeviceBindings("11:22:33:44:55:66")

            assert.are.equal("next_page", bindings1["BT_Key1"])
            assert.are.equal("prev_page", bindings2["BT_Key2"])
        end)

        it("should allow same key name for different devices", function()
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["BT_KeyA"] = "next_page" }
            instance.device_bindings["11:22:33:44:55:66"] = { ["BT_KeyA"] = "prev_page" }

            -- Both should exist
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BT_KeyA"])
            assert.are.equal("prev_page", instance.device_bindings["11:22:33:44:55:66"]["BT_KeyA"])
        end)
    end)

    describe("device path mapping", function()
        before_each(function()
            -- Reset the path mapping for each test in this section
            instance.device_path_to_address = {}
        end)

        it("should initialize with empty path mapping", function()
            local fresh_instance = BluetoothKeyBindings:new({
                settings = mock_settings,
            })
            fresh_instance:setup(function() end, nil)
            assert.is_table(fresh_instance.device_path_to_address)
            assert.are.same({}, fresh_instance.device_path_to_address)
        end)

        it("should set device path mapping", function()
            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")

            assert.are.equal("AA:BB:CC:DD:EE:FF", instance.device_path_to_address["/dev/input/event4"])
        end)

        it("should handle nil device_path in setDevicePathMapping", function()
            -- Should not crash and not add anything
            instance:setDevicePathMapping(nil, "AA:BB:CC:DD:EE:FF")
            assert.is_nil(instance.device_path_to_address[nil])
        end)

        it("should handle nil device_mac in setDevicePathMapping", function()
            -- Should not crash and not add anything
            instance:setDevicePathMapping("/dev/input/event4", nil)
            assert.is_nil(instance.device_path_to_address["/dev/input/event4"])
        end)

        it("should remove device path mapping", function()
            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")
            instance:removeDevicePathMapping("/dev/input/event4")

            assert.is_nil(instance.device_path_to_address["/dev/input/event4"])
        end)

        it("should remove device path mapping by address", function()
            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")
            instance:setDevicePathMapping("/dev/input/event5", "11:22:33:44:55:66")

            instance:removeDevicePathMappingByAddress("AA:BB:CC:DD:EE:FF")

            assert.is_nil(instance.device_path_to_address["/dev/input/event4"])
            -- Other device should still be mapped
            assert.are.equal("11:22:33:44:55:66", instance.device_path_to_address["/dev/input/event5"])
        end)

        it("should get device path by address", function()
            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")

            local path = instance:getDevicePathByAddress("AA:BB:CC:DD:EE:FF")
            assert.are.equal("/dev/input/event4", path)
        end)

        it("should return nil for unknown address", function()
            -- Ensure no mappings exist
            instance.device_path_to_address = {}
            local path = instance:getDevicePathByAddress("11:22:33:44:55:66")
            assert.is_nil(path)
        end)
    end)

    describe("onBluetoothKeyEvent with device path", function()
        before_each(function()
            -- Reset the path mapping for each test
            instance.device_path_to_address = {}
        end)

        it("should use device path to find correct bindings", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            -- Setup path mapping and bindings
            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["KEY_1"] = "Reader:next_page" }

            -- Trigger event from that device
            instance:onBluetoothKeyEvent(1, 1, { sec = 0, usec = 0 }, "/dev/input/event4")

            -- Should have sent the correct event (GotoViewRel with args=1 for next_page)
            assert.is_true(#UIManager._send_event_calls > 0)
            local event = UIManager._send_event_calls[1].event
            assert.are.equal("GotoViewRel", event.name)
            assert.are.equal(1, event.args[1])
        end)

        it("should execute InputEvent hook to reset autosuspend timer", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            -- Setup path mapping and bindings
            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["KEY_1"] = "next_page" }

            -- Trigger event from that device
            instance:onBluetoothKeyEvent(1, 1, { sec = 0, usec = 0 }, "/dev/input/event4")

            -- Should have executed the InputEvent hook for autosuspend integration
            assert.is_true(#UIManager._event_hook_calls > 0)
            assert.are.equal("InputEvent", UIManager._event_hook_calls[1].event_name)
        end)

        it("should trigger correct action when same key is bound to different actions on different devices", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            -- Setup two devices with same key but different actions
            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")
            instance:setDevicePathMapping("/dev/input/event5", "11:22:33:44:55:66")
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["KEY_1"] = "Reader:next_page" }
            instance.device_bindings["11:22:33:44:55:66"] = { ["KEY_1"] = "Reader:prev_page" }

            -- Trigger from device 1 (event4) - should trigger next_page (GotoViewRel with args=1)
            instance:onBluetoothKeyEvent(1, 1, { sec = 0, usec = 0 }, "/dev/input/event4")

            assert.is_true(#UIManager._send_event_calls > 0)
            local event1 = UIManager._send_event_calls[1].event
            assert.are.equal("GotoViewRel", event1.name)
            assert.are.equal(1, event1.args[1]) -- next_page has args = 1

            UIManager:_reset()

            -- Trigger from device 2 (event5) - should trigger prev_page (GotoViewRel with args=-1)
            instance:onBluetoothKeyEvent(1, 1, { sec = 0, usec = 0 }, "/dev/input/event5")

            assert.is_true(#UIManager._send_event_calls > 0)
            local event2 = UIManager._send_event_calls[1].event
            assert.are.equal("GotoViewRel", event2.name)
            assert.are.equal(-1, event2.args[1]) -- prev_page has args = -1
        end)

        it("should not trigger action for unknown device path", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            -- Setup bindings but no path mapping
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["KEY_1"] = "next_page" }

            -- Trigger event from unknown device
            instance:onBluetoothKeyEvent(1, 1, { sec = 0, usec = 0 }, "/dev/input/event99")

            -- Should NOT trigger (no fallback behavior)
            assert.are.equal(0, #UIManager._send_event_calls)
        end)

        it("should not trigger action for unbound key", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["KEY_1"] = "next_page" }

            -- Trigger unbound key
            instance:onBluetoothKeyEvent(99, 1, { sec = 0, usec = 0 }, "/dev/input/event4")

            -- Should not have sent an event
            assert.are.equal(0, #UIManager._send_event_calls)
        end)

        it("should ignore key release events", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            instance:setDevicePathMapping("/dev/input/event4", "AA:BB:CC:DD:EE:FF")
            instance.device_bindings["AA:BB:CC:DD:EE:FF"] = { ["KEY_1"] = "next_page" }

            -- Trigger key release (value = 0)
            instance:onBluetoothKeyEvent(1, 0, { sec = 0, usec = 0 }, "/dev/input/event4")

            -- Should not have sent an event
            assert.are.equal(0, #UIManager._send_event_calls)
        end)
    end)

    describe("captureKey", function()
        before_each(function()
            instance.is_capturing = true
            instance.capture_device_mac = "AA:BB:CC:DD:EE:FF"
            instance.capture_action_id = "next_page"
            instance.device_path_to_address = {}
        end)

        it("should create binding for captured key", function()
            instance:captureKey("BTRight")

            -- Binding should be created
            assert.are.equal("next_page", instance.device_bindings["AA:BB:CC:DD:EE:FF"]["BTRight"])
        end)

        it("should not modify path mapping (handled by InputDeviceHandler)", function()
            instance:captureKey("BTRight")

            -- Path mapping should remain empty (path mapping is handled by InputDeviceHandler callbacks)
            assert.are.same({}, instance.device_path_to_address)
        end)
    end)

    describe("widget dismissal", function()
        local UIManager
        local mock_input_handler

        before_each(function()
            UIManager = require("ui/uimanager")
            UIManager:_reset()
            UIManager._window_stack = {}

            mock_input_handler = {
                registerKeyEventCallback = function() end,
                registerDeviceOpenCallback = function() end,
                registerDeviceCloseCallback = function() end,
            }

            instance = BluetoothKeyBindings:new({
                settings = { dismiss_widgets_on_button = true },
            })
            instance:setup(function() end, mock_input_handler)
            instance.device_path_to_address["/dev/input/event4"] = "AA:BB:CC:DD:EE:FF"
        end)

        describe("_getTopDismissableWidget", function()
            it("should return nil when window stack is nil", function()
                UIManager._window_stack = nil
                local widget = instance:_getTopDismissableWidget()
                assert.is_nil(widget)
            end)

            it("should return nil when window stack is empty", function()
                UIManager._window_stack = {}
                local widget = instance:_getTopDismissableWidget()
                assert.is_nil(widget)
            end)

            it("should return widget with dismissable flag", function()
                local dismissable_widget = {
                    dismissable = true,
                    toast = false,
                }
                UIManager._window_stack = {
                    { widget = dismissable_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(dismissable_widget, widget)
            end)

            it("should return widget with onTapClose handler", function()
                local tap_close_widget = {
                    onTapClose = function() end,
                }
                UIManager._window_stack = {
                    { widget = tap_close_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(tap_close_widget, widget)
            end)

            it("should return widget with onTapCloseAllMenus handler", function()
                local menu_widget = {
                    onTapCloseAllMenus = function() end,
                }
                UIManager._window_stack = {
                    { widget = menu_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(menu_widget, widget)
            end)

            it("should return widget with onTapCloseMenu handler", function()
                local config_widget = {
                    onTapCloseMenu = function() end,
                }
                UIManager._window_stack = {
                    { widget = config_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(config_widget, widget)
            end)

            it("should skip toast widgets", function()
                local dismissable_widget = {
                    dismissable = true,
                    toast = false,
                }
                local toast_widget = {
                    toast = true,
                }
                UIManager._window_stack = {
                    { widget = dismissable_widget },
                    { widget = toast_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(dismissable_widget, widget)
            end)

            it("should skip multiple toast widgets", function()
                local dismissable_widget = {
                    dismissable = true,
                }
                local toast1 = { toast = true }
                local toast2 = { toast = true }
                UIManager._window_stack = {
                    { widget = dismissable_widget },
                    { widget = toast1 },
                    { widget = toast2 },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(dismissable_widget, widget)
            end)

            it("should skip blocklisted ReaderUI widget", function()
                local reader_widget = {
                    name = "ReaderUI",
                    dismissable = true,
                }
                UIManager._window_stack = {
                    { widget = reader_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.is_nil(widget)
            end)

            it("should skip blocklisted FileManager widget", function()
                local file_manager = {
                    name = "FileManager",
                    onTapClose = function() end,
                }
                UIManager._window_stack = {
                    { widget = file_manager },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.is_nil(widget)
            end)

            it("should return dismissable widget above blocklisted widget", function()
                local dismissable_widget = {
                    dismissable = true,
                }
                local reader_widget = {
                    name = "ReaderUI",
                }
                UIManager._window_stack = {
                    { widget = reader_widget },
                    { widget = dismissable_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(dismissable_widget, widget)
            end)

            it("should return nil for non-dismissable widget without handlers", function()
                local non_dismissable = {
                    dismissable = false,
                }
                UIManager._window_stack = {
                    { widget = non_dismissable },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.is_nil(widget)
            end)

            it("should return topmost dismissable widget", function()
                local widget1 = { dismissable = true }
                local widget2 = { onTapClose = function() end }
                UIManager._window_stack = {
                    { widget = widget1 },
                    { widget = widget2 },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(widget2, widget)
            end)

            it("should prioritize dismissable flag over tap-close handler", function()
                local widget_with_flag = { dismissable = true }
                local widget_with_handler = { onTapClose = function() end }
                UIManager._window_stack = {
                    { widget = widget_with_handler },
                    { widget = widget_with_flag },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(widget_with_flag, widget)
            end)

            it("should stop at first non-dismissable non-toast widget", function()
                local dismissable_widget = {
                    dismissable = true,
                }
                local non_dismissable_widget = {
                    dismissable = false,
                }
                local toast_widget = {
                    toast = true,
                }
                UIManager._window_stack = {
                    { widget = dismissable_widget },
                    { widget = non_dismissable_widget },
                    { widget = toast_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.is_nil(widget)
            end)

            it("should detect menu widget (onTapCloseAllMenus)", function()
                local menu_widget = {
                    name = "Menu",
                    onTapCloseAllMenus = function() end,
                }
                UIManager._window_stack = {
                    { widget = menu_widget },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(menu_widget, widget)
            end)

            it("should handle complex stack with multiple widget types", function()
                local reader = { name = "ReaderUI" }
                local menu = { onTapCloseAllMenus = function() end }
                local toast = { toast = true }
                local dialog = { dismissable = true }
                UIManager._window_stack = {
                    { widget = reader },
                    { widget = menu },
                    { widget = toast },
                    { widget = dialog },
                }

                local widget = instance:_getTopDismissableWidget()
                assert.are.equal(dialog, widget)
            end)
        end)

        describe("onBluetoothKeyEvent with dismissal", function()
            it("should dismiss InfoMessage with bound button", function()
                instance.device_bindings = {
                    ["AA:BB:CC:DD:EE:FF"] = {
                        KEY_16 = "Reader:next_page",
                    },
                }

                local info_widget = {
                    modal = true,
                    dismissable = true,
                    dismiss_callback = spy.new(function() end),
                }
                UIManager._window_stack = {
                    { widget = info_widget },
                }

                instance:onBluetoothKeyEvent(16, 1, {}, "/dev/input/event4")

                assert.are.equal(1, #UIManager._close_calls)
                assert.are.equal(info_widget, UIManager._close_calls[1].widget)
                assert.spy(info_widget.dismiss_callback).was_called()
                assert.are.equal(0, #UIManager._send_event_calls)
            end)

            it("should dismiss InfoMessage with unbound button", function()
                local info_widget = {
                    modal = true,
                    dismissable = true,
                }
                UIManager._window_stack = {
                    { widget = info_widget },
                }

                instance:onBluetoothKeyEvent(99, 1, {}, "/dev/input/event4")

                assert.are.equal(1, #UIManager._close_calls)
                assert.are.equal(info_widget, UIManager._close_calls[1].widget)
            end)

            it("should execute normal action when no widget visible", function()
                instance.device_bindings = {
                    ["AA:BB:CC:DD:EE:FF"] = {
                        KEY_16 = "Reader:next_page",
                    },
                }

                UIManager._window_stack = {}

                instance:onBluetoothKeyEvent(16, 1, {}, "/dev/input/event4")

                assert.are.equal(1, #UIManager._send_event_calls)
            end)

            it("should not dismiss non-dismissable widget", function()
                local non_dismissable = {
                    modal = true,
                    dismissable = false,
                }
                UIManager._window_stack = {
                    { widget = non_dismissable },
                }

                instance:onBluetoothKeyEvent(16, 1, {}, "/dev/input/event4")

                assert.are.equal(0, #UIManager._close_calls)
            end)

            it("should respect setting toggle", function()
                instance.settings.dismiss_widgets_on_button = false

                local info_widget = {
                    modal = true,
                    dismissable = true,
                }
                UIManager._window_stack = {
                    { widget = info_widget },
                }

                instance:onBluetoothKeyEvent(16, 1, {}, "/dev/input/event4")

                assert.are.equal(0, #UIManager._close_calls)
            end)

            it("should call dismiss_callback if exists", function()
                local callback = spy.new(function() end)
                local info_widget = {
                    modal = true,
                    dismissable = true,
                    dismiss_callback = callback,
                }
                UIManager._window_stack = {
                    { widget = info_widget },
                }

                instance:onBluetoothKeyEvent(16, 1, {}, "/dev/input/event4")

                assert.spy(callback).was_called()
            end)

            it("should not crash if dismiss_callback is nil", function()
                local info_widget = {
                    modal = true,
                    dismissable = true,
                    dismiss_callback = nil,
                }
                UIManager._window_stack = {
                    { widget = info_widget },
                }

                assert.has_no.errors(function()
                    instance:onBluetoothKeyEvent(16, 1, {}, "/dev/input/event4")
                end)
            end)

            it("should not dismiss during capture mode", function()
                instance.is_capturing = true
                instance.capture_device_mac = "AA:BB:CC:DD:EE:FF"
                instance.capture_action_id = "Reader:next_page"

                local info_widget = {
                    modal = true,
                    dismissable = true,
                }
                UIManager._window_stack = {
                    { widget = info_widget },
                }

                instance:onBluetoothKeyEvent(16, 1, {}, "/dev/input/event4")

                assert.are.equal(0, #UIManager._close_calls)
                assert.is_false(instance.is_capturing)
            end)
        end)
    end)
end)
