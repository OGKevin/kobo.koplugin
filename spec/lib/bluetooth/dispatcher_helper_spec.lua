---
-- Tests for dispatcher_helper module.

describe("dispatcher_helper", function()
    local dispatcher_helper

    setup(function()
        require("spec/helper")
    end)

    before_each(function()
        -- Clear the cache before each test
        package.loaded["src/lib/bluetooth/dispatcher_helper"] = nil
        dispatcher_helper = require("src/lib/bluetooth/dispatcher_helper")
        dispatcher_helper.clear_cache()
    end)

    describe("get_dispatcher_actions_ordered", function()
        it("should return nil when Dispatcher doesn't have required methods", function()
            -- The mock Dispatcher in spec/helper doesn't have init method
            local actions = dispatcher_helper.get_dispatcher_actions_ordered()

            assert.is_nil(actions)
        end)

        it("should cache results on subsequent calls", function()
            -- First call
            local actions1 = dispatcher_helper.get_dispatcher_actions_ordered()

            -- Second call should return the same cached result
            local actions2 = dispatcher_helper.get_dispatcher_actions_ordered()

            assert.are.equal(actions1, actions2)
        end)
    end)

    describe("integration with real Dispatcher (mocked)", function()
        it("should extract actions when Dispatcher has proper structure", function()
            -- This test demonstrates what would happen with a real Dispatcher
            -- We'll create a mock with the expected structure

            -- Save original package.preload
            local original_dispatcher = package.preload["dispatcher"]

            -- Create a more complete mock
            package.preload["dispatcher"] = function()
                local mock_settings = {
                    test_action = {
                        general = true,
                        title = "Test Action",
                        event = "TestEvent",
                    },
                    another_action = {
                        reader = true,
                        title = "Another Action",
                        event = "AnotherEvent",
                    },
                }

                local mock_order = { "test_action", "another_action" }

                local MockDispatcher = {}

                -- Create init function with upvalues
                local function create_init()
                    local settingsList = mock_settings
                    return function()
                        return settingsList
                    end
                end

                MockDispatcher.init = create_init()

                -- Create registerAction function with upvalues
                local function create_register()
                    local dispatcher_menu_order = mock_order
                    return function(self, id, def)
                        return dispatcher_menu_order
                    end
                end

                MockDispatcher.registerAction = create_register()

                return MockDispatcher
            end

            -- Reload modules
            package.loaded["dispatcher"] = nil
            package.loaded["src/lib/bluetooth/dispatcher_helper"] = nil
            local helper = require("src/lib/bluetooth/dispatcher_helper")

            local actions = helper.get_dispatcher_actions_ordered()

            -- Restore original
            package.preload["dispatcher"] = original_dispatcher
            package.loaded["dispatcher"] = nil

            -- Verify we got actions
            assert.is_table(actions)
            assert.is_true(#actions > 0)

            -- Actions should be organized by category with section titles
            local found_general = false
            local found_reader = false

            for _, item in ipairs(actions) do
                if type(item) == "string" then
                    if item == "General" then
                        found_general = true
                    elseif item == "Reader" then
                        found_reader = true
                    end
                elseif type(item) == "table" and item.dispatcher_id then
                    -- Found an action
                    if item.dispatcher_id == "test_action" then
                        assert.are.equal("Test Action", item.title)
                        assert.are.equal("TestEvent", item.event)
                    elseif item.dispatcher_id == "another_action" then
                        assert.are.equal("Another Action", item.title)
                        assert.are.equal("AnotherEvent", item.event)
                    end
                end
            end

            assert.is_true(found_general)
            assert.is_true(found_reader)
        end)
    end)
end)
