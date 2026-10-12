---
--- Unit tests for the WMT Wi-Fi power helper.

require("spec.helper")

describe("WmtPower", function()
    local WmtPower
    local NetworkMgr
    local lfs

    setup(function()
        WmtPower = require("src/lib/bluetooth/wmt_power")
        NetworkMgr = require("ui/network/manager")
        lfs = require("libs/libkoreader-lfs")
    end)

    before_each(function()
        resetAllMocks()
        NetworkMgr:_reset()
        lfs._clearFileStates()
    end)

    after_each(function()
        NetworkMgr:_reset()
        lfs._clearFileStates()
    end)

    describe("powerOn", function()
        it("should leave the marker and run the chip power-on handshake", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            assert.is_true(WmtPower.powerOn())

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.are.equal(WmtPower.COMMAND_MARK_POWERED, commands[1])
            assert.are.equal(WmtPower.COMMAND_POWER_ON, commands[2])
            -- No wpa_supplicant, no DHCP: only the WMT handshake and the function switch
            assert.is_nil(commands[2]:find("wpa_supplicant", 1, true))
            assert.is_not_nil(commands[2]:find("echo 1 >/dev/wmtWifi", 1, true))
        end)

        it("should report failure when the handshake fails", function()
            setMockExecuteResult(1)

            assert.is_false(WmtPower.powerOn())
        end)
    end)

    describe("powerOff", function()
        it("should switch the WiFi function off", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            assert.is_true(WmtPower.powerOff())
            assert.are.equal("echo 0 >/dev/wmtWifi", getExecutedCommands()[1])
        end)
    end)

    describe("wasPoweredForBluetooth", function()
        it("should reflect the marker file", function()
            lfs._setFileState(WmtPower.POWERED_MARKER, { exists = false })
            assert.is_false(WmtPower.wasPoweredForBluetooth())

            lfs._setFileState(WmtPower.POWERED_MARKER, { exists = true, attributes = { mode = "file" } })
            assert.is_true(WmtPower.wasPoweredForBluetooth())
        end)

        it("should remove the marker when cleared", function()
            setMockExecuteResult(0)
            clearExecutedCommands()
            WmtPower.clearPoweredForBluetooth()
            assert.are.equal(WmtPower.COMMAND_CLEAR_POWERED, getExecutedCommands()[1])
        end)
    end)

    describe("isWifiInUse", function()
        it("should be false when nothing uses WiFi", function()
            local in_use = WmtPower.isWifiInUse()
            assert.is_false(in_use)
        end)

        it("should be true while a NetworkMgr connection attempt is pending", function()
            NetworkMgr.pending_connection = true
            local in_use, reason = WmtPower.isWifiInUse()
            assert.is_true(in_use)
            assert.is_string(reason)
        end)

        it("should be true while a connectivity check is pending", function()
            NetworkMgr.pending_connectivity_check = true
            assert.is_true((WmtPower.isWifiInUse()))
        end)

        it("should be true when WiFi is connected", function()
            NetworkMgr:_setConnected(true)
            assert.is_true((WmtPower.isWifiInUse()))
        end)

        it("should be true while wpa_supplicant runs, even outside NetworkMgr", function()
            lfs._setFileState(WmtPower.WPA_SUPPLICANT_SOCKET_DIR .. "/wlan0", {
                exists = true,
                attributes = { mode = "socket" },
            })
            local in_use, reason = WmtPower.isWifiInUse()
            assert.is_true(in_use)
            assert.is_not_nil(reason:find("wpa_supplicant", 1, true))
        end)
    end)
end)
