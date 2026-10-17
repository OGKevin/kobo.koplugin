-- User patch to add dispatcher actions for going to the next & previous page in filemanager
-- Priority: 2

local Dispatcher = require("dispatcher")
local FileManager = require("apps/filemanager/filemanager")
local _ = require("gettext")

-- Add the onGotoNextPage method to FileManager
FileManager.onGotoNextPage = function(self)
    if self.file_chooser then
        local current_page = self.file_chooser.page
        local total_pages = self.file_chooser.page_num

        if current_page < total_pages then
            self.file_chooser:onGotoPage(current_page + 1)
        else
            self.file_chooser:onFirstPage()
        end
        return true
    end
    return false
end

-- Add the onGotoPrevPage method to FileManager
FileManager.onGotoPrevPage = function(self)
    if self.file_chooser then
        local current_page = self.file_chooser.page

        if current_page > 1 then
            self.file_chooser:onGotoPage(current_page - 1)
        else
            self.file_chooser:onLastPage()
        end
        return true
    end
    return false
end

-- Register the dispatcher actions
Dispatcher:registerAction("filemanager_next_page", {
    category = "none",
    event = "GotoNextPage",
    title = _("Next Page"),
    filemanager = true,
})

Dispatcher:registerAction("filemanager_prev_page", {
    category = "none",
    event = "GotoPrevPage",
    title = _("Previous Page"),
    filemanager = true,
})
