---
-- Unit tests for StatusConverter module.

describe("StatusConverter", function()
    local StatusConverter

    setup(function()
        StatusConverter = require("lib/status_converter")
    end)

    describe("koboToKoreader", function()
        it("should convert Kobo status 0 (unopened) to empty string", function()
            assert.are.equal("", StatusConverter.koboToKoreader(0))
        end)

        it("should convert Kobo status 1 (reading) to 'reading'", function()
            assert.are.equal("reading", StatusConverter.koboToKoreader(1))
        end)

        it("should convert Kobo status 2 (finished) to 'complete'", function()
            assert.are.equal("complete", StatusConverter.koboToKoreader(2))
        end)

        it("should handle string Kobo status values", function()
            assert.are.equal("reading", StatusConverter.koboToKoreader("1"))
            assert.are.equal("complete", StatusConverter.koboToKoreader("2"))
        end)

        it("should default to 'abandoned' for unknown status", function()
            assert.are.equal("abandoned", StatusConverter.koboToKoreader(99))
        end)

        it("should handle nil as status 0 (empty string)", function()
            assert.are.equal("", StatusConverter.koboToKoreader(nil))
        end)
    end)

    describe("koreaderToKobo", function()
        it("should convert KOReader 'reading' to Kobo status 1", function()
            assert.are.equal(1, StatusConverter.koreaderToKobo("reading"))
        end)

        it("should convert KOReader 'in-progress' to Kobo status 1", function()
            assert.are.equal(1, StatusConverter.koreaderToKobo("in-progress"))
        end)

        it("should convert KOReader 'complete' to Kobo status 2", function()
            assert.are.equal(2, StatusConverter.koreaderToKobo("complete"))
        end)

        it("should convert KOReader 'finished' to Kobo status 2", function()
            assert.are.equal(2, StatusConverter.koreaderToKobo("finished"))
        end)

        it("should convert KOReader 'abandoned' to Kobo status 1 (reading)", function()
            assert.are.equal(1, StatusConverter.koreaderToKobo("abandoned"))
        end)

        it("should convert KOReader 'on-hold' to Kobo status 1 (reading)", function()
            assert.are.equal(1, StatusConverter.koreaderToKobo("on-hold"))
        end)

        it("should default to Kobo status 1 for unknown statuses", function()
            assert.are.equal(1, StatusConverter.koreaderToKobo("unknown"))
            assert.are.equal(1, StatusConverter.koreaderToKobo(nil))
        end)
    end)
end)
