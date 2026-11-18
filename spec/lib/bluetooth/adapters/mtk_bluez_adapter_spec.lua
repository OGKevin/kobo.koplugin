---
-- Unit tests for the MTK BlueZ adapter lifecycle.

require("spec.helper")

describe("MtkBluezAdapter", function()
    local MtkBluezAdapter
    local Subprocess
    local lfs
    local file_mocker
    local HCI0_SYSFS
    local BT_CONTROL_DEVICE
    local DAEMON_MARKER
    local RADIO_MARKER
    local BLUETOOTHD

    ---
    -- Records every write to the adapter's control files and markers, and can
    -- simulate the driver registering hci0 when the radio is powered on.
    local function createFileMocker()
        local io_mocker = require("spec.helper").createIOOpenMocker()
        local mocker = { writes = {}, on_write = {} }

        local function mockFile(path)
            return {
                write = function(_, text)
                    mocker.writes[path] = mocker.writes[path] or {}
                    table.insert(mocker.writes[path], text)

                    if mocker.on_write[path] then
                        mocker.on_write[path](text)
                    end

                    return true
                end,
                close = function()
                    return true
                end,
            }
        end

        function mocker.install()
            io_mocker.install()
            io_mocker.setMockFile(BT_CONTROL_DEVICE, mockFile(BT_CONTROL_DEVICE))
            io_mocker.setMockFile(DAEMON_MARKER, mockFile(DAEMON_MARKER))
            io_mocker.setMockFile(RADIO_MARKER, mockFile(RADIO_MARKER))
        end

        function mocker.uninstall()
            io_mocker.uninstall()
        end

        function mocker.setFailure(path)
            io_mocker.setMockFileFailure(path)
        end

        return mocker
    end

    before_each(function()
        resetAllMocks()
        require("libs/libkoreader-lfs")._clearFileStates()
        MtkBluezAdapter = require("src/lib/bluetooth/adapters/mtk_bluez_adapter")
        Subprocess = require("src/lib/bluetooth/subprocess")
        lfs = require("libs/libkoreader-lfs")

        HCI0_SYSFS = MtkBluezAdapter.HCI0_SYSFS
        BT_CONTROL_DEVICE = MtkBluezAdapter.BT_CONTROL_DEVICE
        DAEMON_MARKER = MtkBluezAdapter.DAEMON_MARKER
        RADIO_MARKER = MtkBluezAdapter.RADIO_MARKER
        BLUETOOTHD = MtkBluezAdapter.BLUETOOTHD_ARGV[1]

        file_mocker = createFileMocker()
        file_mocker.install()
        clearExecutedCommands()
    end)

    after_each(function()
        file_mocker.uninstall()
        require("libs/libkoreader-lfs")._clearFileStates()
    end)

    describe("turnOn", function()
        it("should power the radio, start bluetoothd, and set Powered=true", function()
            lfs._setFileState(HCI0_SYSFS, { exists = false })
            setMockPopenOutput("variant boolean true")
            file_mocker.on_write[BT_CONTROL_DEVICE] = function(text)
                if text == "1" then
                    lfs._setFileState(HCI0_SYSFS, { exists = true })
                end
            end

            assert.is_true(MtkBluezAdapter.turnOn())

            assert.are.equal("1", file_mocker.writes[BT_CONTROL_DEVICE][1])
            assert.are.equal(1, #Subprocess._start_daemon_calls)
            assert.is_truthy(file_mocker.writes[DAEMON_MARKER])
            assert.is_truthy(file_mocker.writes[RADIO_MARKER])
        end)

        it("should reuse a running bluetoothd and not start a second one", function()
            setMockPopenOutput("variant boolean true")
            Subprocess._running_processes[BLUETOOTHD] = true

            assert.is_true(MtkBluezAdapter.turnOn())

            assert.are.equal(0, #Subprocess._start_daemon_calls)
            assert.is_falsy(file_mocker.writes[DAEMON_MARKER])
        end)

        it("should not power the radio when hci0 is already up", function()
            lfs._setFileState(HCI0_SYSFS, { exists = true })
            setMockPopenOutput("variant boolean true")

            assert.is_true(MtkBluezAdapter.turnOn())

            assert.is_falsy(file_mocker.writes[BT_CONTROL_DEVICE])
            assert.is_truthy(file_mocker.writes[DAEMON_MARKER])
        end)

        it("should fail when the radio control device cannot be written", function()
            lfs._setFileState(HCI0_SYSFS, { exists = false })
            file_mocker.setFailure(BT_CONTROL_DEVICE)

            assert.is_false(MtkBluezAdapter.turnOn())

            assert.are.equal(0, #Subprocess._start_daemon_calls)
        end)

        it("should fail and roll back when hci0 never appears", function()
            lfs._setFileState(HCI0_SYSFS, { exists = false })

            assert.is_false(MtkBluezAdapter.turnOn())

            assert.are.equal("1", file_mocker.writes[BT_CONTROL_DEVICE][1])
            assert.are.equal("0", file_mocker.writes[BT_CONTROL_DEVICE][2])
            assert.are.equal(0, #Subprocess._start_daemon_calls)
        end)

        it("should fail and roll back when bluetoothd cannot be started", function()
            lfs._setFileState(HCI0_SYSFS, { exists = false })
            file_mocker.on_write[BT_CONTROL_DEVICE] = function(text)
                if text == "1" then
                    lfs._setFileState(HCI0_SYSFS, { exists = true })
                end
            end
            Subprocess._start_daemon_result = false

            assert.is_false(MtkBluezAdapter.turnOn())

            assert.are.equal("1", file_mocker.writes[BT_CONTROL_DEVICE][1])
            assert.are.equal("0", file_mocker.writes[BT_CONTROL_DEVICE][2])
            assert.is_falsy(file_mocker.writes[DAEMON_MARKER])
        end)

        it("should fail and roll back when bluetoothd never publishes the adapter", function()
            lfs._setFileState(HCI0_SYSFS, { exists = true })
            setMockExecuteResult(1)
            setMockPopenOutput("")

            assert.is_false(MtkBluezAdapter.turnOn())

            assert.are.equal(1, #Subprocess._start_daemon_calls)
            assert.is_truthy(file_mocker.writes[DAEMON_MARKER] == nil)
            assert.is_falsy(file_mocker.writes[BT_CONTROL_DEVICE])
        end)

        it("should treat an org.bluez.Error.Busy reply as success when the adapter really is powered", function()
            lfs._setFileState(HCI0_SYSFS, { exists = true })
            setMockExecuteResult(1)
            setMockPopenOutput("variant boolean true")

            assert.is_true(MtkBluezAdapter.turnOn())
        end)

        it("should fail and roll back when the adapter does not come up powered", function()
            lfs._setFileState(HCI0_SYSFS, { exists = true })
            setMockExecuteResult(1)
            setMockPopenOutput("variant boolean false")

            assert.is_false(MtkBluezAdapter.turnOn())

            assert.is_truthy(getExecutedCommands() and #getExecutedCommands() > 0)
            assert.is_falsy(file_mocker.writes[BT_CONTROL_DEVICE])
        end)
    end)

    describe("turnOff", function()
        it("should set Powered=false and power the radio down after a full turnOn", function()
            lfs._setFileState(HCI0_SYSFS, { exists = true })
            MtkBluezAdapter.turnOn()
            clearExecutedCommands()

            assert.is_true(MtkBluezAdapter.turnOff())

            assert.is_truthy(file_mocker.writes[BT_CONTROL_DEVICE])
            assert.are.equal("0", file_mocker.writes[BT_CONTROL_DEVICE][1])
        end)

        it("should stop the daemon the plugin started", function()
            lfs._setFileState(HCI0_SYSFS, { exists = true })
            MtkBluezAdapter.turnOn()
            clearExecutedCommands()

            MtkBluezAdapter.turnOff()

            local commands = getExecutedCommands()
            local killed = false
            for _, cmd in ipairs(commands) do
                if cmd:match("killall bluetoothd") then
                    killed = true
                end
            end
            assert.is_true(killed)
        end)

        it("should leave a pre-existing daemon and radio alone", function()
            lfs._setFileState(DAEMON_MARKER, { exists = false })
            lfs._setFileState(RADIO_MARKER, { exists = false })

            assert.is_true(MtkBluezAdapter.turnOff())

            local commands = getExecutedCommands()
            for _, cmd in ipairs(commands) do
                assert.is_falsy(cmd:match("killall bluetoothd"))
            end
            assert.is_falsy(file_mocker.writes[BT_CONTROL_DEVICE])
        end)
    end)
end)
