-- User patch to fix position restoration bug in ReaderRolling
-- Bug: When restoring from last_percent in page mode, the code was calling
-- gotoPos(0) which reset the document to page 1 instead of the intended page.
-- This patch fixes the setupXpointer function to only call gotoPos in scroll mode.
-- Priority: 2

local logger = require("logger")

-- Patch require() to intercept ReaderRolling
local original_require = require
_G.require = function(modname)
    local result = original_require(modname)

    -- When ReaderRolling is required, patch it to fix the position restoration bug
    if modname == "apps/reader/modules/readerrolling" and type(result) == "table" then
        local ReaderRolling = result

        -- Patch onReadSettings (only patch once)
        if not ReaderRolling._patched_position_fix then
            local original_onReadSettings = ReaderRolling.onReadSettings
            ReaderRolling.onReadSettings = function(self, config)
                -- Call original first
                original_onReadSettings(self, config)

                -- Now patch the setupXpointer function that was created above
                -- We need to wrap it to fix the gotoPos bug in page mode
                local original_setupXpointer = self.setupXpointer
                if original_setupXpointer then
                    self.setupXpointer = function()
                        logger.info("ReaderRolling Position Fix: Applying position restoration fix")

                        -- Get the last_percent value if it exists
                        local last_per = config:readSetting("last_percent")

                        if last_per and self.view.view_mode == "page" then
                            -- In page mode with last_percent, we need to call gotoPercent
                            -- but NOT call gotoPos(0) which resets to page 1
                            logger.info("ReaderRolling Position Fix: Restoring page position from", last_per * 100, "%")
                            self:_gotoPercent(last_per * 100)
                            -- In page mode, _gotoPercent calls _gotoPage which already
                            -- handles everything. Don't call gotoPos!
                            -- Just update the xpointer
                            self.xpointer = self.ui.document:getXPointer()
                        else
                            -- For all other cases (xpointer or default), use original
                            original_setupXpointer()
                        end
                    end
                    ReaderRolling._patched_position_fix = true
                    logger.info("ReaderRolling Position Fix: Patch applied successfully")
                end
            end
            ReaderRolling._patched_position_fix = true
        end
    end

    return result
end
