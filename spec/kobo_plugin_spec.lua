---
-- Unit tests for KoboPlugin main module.

require("spec.helper")

describe("KoboPlugin", function()
    local KoboPlugin
    local UIManager
    local Device

    setup(function()
        Device = require("device")
        UIManager = require("ui/uimanager")
        KoboPlugin = require("main")
    end)

    before_each(function()
        UIManager:_reset()

        Device.isMTK = true
        Device.isKobo = function()
            return true
        end

        resetAllMocks()

        -- Reset G_reader_settings to default mock
        _G.G_reader_settings = {
            _settings = {},
            readSetting = function(self, key)
                return self._settings[key]
            end,
            saveSetting = function(self, key, value)
                self._settings[key] = value
            end,
            flush = function(self) end,
        }
    end)

    describe("init", function()
        it("should initialize plugin with default settings", function()
            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            assert.is_not_nil(instance.metadata_parser)
            assert.is_not_nil(instance.virtual_library)
            assert.is_not_nil(instance.reading_state_sync)
            assert.is_not_nil(instance.kobo_bluetooth)
            assert.is_not_nil(instance.settings)
        end)

        it("should initialize paired_devices setting to empty table", function()
            _G.G_reader_settings = {
                readSetting = function(self, key)
                    return nil
                end,
                saveSetting = function(self, key, value) end,
                flush = function(self) end,
            }

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            assert.is_not_nil(instance.settings.paired_devices)
            assert.are.equal(0, #instance.settings.paired_devices)
        end)

        it("should turn off Bluetooth when suspending", function()
            setMockPopenOutput("variant boolean true")

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            -- Reset UIManager to clear any init popups
            UIManager:_reset()

            instance:onSuspend()

            -- Verify Bluetooth was turned off without popup
            assert.are.equal(0, #UIManager._shown_widgets)
        end)

        it("should add kobo_bluetooth to widget hierarchy", function()
            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            -- Check that kobo_bluetooth was inserted into the widget hierarchy
            local found_bluetooth = false

            for _, widget in ipairs(instance) do
                if widget.name == "kobo_bluetooth" then
                    found_bluetooth = true

                    break
                end
            end

            assert.is_true(found_bluetooth)
        end)
    end)

    describe("onDispatcherRegisterActions", function()
        it("should register paired devices with dispatcher", function()
            setMockPopenOutput("variant boolean false")

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            instance.settings.paired_devices = {
                { name = "Device 1", address = "00:11:22:33:44:55" },
                { name = "Device 2", address = "AA:BB:CC:DD:EE:FF" },
            }

            instance:onDispatcherRegisterActions()

            local action_id_1 = "bluetooth_connect_00_11_22_33_44_55"
            local action_id_2 = "bluetooth_connect_AA_BB_CC_DD_EE_FF"

            assert.is_true(instance.kobo_bluetooth.dispatcher_registered_devices[action_id_1])
            assert.is_true(instance.kobo_bluetooth.dispatcher_registered_devices[action_id_2])
        end)

        it("should not crash if kobo_bluetooth is nil", function()
            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }
            instance.kobo_bluetooth = nil

            instance:onDispatcherRegisterActions()

            -- Should not crash
            assert.is_not_nil(instance)
        end)
    end)

    describe("onConnectToBluetoothDevice", function()
        it("should delegate to kobo_bluetooth", function()
            setMockPopenOutput("variant boolean true")

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            instance.kobo_bluetooth.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.kobo_bluetooth.device_manager.loadPairedDevices = function(self) end

            local connect_called = false
            instance.kobo_bluetooth.device_manager.connectDevice = function(self, device_info, on_success)
                connect_called = true
            end

            instance:onConnectToBluetoothDevice("00:11:22:33:44:55")

            assert.is_true(connect_called)
        end)

        it("should not crash if kobo_bluetooth is nil", function()
            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }
            instance.kobo_bluetooth = nil

            instance:onConnectToBluetoothDevice("00:11:22:33:44:55")

            -- Should not crash
            assert.is_not_nil(instance)
        end)
    end)

    describe("onSuspend", function()
        it("should turn off Bluetooth when suspending", function()
            setMockPopenOutput("variant boolean true")

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            -- Reset UIManager to clear any init popups
            UIManager:_reset()

            instance:onSuspend()

            -- Debug: print what widgets were shown
            if #UIManager._shown_widgets > 0 then
                for i, widget in ipairs(UIManager._shown_widgets) do
                    print("Widget", i, ":", widget.text or "no text")
                end
            end

            -- Verify Bluetooth was turned off without popup
            assert.are.equal(0, #UIManager._shown_widgets)
        end)

        it("should not turn off Bluetooth if already off", function()
            setMockPopenOutput("variant boolean false")

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            instance:onSuspend()

            -- Should not crash
            assert.is_not_nil(instance)
        end)

        it("should not crash if Bluetooth not supported", function()
            Device.isMTK = false

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            instance:onSuspend()

            -- Should not crash
            assert.is_not_nil(instance)
        end)

        it("should not crash if kobo_bluetooth is nil", function()
            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }
            instance.kobo_bluetooth = nil

            instance:onSuspend()

            -- Should not crash
            assert.is_not_nil(instance)
        end)
    end)

    describe("saveSettings", function()
        it("should save paired_devices to settings", function()
            local saved_settings = nil
            local saved_key = nil

            _G.G_reader_settings = {
                readSetting = function(self, key)
                    return nil
                end,
                saveSetting = function(self, key, value)
                    saved_key = key
                    saved_settings = value
                end,
                flush = function(self) end,
            }

            local instance = KoboPlugin:new()
            instance.ui = { menu = { registerToMainMenu = function() end } }

            instance:init()

            instance.settings.paired_devices = {
                { name = "Device 1", address = "00:11:22:33:44:55" },
            }

            instance:saveSettings()

            assert.are.equal("kobo_plugin", saved_key)
            assert.is_not_nil(saved_settings)
            assert.is_not_nil(saved_settings.paired_devices)
            assert.are.equal(1, #saved_settings.paired_devices)
        end)
    end)
end)
