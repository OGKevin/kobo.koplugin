---
-- Unit tests for the Kobo firmware version accessor.

require("spec.helper")

describe("KoboFirmware", function()
    local KoboFirmware
    local Device

    setup(function()
        Device = require("device")
    end)

    before_each(function()
        resetAllMocks()
        KoboFirmware = require("src/lib/kobo_firmware")
        KoboFirmware._resetCache()
        Device.getFirmwareVersion = nil
        Device.firmware_rev = nil
    end)

    after_each(function()
        Device.getFirmwareVersion = nil
        Device.firmware_rev = nil
    end)

    describe("parseVersion", function()
        it("should parse a three-component version string", function()
            local version = KoboFirmware.parseVersion("4.45.23697")

            assert.are.equal(4, version.major)
            assert.are.equal(45, version.minor)
        end)

        it("should parse a two-component version string", function()
            local version = KoboFirmware.parseVersion("5.0")

            assert.are.equal(5, version.major)
            assert.are.equal(0, version.minor)
        end)

        it("should return nil for a non-numeric version string", function()
            assert.is_nil(KoboFirmware.parseVersion("none"))
        end)

        it("should return nil for a non-string", function()
            assert.is_nil(KoboFirmware.parseVersion(nil))
        end)
    end)

    describe("isAtLeast", function()
        it("should compare version components numerically, not lexically", function()
            Device.getFirmwareVersion = function()
                return "4.9.123"
            end

            assert.is_false(KoboFirmware.isAtLeast(4, 10))
        end)

        it("should accept firmware >= 5.0", function()
            Device.getFirmwareVersion = function()
                return "5.0.12345"
            end

            assert.is_true(KoboFirmware.isAtLeast(5, 0))
        end)

        it("should accept firmware well above the cutoff", function()
            Device.getFirmwareVersion = function()
                return "6.0.12345"
            end

            assert.is_true(KoboFirmware.isAtLeast(5, 0))
        end)

        it("should reject firmware below the cutoff", function()
            Device.getFirmwareVersion = function()
                return "4.45.23697"
            end

            assert.is_false(KoboFirmware.isAtLeast(5, 0))
        end)

        it("should return nil when the firmware is unknown", function()
            Device.getFirmwareVersion = function()
                return "none"
            end

            assert.is_nil(KoboFirmware.isAtLeast(5, 0))
        end)
    end)

    describe("getFirmwareVersion", function()
        it("should prefer the device accessor", function()
            Device.getFirmwareVersion = function()
                return "6.0.12345"
            end

            assert.are.equal("6.0.12345", KoboFirmware.getFirmwareVersion())
        end)

        it("should accept the device accessor storing the version on the device object", function()
            Device.getFirmwareVersion = function()
                Device.firmware_rev = "6.0.12345"
            end

            assert.are.equal("6.0.12345", KoboFirmware.getFirmwareVersion())
        end)

        it("should return nil when the accessor yields nothing", function()
            Device.getFirmwareVersion = function()
                return "none"
            end

            assert.is_nil(KoboFirmware.getFirmwareVersion())
        end)

        it("should cache the version between calls", function()
            local calls = 0
            Device.getFirmwareVersion = function()
                calls = calls + 1

                return "6.0.12345"
            end

            KoboFirmware.getFirmwareVersion()
            KoboFirmware.getFirmwareVersion()

            assert.are.equal(1, calls)
        end)
    end)
end)
