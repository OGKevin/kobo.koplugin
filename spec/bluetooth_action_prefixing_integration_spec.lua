---
-- Integration tests for Bluetooth action ID prefixing workflow.
-- Tests the complete flow from action loading to event triggering.

describe("Bluetooth Action ID Prefixing Integration", function()
    local BluetoothKeyBindings
    local AvailableActions
    local instance

    setup(function()
        require("spec/helper")
        BluetoothKeyBindings = require("src/bluetooth_keybindings")
        AvailableActions = require("src/lib/bluetooth/available_actions")
    end)

    before_each(function()
        instance = BluetoothKeyBindings:new({ settings = {} })
        instance:setup(function() end, nil)
    end)

    describe("action ID prefixing", function()
        it("should build action lookup map with prefixed IDs", function()
            -- Verify that actions are accessible via prefixed IDs
            local reader_next_page = instance:getActionById("Reader:next_page")
            local reader_prev_page = instance:getActionById("Reader:prev_page")

            assert.is_not_nil(reader_next_page)
            assert.is_not_nil(reader_prev_page)

            -- Verify the base action properties are preserved
            assert.are.equal("next_page", reader_next_page.id)
            assert.are.equal("prev_page", reader_prev_page.id)
        end)

        it("should not find actions by unprefixed ID", function()
            local action = instance:getActionById("next_page")
            assert.is_nil(action)
        end)

        it("should differentiate actions with same ID in different categories", function()
            local reader_action = instance:getActionById("Reader:next_page")
            assert.is_not_nil(reader_action)

            local wrong_prefix = instance:getActionById("General:next_page")
            assert.is_nil(wrong_prefix)
        end)
    end)

    describe("device bindings with prefixed IDs", function()
        it("should store and retrieve bindings with prefixed IDs", function()
            local device_mac = "AA:BB:CC:DD:EE:FF"
            local key_name = "KEY_PAGEDOWN"
            local prefixed_action_id = "Reader:next_page"

            -- Set binding
            instance.device_bindings[device_mac] = {
                [key_name] = prefixed_action_id,
            }

            -- Retrieve binding
            local bindings = instance:getDeviceBindings(device_mac)
            assert.are.equal(prefixed_action_id, bindings[key_name])

            -- Verify the action can be looked up
            local action = instance:getActionById(bindings[key_name])
            assert.is_not_nil(action)
            assert.are.equal("GotoViewRel", action.event)
        end)

        it("should trigger correct event using prefixed action ID", function()
            local UIManager = require("ui/uimanager")
            UIManager:_reset()

            local device_mac = "AA:BB:CC:DD:EE:FF"
            local device_path = "/dev/input/event4"
            local key_code = 109

            -- Setup device mapping
            instance:setDevicePathMapping(device_path, device_mac)

            -- Bind key to prefixed action ID
            -- Key name is "KEY_" + key_code
            instance.device_bindings[device_mac] = {
                ["KEY_109"] = "Reader:next_page",
            }

            -- Simulate key event with key_code 109
            instance:onBluetoothKeyEvent(key_code, 1, { sec = 0, usec = 0 }, device_path)

            -- Verify event was sent
            assert.is_true(#UIManager._send_event_calls > 0)
            local event = UIManager._send_event_calls[1].event
            assert.are.equal("GotoViewRel", event.name)
            assert.are.equal(1, event.args[1])
        end)
    end)

    describe("available actions structure", function()
        it("should provide categorized actions", function()
            assert.is_table(AvailableActions)
            assert.is_true(#AvailableActions > 0)

            -- Each category should have proper structure
            for _, category in ipairs(AvailableActions) do
                assert.is_string(category.category)
                assert.is_table(category.actions)

                -- Each action should have base (unprefixed) ID
                for _, action in ipairs(category.actions) do
                    assert.is_string(action.id)
                    -- Base IDs in the actions array should not contain colon
                    -- (prefixing happens in the lookup map)
                    if action.id:find(":") then
                        error("Action ID should not be prefixed in the actions array: " .. action.id)
                    end
                end
            end
        end)

        it("should allow building prefixed IDs from category and action ID", function()
            -- Find a category with actions
            local found = false

            for _, category in ipairs(AvailableActions) do
                if #category.actions > 0 then
                    local action = category.actions[1]
                    local prefixed_id = category.category .. ":" .. action.id

                    -- Should be able to look up by prefixed ID
                    local looked_up = instance:getActionById(prefixed_id)
                    assert.is_not_nil(looked_up)
                    assert.are.equal(action.id, looked_up.id)

                    found = true
                    break
                end
            end

            assert.is_true(found)
        end)
    end)

    describe("multiple devices with different action mappings", function()
        it("should handle different devices with different action sets", function()
            local UIManager = require("ui/uimanager")

            local device1_mac = "11:11:11:11:11:11"
            local device1_path = "/dev/input/event4"

            local device2_mac = "22:22:22:22:22:22"
            local device2_path = "/dev/input/event5"

            -- Setup device mappings
            instance:setDevicePathMapping(device1_path, device1_mac)
            instance:setDevicePathMapping(device2_path, device2_mac)

            -- Device 1: Page navigation
            instance.device_bindings[device1_mac] = {
                ["KEY_1"] = "Reader:next_page",
                ["KEY_2"] = "Reader:prev_page",
            }

            -- Device 2: Chapter navigation
            instance.device_bindings[device2_mac] = {
                ["KEY_1"] = "Reader:next_chapter",
                ["KEY_2"] = "Reader:prev_chapter",
            }

            -- Test device 1 - KEY_1 should trigger next_page
            UIManager:_reset()
            instance:onBluetoothKeyEvent(1, 1, { sec = 0, usec = 0 }, device1_path)

            assert.is_true(#UIManager._send_event_calls > 0)
            local event1 = UIManager._send_event_calls[1].event
            assert.are.equal("GotoViewRel", event1.name)

            -- Test device 2 - KEY_1 should trigger next_chapter
            UIManager:_reset()
            instance:onBluetoothKeyEvent(1, 1, { sec = 0, usec = 0 }, device2_path)

            assert.is_true(#UIManager._send_event_calls > 0)
            local event2 = UIManager._send_event_calls[1].event
            assert.are.equal("GotoNextChapter", event2.name)
        end)
    end)

    describe("persistence with prefixed IDs", function()
        it("should persist and load bindings with prefixed IDs", function()
            local device_mac = "AA:BB:CC:DD:EE:FF"
            local settings = {}

            -- Create instance and set bindings
            local instance1 = BluetoothKeyBindings:new({ settings = settings })
            instance1:setup(function()
                -- Save callback - store to settings
                settings.bluetooth_device_bindings = instance1.device_bindings
            end, nil)

            instance1.device_bindings[device_mac] = {
                ["KEY_A"] = "Reader:next_page",
                ["KEY_B"] = "Reader:prev_chapter",
            }

            instance1:saveBindings()

            -- Create new instance and load bindings
            local instance2 = BluetoothKeyBindings:new({ settings = settings })
            instance2:setup(function() end, nil)
            instance2:loadBindings()

            -- Verify bindings were loaded
            local loaded_bindings = instance2:getDeviceBindings(device_mac)
            assert.are.equal("Reader:next_page", loaded_bindings["KEY_A"])
            assert.are.equal("Reader:prev_chapter", loaded_bindings["KEY_B"])

            -- Verify actions can still be looked up
            local action_a = instance2:getActionById(loaded_bindings["KEY_A"])
            local action_b = instance2:getActionById(loaded_bindings["KEY_B"])

            assert.is_not_nil(action_a)
            assert.is_not_nil(action_b)
            assert.are.equal("GotoViewRel", action_a.event)
            assert.are.equal("GotoPrevChapter", action_b.event)
        end)
    end)
end)
