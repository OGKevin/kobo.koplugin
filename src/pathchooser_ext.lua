---
--- PathChooser extensions for bypassing virtual library.
--- Monkey patches PathChooser to support bypass_virtual_library option.

local logger = require("logger")

local PathChooserExt = {}

---
--- Initializes the PathChooser extension with required dependencies.
--- @param deps table: Dependencies table containing virtual_library.
function PathChooserExt:init(deps)
    self.virtual_library = deps.virtual_library
end

---
--- Applies monkey patches to PathChooser to support bypassing virtual library.
function PathChooserExt:apply()
    local PathChooser = require("ui/widget/pathchooser")
    local FileChooser = require("ui/widget/filechooser")

    local original_init = PathChooser.init
    local original_genItemTableFromPath = FileChooser.genItemTableFromPath
    local original_changeToPath = FileChooser.changeToPath

    ---
    --- Wraps PathChooser.init to store bypass_virtual_library flag.
    PathChooser.init = function(path_chooser_self)
        path_chooser_self._bypass_virtual_library = path_chooser_self.bypass_virtual_library or false
        original_init(path_chooser_self)
    end

    ---
    --- Wraps FileChooser.genItemTableFromPath to bypass virtual library when flag is set.
    --- Only bypasses if instance is a PathChooser with bypass_virtual_library flag.
    FileChooser.genItemTableFromPath = function(file_chooser_self, path)
        local is_path_chooser = file_chooser_self.onLeftButtonTap ~= nil

        if is_path_chooser and file_chooser_self._bypass_virtual_library then
            local virtual_library = PathChooserExt.virtual_library
            if virtual_library then
                local saved_active = virtual_library._file_chooser_bypass_active
                virtual_library._file_chooser_bypass_active = true

                local result = original_genItemTableFromPath(file_chooser_self, path)

                virtual_library._file_chooser_bypass_active = saved_active
                return result
            end
        end

        return original_genItemTableFromPath(file_chooser_self, path)
    end

    ---
    --- Wraps FileChooser.changeToPath to bypass virtual library when flag is set.
    --- Only bypasses if instance is a PathChooser with bypass_virtual_library flag.
    FileChooser.changeToPath = function(file_chooser_self, path, ...)
        local is_path_chooser = file_chooser_self.onLeftButtonTap ~= nil

        if is_path_chooser and file_chooser_self._bypass_virtual_library then
            local virtual_library = PathChooserExt.virtual_library
            if virtual_library then
                local saved_active = virtual_library._file_chooser_bypass_active
                virtual_library._file_chooser_bypass_active = true

                local result = original_changeToPath(file_chooser_self, path, ...)

                virtual_library._file_chooser_bypass_active = saved_active
                return result
            end
        end

        return original_changeToPath(file_chooser_self, path, ...)
    end

    logger.info("PathChooserExt: Applied monkey patches for bypass_virtual_library support")
end

return PathChooserExt
