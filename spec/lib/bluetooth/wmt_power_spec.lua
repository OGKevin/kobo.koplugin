---
--- Unit tests for the WMT Wi-Fi power helper.

local helper = require("spec.helper")

describe("WmtPower", function()
    local WmtPower
    local NetworkMgr
    local lfs
    local files

    setup(function()
        WmtPower = require("src/lib/bluetooth/wmt_power")
        NetworkMgr = require("ui/network/manager")
        lfs = require("libs/libkoreader-lfs")
        files = helper.createWmtFileMocker()
    end)

    before_each(function()
        resetAllMocks()
        NetworkMgr:_reset()
        lfs._clearFileStates()
        files.install()
        clearExecutedCommands()
    end)

    after_each(function()
        files.uninstall()
        NetworkMgr:_reset()
        lfs._clearFileStates()
        WmtPower.bringing_up = false
    end)

    local ALL_MODULES = "wmt_drv 1 0 - Live\nwmt_chrdev_wifi 1 0 - Live\nwmt_cdev_bt 1 0 - Live\nwlan_drv_gen4m 1 0 - Live\n"

    describe("powerOn", function()
        it("should leave the marker, run the handshake and switch the WiFi function on", function()
            assert.is_true(WmtPower.powerOn())

            assert.are.same({ "" }, files.writes[WmtPower.POWERED_MARKER])
            assert.are.same({ "0xDB9DB9", "7 9 0", "0xDB9DB9", "7 9 1" }, files.writes[WmtPower.WMT_DEBUG_FILE])
            assert.are.same({ "1" }, files.writes[WmtPower.WIFI_CONTROL_DEVICE])
            -- No wpa_supplicant, no DHCP: nothing is run through the shell
            assert.are.equal(0, #getExecutedCommands())
        end)

        it("should report failure when a control file cannot be written", function()
            files.uninstall()

            assert.is_false(WmtPower.powerOn())
        end)
    end)

    describe("powerOff", function()
        it("should switch the WiFi function off", function()
            assert.is_true(WmtPower.powerOff())
            assert.are.same({ "0" }, files.writes[WmtPower.WIFI_CONTROL_DEVICE])
        end)
    end)

    describe("isModuleLoaded", function()
        it("should read the module list", function()
            files.setContent(WmtPower.MODULES_FILE, "wmt_drv 961828 4 - Live 0xbf000000 (O)\nwlan_drv_gen4m 1 0 - Live\n")

            assert.is_true(WmtPower.isModuleLoaded("wmt_drv"))
            assert.is_true(WmtPower.isModuleLoaded("wlan_drv_gen4m"))
            assert.is_false(WmtPower.isModuleLoaded("wmt_cdev_bt"))
        end)
    end)

    describe("isLauncherRunning", function()
        it("should find the firmware daemon by its command line", function()
            lfs._setDirectoryContents(WmtPower.PROC_DIR, { "1", "1878", "self" })
            files.setContent(WmtPower.PROC_DIR .. "/1/cmdline", "init\0")
            files.setContent(WmtPower.PROC_DIR .. "/1878/cmdline", WmtPower.WMT_LAUNCHER .. "\0-p\0/lib/firmware\0")

            assert.is_true(WmtPower.isLauncherRunning())
        end)

        it("should be false when no process runs it", function()
            lfs._setDirectoryContents(WmtPower.PROC_DIR, { "1" })
            files.setContent(WmtPower.PROC_DIR .. "/1/cmdline", "init\0")

            assert.is_false(WmtPower.isLauncherRunning())
        end)
    end)

    describe("loadStack", function()
        it("should run the loader and start the daemon when the modules are present", function()
            setMockExecuteResult(0)
            files.setContent(WmtPower.MODULES_FILE, ALL_MODULES)

            assert.is_true(WmtPower.loadStack())

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.is_not_nil(commands[1]:find(WmtPower.WMT_LOADER, 1, true))
            assert.are.equal(WmtPower.launcherCommand(), commands[2])
            -- Detached, off the onboard partition, without KOReader's streams
            assert.is_not_nil(commands[2]:find("cd /tmp && setsid", 1, true))
            assert.is_not_nil(commands[2]:find(">/dev/null 2>&1 </dev/null &", 1, true))
        end)

        it("should insert the modules the loader did not, and fail if one is still missing", function()
            setMockExecuteResult(0)
            files.setContent(WmtPower.MODULES_FILE, "")

            assert.is_false(WmtPower.loadStack())

            local commands = getExecutedCommands()
            assert.is_not_nil(commands[1]:find("insmod /drivers/", 1, true))
            assert.is_not_nil(commands[1]:find("/mt66xx/wmt_drv.ko", 1, true))
            assert.is_not_nil(commands[2]:find(WmtPower.WMT_LOADER, 1, true))
            assert.is_not_nil(commands[3]:find("/mt66xx/wmt_chrdev_wifi.ko", 1, true))
            for _, cmd in ipairs(commands) do
                assert.is_nil(cmd:find(WmtPower.WMT_LAUNCHER, 1, true))
            end
        end)

        it("should not start a second firmware daemon", function()
            setMockExecuteResult(0)
            files.setContent(WmtPower.MODULES_FILE, ALL_MODULES)
            lfs._setDirectoryContents(WmtPower.PROC_DIR, { "1878" })
            files.setContent(WmtPower.PROC_DIR .. "/1878/cmdline", WmtPower.WMT_LAUNCHER .. "\0")

            assert.is_true(WmtPower.loadStack())

            for _, cmd in ipairs(getExecutedCommands()) do
                assert.is_nil(cmd:find("setsid", 1, true))
            end
        end)
    end)

    describe("markers", function()
        it("should write the powered and stack-ready markers", function()
            assert.is_true(WmtPower.markPowered())
            assert.is_true(WmtPower.markStackReady())
            assert.are.same({ "" }, files.writes[WmtPower.POWERED_MARKER])
            assert.are.same({ "" }, files.writes[WmtPower.STACK_READY_MARKER])
        end)

        it("should report a marker that cannot be written", function()
            files.uninstall()

            assert.is_false(WmtPower.markStackReady())
        end)

        it("should reflect the powered marker", function()
            lfs._setFileState(WmtPower.POWERED_MARKER, { exists = false })
            assert.is_false(WmtPower.wasPoweredForBluetooth())

            lfs._setFileState(WmtPower.POWERED_MARKER, { exists = true, attributes = { mode = "file" } })
            assert.is_true(WmtPower.wasPoweredForBluetooth())
        end)

        it("should consider the powered marker cleared once it is gone", function()
            lfs._setFileState(WmtPower.POWERED_MARKER, { exists = false })

            assert.is_true(WmtPower.clearPoweredForBluetooth())
        end)
    end)

    describe("isStackLoaded", function()
        it("should be false without the Bluetooth device node", function()
            lfs._setFileState(WmtPower.STACK_READY_MARKER, { exists = false })
            lfs._setFileState(WmtPower.BT_DEVICE, { exists = false })

            assert.is_false(WmtPower.isStackLoaded())
        end)

        it("should be true when the node exists and the firmware daemon runs, and remember it", function()
            lfs._setFileState(WmtPower.STACK_READY_MARKER, { exists = false })
            lfs._setFileState(WmtPower.BT_DEVICE, { exists = true, attributes = { mode = "char device" } })
            lfs._setDirectoryContents(WmtPower.PROC_DIR, { "1878" })
            files.setContent(WmtPower.PROC_DIR .. "/1878/cmdline", WmtPower.WMT_LAUNCHER .. "\0")

            assert.is_true(WmtPower.isStackLoaded())
            assert.are.same({ "" }, files.writes[WmtPower.STACK_READY_MARKER])
        end)

        it("should be false when the node exists but no firmware daemon runs", function()
            lfs._setFileState(WmtPower.STACK_READY_MARKER, { exists = false })
            lfs._setFileState(WmtPower.BT_DEVICE, { exists = true, attributes = { mode = "char device" } })
            lfs._setDirectoryContents(WmtPower.PROC_DIR, {})

            assert.is_false(WmtPower.isStackLoaded())
        end)

        it("should be false while this process is bringing the stack up, until the marker appears", function()
            lfs._setFileState(WmtPower.STACK_READY_MARKER, { exists = false })
            lfs._setFileState(WmtPower.BT_DEVICE, { exists = true, attributes = { mode = "char device" } })
            WmtPower.bringing_up = true

            assert.is_false(WmtPower.isStackLoaded())

            lfs._setFileState(WmtPower.STACK_READY_MARKER, { exists = true, attributes = { mode = "file" } })
            assert.is_true(WmtPower.isStackLoaded())
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
