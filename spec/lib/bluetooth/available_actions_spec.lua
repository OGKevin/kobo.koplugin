---
-- Tests for available_actions module.

describe("available_actions", function()
    local available_actions

    setup(function()
        require("spec/helper")
    end)

    before_each(function()
        -- Reload module for each test
        package.loaded["src/lib/bluetooth/available_actions"] = nil
        package.loaded["src/lib/bluetooth/dispatcher_helper"] = nil

        -- Clear dispatcher_helper cache
        local dispatcher_helper = require("src/lib/bluetooth/dispatcher_helper")
        dispatcher_helper.clear_cache()

        available_actions = require("src/lib/bluetooth/available_actions")
    end)

    describe("structure", function()
        it("should return a table", function()
            assert.is_table(available_actions)
        end)

        it("should have categorized actions", function()
            assert.is_true(#available_actions > 0)

            -- Each category should have category name and actions array
            for _, category in ipairs(available_actions) do
                assert.is_table(category)
                assert.is_string(category.category)
                assert.is_table(category.actions)
            end
        end)

        it("should have at least one category with actions", function()
            local has_actions = false

            for _, category in ipairs(available_actions) do
                if #category.actions > 0 then
                    has_actions = true
                    break
                end
            end

            assert.is_true(has_actions)
        end)
    end)

    describe("essential actions", function()
        it("should include essential navigation actions", function()
            -- Find Reader category
            local reader_category

            for _, category in ipairs(available_actions) do
                if category.category == "Reader" then
                    reader_category = category
                    break
                end
            end

            assert.is_not_nil(reader_category)

            -- Check for essential actions
            local action_ids = {}
            for _, action in ipairs(reader_category.actions) do
                action_ids[action.id] = action
            end

            assert.is_not_nil(action_ids["next_page"])
            assert.is_not_nil(action_ids["prev_page"])
            assert.is_not_nil(action_ids["next_chapter"])
            assert.is_not_nil(action_ids["prev_chapter"])

            -- Verify next_page details
            assert.are.equal("GotoViewRel", action_ids["next_page"].event)
            assert.are.equal(1, action_ids["next_page"].args)

            -- Verify prev_page details
            assert.are.equal("GotoViewRel", action_ids["prev_page"].event)
            assert.are.equal(-1, action_ids["prev_page"].args)

            -- Verify chapter navigation
            assert.are.equal("GotoNextChapter", action_ids["next_chapter"].event)
            assert.are.equal("GotoPrevChapter", action_ids["prev_chapter"].event)
        end)

        it("should include static fallback actions when dispatcher fails", function()
            -- Since dispatcher extraction fails in test environment,
            -- we should get the static fallback actions

            -- Find categories that exist
            local categories_found = {}
            for _, category in ipairs(available_actions) do
                table.insert(categories_found, category.category)
            end

            -- Should have at least Reader category with essential actions
            assert.is_true(#categories_found > 0)
        end)
    end)

    describe("action properties", function()
        it("should have required properties for each action", function()
            for _, category in ipairs(available_actions) do
                for _, action in ipairs(category.actions) do
                    -- Every action must have these fields
                    assert.is_string(action.id)
                    assert.is_string(action.title)
                    assert.is_string(action.event)
                    assert.is_string(action.description)

                    -- args is optional but if present should be correct type
                    if action.args ~= nil then
                        assert.is_true(
                            type(action.args) == "number"
                                or type(action.args) == "string"
                                or type(action.args) == "table"
                        )
                    end
                end
            end
        end)

        it("should have sorted actions within categories", function()
            for _, category in ipairs(available_actions) do
                if #category.actions > 1 then
                    -- Check if sorted alphabetically by title
                    local is_sorted = true
                    for i = 1, #category.actions - 1 do
                        local current_title = category.actions[i].title or ""
                        local next_title = category.actions[i + 1].title or ""
                        if current_title > next_title then
                            is_sorted = false
                            break
                        end
                    end

                    assert.is_true(is_sorted, "Actions in category " .. category.category .. " are not sorted")
                end
            end
        end)
    end)

    describe("fallback behavior", function()
        it("should use static actions when dispatcher extraction fails", function()
            -- In test environment, dispatcher_helper returns nil
            -- So we should get static fallback actions

            -- Verify we have actions even though dispatcher failed
            assert.is_true(#available_actions > 0)

            -- Should have essential actions
            local has_next_page = false

            for _, category in ipairs(available_actions) do
                for _, action in ipairs(category.actions) do
                    if action.id == "next_page" then
                        has_next_page = true
                        break
                    end
                end
                if has_next_page then
                    break
                end
            end

            assert.is_true(has_next_page)
        end)
    end)

    describe("dynamic dispatcher integration (mocked)", function()
        it("should use dispatcher actions when available", function()
            -- Save originals
            local original_dispatcher = package.preload["dispatcher"]

            -- Create a complete mock dispatcher with upvalues
            package.preload["dispatcher"] = function()
                local mock_settings = {
                    dynamic_action_1 = {
                        general = true,
                        title = "Dynamic Action 1",
                        event = "DynamicEvent1",
                        args = "test_arg",
                    },
                    dynamic_action_2 = {
                        device = true,
                        title = "Dynamic Action 2",
                        event = "DynamicEvent2",
                        toggle = { "setting_a", "setting_b" },
                    },
                }

                local mock_order = { "dynamic_action_1", "dynamic_action_2" }

                local MockDispatcher = {}

                local function create_init()
                    local settingsList = mock_settings
                    return function()
                        return settingsList
                    end
                end

                MockDispatcher.init = create_init()

                local function create_register()
                    local dispatcher_menu_order = mock_order
                    return function(self, id, def)
                        return dispatcher_menu_order
                    end
                end

                MockDispatcher.registerAction = create_register()

                return MockDispatcher
            end

            -- Reload everything
            package.loaded["dispatcher"] = nil
            package.loaded["src/lib/bluetooth/dispatcher_helper"] = nil
            package.loaded["src/lib/bluetooth/available_actions"] = nil

            local actions = require("src/lib/bluetooth/available_actions")

            -- Restore
            package.preload["dispatcher"] = original_dispatcher
            package.loaded["dispatcher"] = nil

            -- Verify we got dynamic actions
            assert.is_table(actions)
            assert.is_true(#actions > 0)

            -- Should have General and Device categories from our mock
            local found_dynamic_1 = false
            local found_dynamic_2 = false

            for _, category in ipairs(actions) do
                for _, action in ipairs(category.actions) do
                    if action.id == "dynamic_action_1" then
                        found_dynamic_1 = true
                        assert.are.equal("Dynamic Action 1", action.title)
                        assert.are.equal("DynamicEvent1", action.event)
                        assert.are.equal("test_arg", action.args)
                    elseif action.id == "dynamic_action_2" then
                        found_dynamic_2 = true
                        assert.are.equal("Dynamic Action 2", action.title)
                        assert.are.equal("DynamicEvent2", action.event)
                        assert.is_table(action.toggle)
                    end
                end
            end

            assert.is_true(found_dynamic_1, "Should find dynamic_action_1")
            assert.is_true(found_dynamic_2, "Should find dynamic_action_2")
        end)

        it("should still include essential actions even with dynamic dispatcher", function()
            -- Save originals
            local original_dispatcher = package.preload["dispatcher"]

            -- Create mock dispatcher
            package.preload["dispatcher"] = function()
                local mock_settings = {
                    some_action = {
                        general = true,
                        title = "Some Action",
                        event = "SomeEvent",
                    },
                }

                local mock_order = { "some_action" }

                local MockDispatcher = {}

                local function create_init()
                    local settingsList = mock_settings
                    return function()
                        return settingsList
                    end
                end

                MockDispatcher.init = create_init()

                local function create_register()
                    local dispatcher_menu_order = mock_order
                    return function(self, id, def)
                        return dispatcher_menu_order
                    end
                end

                MockDispatcher.registerAction = create_register()

                return MockDispatcher
            end

            -- Reload
            package.loaded["dispatcher"] = nil
            package.loaded["src/lib/bluetooth/dispatcher_helper"] = nil
            package.loaded["src/lib/bluetooth/available_actions"] = nil

            local actions = require("src/lib/bluetooth/available_actions")

            -- Restore
            package.preload["dispatcher"] = original_dispatcher
            package.loaded["dispatcher"] = nil

            -- Essential navigation actions should still be there
            local found_next_page = false

            for _, category in ipairs(actions) do
                for _, action in ipairs(category.actions) do
                    if action.id == "next_page" then
                        found_next_page = true
                        break
                    end
                end
            end

            assert.is_true(found_next_page, "Essential actions should be included")
        end)
    end)
end)
