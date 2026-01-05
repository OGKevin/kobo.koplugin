---
-- Unit tests for PatternUtils module.

describe("PatternUtils", function()
    local PatternUtils

    setup(function()
        require("spec/helper")
        PatternUtils = require("src/lib/pattern_utils")
    end)

    describe("escape", function()
        it("should escape all Lua pattern special characters", function()
            local input = "^$()%.[]*+-?test"
            local escaped = PatternUtils.escape(input)

            -- The escaped string should work in a pattern without errors
            local test_string = "prefix^$()%.[]*+-?testsuffix"
            local match = test_string:match(escaped)

            assert.equals(input, match)
        end)

        it("should escape dots for literal matching", function()
            local path = "/mnt/onboard/.kobo/kepub"
            local escaped = PatternUtils.escape(path)

            -- Should match the exact path
            assert.is_not_nil(path:match("^" .. escaped))

            -- Should NOT match with any character in place of dots
            local wrong_path = "/mnt/onboardXkobo/kepub"
            assert.is_nil(wrong_path:match("^" .. escaped))
        end)

        it("should escape hyphens to prevent range interpretation", function()
            local input = "test-path"
            local escaped = PatternUtils.escape(input)

            -- Should match exact string
            assert.equals(input, input:match(escaped))

            -- The hyphen should not be interpreted as a range
            local test_string = "test-path"
            assert.is_not_nil(test_string:match(escaped))
        end)

        it("should escape caret to prevent start-of-string anchor", function()
            local input = "^test"
            local escaped = PatternUtils.escape(input)

            -- Should match the literal caret
            assert.equals(input, input:match(escaped))
            assert.equals(input, ("prefix^test"):match(escaped))
        end)

        it("should escape dollar to prevent end-of-string anchor", function()
            local input = "test$"
            local escaped = PatternUtils.escape(input)

            -- Should match the literal dollar sign
            assert.equals(input, input:match(escaped))
            assert.equals(input, ("test$suffix"):match(escaped))
        end)

        it("should escape parentheses to prevent captures", function()
            local input = "test(group)"
            local escaped = PatternUtils.escape(input)

            -- Should match literal parentheses
            assert.equals(input, input:match(escaped))
        end)

        it("should escape percent to prevent escape sequences", function()
            local input = "test%d"
            local escaped = PatternUtils.escape(input)

            -- Should match literal %d, not any digit
            assert.equals(input, input:match(escaped))
            local test_digit = "test5"
            assert.is_nil(test_digit:match(escaped))
        end)

        it("should escape square brackets to prevent character classes", function()
            local input = "test[abc]"
            local escaped = PatternUtils.escape(input)

            -- Should match literal brackets
            assert.equals(input, input:match(escaped))
            local test_char = "testa"
            assert.is_nil(test_char:match(escaped))
        end)

        it("should escape asterisk to prevent zero-or-more quantifier", function()
            local input = "test*"
            local escaped = PatternUtils.escape(input)

            -- Should match literal asterisk
            assert.equals(input, input:match(escaped))
        end)

        it("should escape plus to prevent one-or-more quantifier", function()
            local input = "test+"
            local escaped = PatternUtils.escape(input)

            -- Should match literal plus
            assert.equals(input, input:match(escaped))
        end)

        it("should escape question mark to prevent optional quantifier", function()
            local input = "test?"
            local escaped = PatternUtils.escape(input)

            -- Should match literal question mark
            assert.equals(input, input:match(escaped))
        end)

        it("should handle empty string", function()
            local escaped = PatternUtils.escape("")
            assert.equals("", escaped)
        end)

        it("should handle string with no special characters", function()
            local input = "test/path/file"
            local escaped = PatternUtils.escape(input)
            assert.equals(input, escaped)
        end)

        it("should handle nil input", function()
            local escaped = PatternUtils.escape(nil)
            assert.is_nil(escaped)
        end)

        it("should handle non-string input", function()
            local escaped = PatternUtils.escape(123)
            assert.equals(123, escaped)
        end)

        it("should work with real-world path examples", function()
            -- Test with actual kepub path
            local kepub_path = "/mnt/onboard/.kobo/kepub"
            local escaped = PatternUtils.escape(kepub_path)

            local test_path1 = "/mnt/onboard/.kobo/kepub/file"
            local test_path2 = "/mnt/onboard/.kobo/kepub"
            local test_path3 = "/mnt/onboardXkoboXkepub"

            assert.is_not_nil(test_path1:match("^" .. escaped))
            assert.is_not_nil(test_path2:match("^" .. escaped))
            assert.is_nil(test_path3:match("^" .. escaped))
        end)

        it("should work with virtual path prefix", function()
            local virtual_prefix = "KOBO_VIRTUAL://"
            local escaped = PatternUtils.escape(virtual_prefix)

            local test_path = "KOBO_VIRTUAL://file.epub"
            assert.is_not_nil(test_path:match("^" .. escaped))
        end)

        it("should consistently escape the same string", function()
            local input = "/mnt/onboard/.kobo/kepub"
            local escaped1 = PatternUtils.escape(input)
            local escaped2 = PatternUtils.escape(input)

            assert.equals(escaped1, escaped2)
        end)
    end)
end)
