---
-- Unit tests for UiMenus module.

require("spec.helper")

describe("UiMenus", function()
    local UiMenus
    local UIManager

    setup(function()
        UiMenus = require("src/lib/bluetooth/ui_menus")
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        UIManager:_reset()
    end)

    describe("showScanResults", function()
        describe("filtering reachable devices", function()
            it("should filter out devices with RSSI -127 (out of range)", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = false, connected = false },
                    {
                        name = "Device 2",
                        address = "11:22:33:44:55:66",
                        rssi = -127,
                        paired = false,
                        connected = false,
                    },
                    { name = "Device 3", address = "99:88:77:66:55:44", rssi = -60, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                -- Should show a menu with only 2 devices (excluding the one with RSSI -127)
                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.is_not_nil(shown_widget)
                assert.is_not_nil(shown_widget.item_table)
                assert.are.equal(2, #shown_widget.item_table)
                assert.are.equal("Device 1", shown_widget.item_table[1].text)
                assert.are.equal("Device 3", shown_widget.item_table[2].text)
            end)

            it("should keep devices with nil RSSI (considered reachable)", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = nil, paired = false, connected = false },
                    { name = "Device 2", address = "11:22:33:44:55:66", rssi = -50, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal(2, #shown_widget.item_table)
            end)

            it("should keep devices with RSSI > -127", function()
                local devices = {
                    {
                        name = "Device 1",
                        address = "AA:BB:CC:DD:EE:FF",
                        rssi = -126,
                        paired = false,
                        connected = false,
                    },
                    { name = "Device 2", address = "11:22:33:44:55:66", rssi = -38, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal(2, #shown_widget.item_table)
            end)

            it("should show info message when no reachable devices found", function()
                local devices = {
                    {
                        name = "Device 1",
                        address = "AA:BB:CC:DD:EE:FF",
                        rssi = -127,
                        paired = false,
                        connected = false,
                    },
                    {
                        name = "Device 2",
                        address = "11:22:33:44:55:66",
                        rssi = -127,
                        paired = false,
                        connected = false,
                    },
                }

                UiMenus.showScanResults(devices, function() end)

                -- Should show InfoMessage, not a menu
                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("No Bluetooth devices found", shown_widget.text)
                assert.are.equal(3, shown_widget.timeout)
            end)
        end)

        describe("filtering named devices", function()
            it("should filter out devices with empty names", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = false, connected = false },
                    { name = "", address = "11:22:33:44:55:66", rssi = -60, paired = false, connected = false },
                    { name = "Device 3", address = "99:88:77:66:55:44", rssi = -70, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                -- Should show a menu with only 2 devices (excluding the one with empty name)
                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.is_not_nil(shown_widget.item_table)
                assert.are.equal(2, #shown_widget.item_table)
                assert.are.equal("Device 1", shown_widget.item_table[1].text)
                assert.are.equal("Device 3", shown_widget.item_table[2].text)
            end)

            it("should show info message when no named devices found (all reachable)", function()
                local devices = {
                    { name = "", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = false, connected = false },
                    { name = "", address = "11:22:33:44:55:66", rssi = -60, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                -- Should show InfoMessage about no named devices
                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("No named Bluetooth devices found", shown_widget.text)
                assert.are.equal(3, shown_widget.timeout)
            end)
        end)

        describe("combined filtering", function()
            it("should filter both unreachable and unnamed devices", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = false, connected = false },
                    { name = "", address = "11:22:33:44:55:66", rssi = -60, paired = false, connected = false },
                    {
                        name = "Device 3",
                        address = "99:88:77:66:55:44",
                        rssi = -127,
                        paired = false,
                        connected = false,
                    },
                    { name = "Device 4", address = "AA:AA:AA:AA:AA:AA", rssi = -40, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                -- Should show only Device 1 and Device 4
                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.is_not_nil(shown_widget.item_table)
                assert.are.equal(2, #shown_widget.item_table)
                assert.are.equal("Device 1", shown_widget.item_table[1].text)
                assert.are.equal("Device 4", shown_widget.item_table[2].text)
            end)

            it("should handle all devices being filtered out due to unreachable RSSI", function()
                local devices = {
                    {
                        name = "Device 1",
                        address = "AA:BB:CC:DD:EE:FF",
                        rssi = -127,
                        paired = false,
                        connected = false,
                    },
                }

                UiMenus.showScanResults(devices, function() end)

                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("No Bluetooth devices found", shown_widget.text)
            end)

            it("should handle all devices being filtered out due to empty names", function()
                local devices = {
                    { name = "", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("No named Bluetooth devices found", shown_widget.text)
            end)
        end)

        describe("device display", function()
            it("should display correct status for connected devices", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = true, connected = true },
                }

                UiMenus.showScanResults(devices, function() end)

                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("Connected", shown_widget.item_table[1].mandatory)
            end)

            it("should display correct status for paired but not connected devices", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = true, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("Paired", shown_widget.item_table[1].mandatory)
            end)

            it("should display correct status for unpaired devices", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("Not paired", shown_widget.item_table[1].mandatory)
            end)
        end)

        describe("edge cases", function()
            it("should handle empty device list", function()
                local devices = {}

                UiMenus.showScanResults(devices, function() end)

                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal("No Bluetooth devices found", shown_widget.text)
            end)

            it("should handle devices with mixed RSSI values at boundary", function()
                local devices = {
                    {
                        name = "Device 1",
                        address = "AA:BB:CC:DD:EE:FF",
                        rssi = -127,
                        paired = false,
                        connected = false,
                    },
                    {
                        name = "Device 2",
                        address = "11:22:33:44:55:66",
                        rssi = -126,
                        paired = false,
                        connected = false,
                    },
                }

                UiMenus.showScanResults(devices, function() end)

                -- Only Device 2 should be shown (RSSI > -127)
                assert.are.equal(1, #UIManager._show_calls)
                local shown_widget = UIManager._shown_widgets[1]
                assert.are.equal(1, #shown_widget.item_table)
                assert.are.equal("Device 2", shown_widget.item_table[1].text)
            end)

            it("should preserve device info for callback", function()
                local devices = {
                    { name = "Device 1", address = "AA:BB:CC:DD:EE:FF", rssi = -50, paired = false, connected = false },
                }

                UiMenus.showScanResults(devices, function() end)

                local shown_widget = UIManager._shown_widgets[1]
                assert.is_not_nil(shown_widget.item_table[1].device_info)
                assert.are.equal("Device 1", shown_widget.item_table[1].device_info.name)
                assert.are.equal("AA:BB:CC:DD:EE:FF", shown_widget.item_table[1].device_info.address)
                assert.are.equal(-50, shown_widget.item_table[1].device_info.rssi)
            end)
        end)
    end)
end)
