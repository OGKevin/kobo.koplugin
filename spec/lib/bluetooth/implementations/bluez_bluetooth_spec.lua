---
--- Unit tests for BlueZBluetooth implementation.

require("spec.helper")

describe("BlueZBluetooth", function()
    local BlueZBluetooth
    local Device

    setup(function()
        Device = require("device")
        BlueZBluetooth = require("src/lib/bluetooth/implementations/bluez_bluetooth")
    end)

    before_each(function()
        -- Reset device state to Libra 2 (Kobo_io) by default
        Device.model = "Kobo_io"
        Device.isKobo = function()
            return true
        end

        -- Reset all mocks
        resetAllMocks()
    end)

    describe("isDeviceSupported", function()
        it("should return true on Kobo Libra 2 device", function()
            Device.model = "Kobo_io"
            local instance = BlueZBluetooth:new()
            assert.is_true(instance:isDeviceSupported())
        end)

        it("should return true on Kobo Sage device", function()
            Device.model = "Kobo_cadmus"
            local instance = BlueZBluetooth:new()
            assert.is_true(instance:isDeviceSupported())
        end)

        it("should return false on non-BlueZ Kobo device", function()
            Device.model = "Kobo_unsupported"
            local instance = BlueZBluetooth:new()
            assert.is_false(instance:isDeviceSupported())
        end)

        it("should return false on MTK Kobo device", function()
            Device.model = "KLC"
            Device._isMTK = true
            local instance = BlueZBluetooth:new()
            assert.is_false(instance:isDeviceSupported())
        end)

        it("should return false on non-Kobo device", function()
            local original_isKobo = Device.isKobo
            Device.isKobo = function()
                return false
            end
            Device.model = "Kobo_io"
            local instance = BlueZBluetooth:new()
            assert.is_false(instance:isDeviceSupported())
            Device.isKobo = original_isKobo
        end)
    end)

    describe("device selection in KoboBluetooth.create()", function()
        before_each(function()
            -- Clear cached module to test factory selection fresh
            package.loaded["src/kobo_bluetooth"] = nil
            package.loaded["src/lib/bluetooth/implementations/bluez_bluetooth"] = nil
        end)

        it("should return BlueZBluetooth instance for Libra 2 device", function()
            Device.model = "Kobo_io"
            Device._isMTK = false
            Device.isKobo = function()
                return true
            end

            local KoboBluetooth = require("src/kobo_bluetooth")
            local instance = KoboBluetooth.create()

            -- Verify we got a BlueZBluetooth instance by checking device support
            assert.is_true(instance:isDeviceSupported())
        end)

        it("should return BlueZBluetooth instance for Sage device", function()
            Device.model = "Kobo_cadmus"
            Device._isMTK = false
            Device.isKobo = function()
                return true
            end

            local KoboBluetooth = require("src/kobo_bluetooth")
            local instance = KoboBluetooth.create()

            assert.is_true(instance:isDeviceSupported())
        end)
    end)
end)
