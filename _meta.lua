local _ = require("gettext")

return {
    id = "kobo.koplugin",
    name = "kobo",
    fullname = _("Kobo"),
    description = [[Browse and open unencrypted kepub books from Kobo Nickel library.
This plugin creates a virtual library from books synced via Kobo's Nickel OS,
allowing you to read them directly in KOReader without file extension workarounds.]],
    author = "OGKevin",
    version = "0.4.0", -- x-release-please-version
    supported_platforms = { "kobo" },
}
