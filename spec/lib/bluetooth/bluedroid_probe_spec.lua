---
-- Unit tests for the legacy bluedroid D-Bus probe.

require("spec.helper")

describe("BluedroidProbe", function()
    local BluedroidProbe

    before_each(function()
        resetAllMocks()
        BluedroidProbe = require("src/lib/bluetooth/bluedroid_probe")
    end)

    describe("probeService", function()
        it("should report the service as owned when it is running", function()
            setMockPopenOutput(
                "method return sender=:1.23 -> dest=:1.42 reply_serial=2\n" .. "   variant       boolean true"
            )

            assert.are.equal(BluedroidProbe.OWNED, BluedroidProbe.probeService())
        end)

        it("should report the service as absent when it is neither owned nor activatable", function()
            setMockPopenOutput(
                "variant boolean false\n" .. '   string "com.kobo.wifiservice"\n' .. '   string "org.bluez"'
            )

            assert.are.equal(BluedroidProbe.ABSENT, BluedroidProbe.probeService())
        end)

        it("should report the service as activatable when only the bus could start it", function()
            setMockPopenOutput(
                "variant boolean false\n" .. '   string "com.kobo.mtk.bluedroid"\n' .. '   string "org.bluez"'
            )

            assert.are.equal(BluedroidProbe.ACTIVATABLE, BluedroidProbe.probeService())
        end)

        it("should match the service name exactly, not as a substring", function()
            setMockPopenOutput("variant boolean false\n" .. '   string "com.kobo.mtk.bluedroid2"')

            assert.are.equal(BluedroidProbe.ABSENT, BluedroidProbe.probeService())
        end)

        it("should report unknown when the bus query returns nothing", function()
            setMockPopenOutput("")

            assert.are.equal(BluedroidProbe.UNKNOWN, BluedroidProbe.probeService())
        end)

        it("should report unknown when the bus query fails", function()
            setMockPopenFailure()

            assert.are.equal(BluedroidProbe.UNKNOWN, BluedroidProbe.probeService())
        end)

        it("should report unknown when the query output is unparseable", function()
            setMockPopenOutput("Error org.freedesktop.DBus.Error.AccessDenied: not allowed")

            assert.are.equal(BluedroidProbe.UNKNOWN, BluedroidProbe.probeService())
        end)

        it("should ask the bus itself for the owner, without activating the service", function()
            setMockPopenOutput("variant boolean false")

            local popen_calls = {}
            local real_popen = io.popen
            io.popen = function(cmd)
                table.insert(popen_calls, cmd)
                return real_popen(cmd)
            end

            BluedroidProbe.probeService()

            io.popen = real_popen

            assert.is_truthy(
                popen_calls[1]:match("org%.freedesktop%.DBus%.NameHasOwner string:com%.kobo%.mtk%.bluedroid")
            )
            -- both queries address the bus object itself, which never starts a service
            assert.is_truthy(popen_calls[2]:match("org%.freedesktop%.DBus%.ListActivatableNames"))
        end)

        it("should check activatable names only when the service is not owned", function()
            local popen_calls = {}
            local real_popen = io.popen
            io.popen = function(cmd)
                table.insert(popen_calls, cmd)
                return real_popen(cmd)
            end

            setMockPopenOutput("variant boolean true")
            BluedroidProbe.probeService()
            assert.are.equal(1, #popen_calls)

            setMockPopenOutput("variant boolean false")
            BluedroidProbe.probeService()
            assert.are.equal(3, #popen_calls)

            io.popen = real_popen
        end)
    end)
end)
