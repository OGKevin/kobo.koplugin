describe("DocSettingsExt", function()
    local DocSettingsExt

    setup(function()
        require("spec/helper")
        DocSettingsExt = require("src/docsettings_ext")
    end)

    describe("location override for kepub files", function()
        local mock_virtual_library
        local mock_docsettings

        before_each(function()
            mock_virtual_library = {
                isActive = function()
                    return true
                end,
                isVirtualPath = function(self, path)
                    if type(path) ~= "string" then
                        return false
                    end
                    return path:match("^KOBO_VIRTUAL://") ~= nil
                end,
                getRealPath = function(self, path)
                    if path == "KOBO_VIRTUAL://shelf1/book.kepub.epub" then
                        return "/mnt/onboard/.kobo/kepub/ABC123"
                    end
                    return nil
                end,
                getVirtualPath = function(self, path)
                    if path == "/mnt/onboard/.kobo/kepub/ABC123" then
                        return "KOBO_VIRTUAL://shelf1/book.kepub.epub"
                    end
                    return nil
                end,
                real_to_virtual = {
                    ["/mnt/onboard/.kobo/kepub/ABC123"] = "KOBO_VIRTUAL://shelf1/book.kepub.epub",
                },
                parser = {
                    getKepubPath = function()
                        return "/mnt/onboard/.kobo/kepub"
                    end,
                },
            }

            -- Mock DocSettings
            mock_docsettings = {
                getSidecarDir = function(self, doc_path, force_location)
                    return doc_path .. ".sdr"
                end,
                getSidecarFilename = function(doc_path)
                    return "metadata." .. doc_path:match("([^/]+)$") .. ".lua"
                end,
                getHistoryPath = function(self, doc_path)
                    return "/mnt/onboard/.kobo/koreader/history/" .. doc_path:match("([^/]+)$") .. ".lua"
                end,
            }

            -- Reset G_reader_settings to empty state
            _G.G_reader_settings._settings = {}

            -- Initialize extension
            DocSettingsExt:init(mock_virtual_library)
            DocSettingsExt:apply(mock_docsettings)
        end)

        after_each(function()
            DocSettingsExt:unapply(mock_docsettings)
            _G.G_reader_settings._settings = {}
        end)

        it("should override 'doc' location to 'dir' for kepub files", function()
            _G.G_reader_settings._settings.document_metadata_folder = "doc"

            local result = mock_docsettings:getSidecarDir("KOBO_VIRTUAL://shelf1/book.kepub.epub")

            assert.equals("/mnt/onboard/.kobo/koreader/docsettings/mnt/onboard/.kobo/kepub/ABC123.sdr", result)
        end)

        it("should respect 'hash' location for kepub files", function()
            _G.G_reader_settings._settings.document_metadata_folder = "hash"

            local result = mock_docsettings:getSidecarDir("KOBO_VIRTUAL://shelf1/book.kepub.epub")

            -- Result should be hash-based path, not dir-based
            assert.is_not.equals("/mnt/onboard/.kobo/koreader/docsettings/mnt/onboard/.kobo/kepub/ABC123.sdr", result)
            assert.is_truthy(result:match("%.sdr$"))
        end)

        it("should respect 'dir' location for kepub files", function()
            _G.G_reader_settings._settings.document_metadata_folder = "dir"

            local result = mock_docsettings:getSidecarDir("KOBO_VIRTUAL://shelf1/book.kepub.epub")

            assert.equals("/mnt/onboard/.kobo/koreader/docsettings/mnt/onboard/.kobo/kepub/ABC123.sdr", result)
        end)

        it("should override 'doc' to 'dir' even when force_location is 'doc'", function()
            _G.G_reader_settings._settings.document_metadata_folder = "hash"

            local result = mock_docsettings:getSidecarDir("KOBO_VIRTUAL://shelf1/book.kepub.epub", "doc")

            assert.equals("/mnt/onboard/.kobo/koreader/docsettings/mnt/onboard/.kobo/kepub/ABC123.sdr", result)
        end)

        it("should not override for non-kepub files with 'doc' location", function()
            _G.G_reader_settings._settings.document_metadata_folder = "doc"

            local result = mock_docsettings:getSidecarDir("/mnt/onboard/Books/regular.epub")

            -- Should use original method, which returns path + .sdr
            assert.equals("/mnt/onboard/Books/regular.epub.sdr", result)
        end)
    end)
end)
