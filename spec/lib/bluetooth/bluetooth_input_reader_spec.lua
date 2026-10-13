---
--- Unit tests for the gesture translation in BluetoothInputReader.
--- The helper replaces the module with a stub for the other specs (it reads
--- device nodes through FFI); these tests load the real module, whose event
--- processing is plain Lua.

require("spec.helper")

describe("BluetoothInputReader gesture translation", function()
    local MODULE = "src/lib/bluetooth/bluetooth_input_reader"
    local BluetoothInputReader
    local stub_loader

    local EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
    local ABS_X, ABS_Y = 0, 1
    local BTN_TOUCH = 330
    local BTN_TOOL_FINGER = 325
    local KEY_VOLUMEUP = 115

    setup(function()
        stub_loader = package.preload[MODULE]
        package.preload[MODULE] = nil
        package.loaded[MODULE] = nil
        BluetoothInputReader = require(MODULE)
    end)

    teardown(function()
        package.loaded[MODULE] = nil
        package.preload[MODULE] = stub_loader
    end)

    local reader
    local emitted

    before_each(function()
        reader = BluetoothInputReader:new()
        emitted = {}
        reader:registerKeyCallback(function(code, value)
            table.insert(emitted, { code = code, value = value })
        end)
    end)

    local function event(ev_type, code, value)
        return { type = ev_type, code = code, value = value, time = { sec = 0, usec = 0 } }
    end

    -- Sends one evdev frame (events followed by SYN_REPORT)
    local function frame(events)
        for _, ev in ipairs(events) do
            reader:_processEvent(ev)
        end
        reader:_processEvent(event(EV_SYN, 0, 0))
    end

    -- A full touch contact as a touch-screen style remote sends it: finger down at
    -- (x1, y1), positions along the way, finger up.
    local function touch(x1, y1, x2, y2)
        frame({ event(EV_KEY, BTN_TOUCH, 1), event(EV_ABS, ABS_X, x1), event(EV_ABS, ABS_Y, y1) })
        frame({ event(EV_ABS, ABS_X, (x1 + x2) / 2), event(EV_ABS, ABS_Y, (y1 + y2) / 2) })
        frame({ event(EV_ABS, ABS_X, x2), event(EV_ABS, ABS_Y, y2) })
        frame({ event(EV_KEY, BTN_TOUCH, 0) })
    end

    local function codes()
        local result = {}
        for _, e in ipairs(emitted) do
            table.insert(result, e.code .. ":" .. e.value)
        end
        return table.concat(result, " ")
    end

    it("should pass plain key events through unchanged", function()
        frame({ event(EV_KEY, KEY_VOLUMEUP, 1) })
        frame({ event(EV_KEY, KEY_VOLUMEUP, 0) })

        assert.are.equal("115:1 115:0", codes())
    end)

    it("should turn a contact without movement into one tap press and release", function()
        touch(500, 500, 500, 500)

        local tap = BluetoothInputReader.GESTURE_TAP
        assert.are.equal(tap .. ":1 " .. tap .. ":0", codes())
    end)

    it("should turn a swipe with increasing Y into swipe down", function()
        touch(500, 300, 500, 700)

        assert.are.equal(BluetoothInputReader.GESTURE_SWIPE_DOWN, emitted[1].code)
        assert.are.equal(2, #emitted)
    end)

    it("should turn a swipe with decreasing Y into swipe up", function()
        touch(500, 700, 500, 300)

        assert.are.equal(BluetoothInputReader.GESTURE_SWIPE_UP, emitted[1].code)
    end)

    it("should turn horizontal swipes into left and right", function()
        touch(700, 500, 300, 500)
        touch(300, 500, 700, 500)

        assert.are.equal(BluetoothInputReader.GESTURE_SWIPE_LEFT, emitted[1].code)
        assert.are.equal(BluetoothInputReader.GESTURE_SWIPE_RIGHT, emitted[3].code)
        assert.are.equal(4, #emitted)
    end)

    it("should fire a swipe as soon as its direction is clear, before the finger lifts", function()
        frame({ event(EV_KEY, BTN_TOUCH, 1), event(EV_ABS, ABS_X, 500), event(EV_ABS, ABS_Y, 300) })
        assert.are.equal(0, #emitted)

        frame({ event(EV_ABS, ABS_Y, 600) })
        assert.are.equal(2, #emitted)
        assert.are.equal(BluetoothInputReader.GESTURE_SWIPE_DOWN, emitted[1].code)

        -- Further movement and the release add nothing: one gesture per contact
        frame({ event(EV_ABS, ABS_Y, 900) })
        frame({ event(EV_KEY, BTN_TOUCH, 0) })
        assert.are.equal(2, #emitted)
    end)

    it("should treat movement below 5% of the coordinate range as a tap", function()
        touch(500, 500, 520, 510)

        assert.are.equal(BluetoothInputReader.GESTURE_TAP, emitted[1].code)
    end)

    it("should swallow the tool buttons that accompany a touch contact", function()
        frame({ event(EV_KEY, BTN_TOOL_FINGER, 1), event(EV_KEY, BTN_TOUCH, 1), event(EV_ABS, ABS_X, 500) })
        frame({ event(EV_KEY, BTN_TOOL_FINGER, 0), event(EV_KEY, BTN_TOUCH, 0) })

        assert.are.equal(2, #emitted)
        assert.are.equal(BluetoothInputReader.GESTURE_TAP, emitted[1].code)
        assert.are.equal(BluetoothInputReader.GESTURE_TAP, emitted[2].code)
    end)

    it("should swallow a key that arrives in the same frame as the touch button", function()
        frame({ event(EV_KEY, BTN_TOUCH, 1), event(EV_KEY, KEY_VOLUMEUP, 1), event(EV_ABS, ABS_X, 500) })
        frame({ event(EV_KEY, BTN_TOUCH, 0) })

        for _, e in ipairs(emitted) do
            assert.is_not.equal(KEY_VOLUMEUP, e.code)
        end
    end)

    it("should deliver each gesture to every registered callback", function()
        local second = 0
        reader:registerKeyCallback(function()
            second = second + 1
        end)

        touch(500, 500, 500, 500)

        assert.are.equal(2, #emitted)
        assert.are.equal(2, second)
    end)
end)
