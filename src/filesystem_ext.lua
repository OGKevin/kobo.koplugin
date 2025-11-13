-- Filesystem virtualization for Kobo kepub files
-- Monkey patches lfs and related filesystem functions to make virtual files appear real

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local FilesystemExt = {}

---
-- Initializes the filesystem extension with a virtual library instance.
-- @param virtual_library table: VirtualLibrary instance for path translation.
function FilesystemExt:init(virtual_library)
    self.virtual_library = virtual_library
    self.original_functions = {}
end

---
-- Creates the patched lfs.attributes function with virtual path support.
-- @param virtual_library table: VirtualLibrary instance for path translation.
-- @param original_lfs_attributes function: Original lfs.attributes function.
-- @return function: Patched attributes function that handles virtual paths.
local function createPatchedAttributesFunction(virtual_library, original_lfs_attributes)
    return function(filepath, ...)
        if type(filepath) == "string" and virtual_library:isVirtualPath(filepath) then
            logger.dbg("KoboPlugin: lfs.attributes intercepted virtual path:", filepath)
            local real_path = virtual_library:getRealPath(filepath)
            if real_path then
                logger.dbg("KoboPlugin: Redirecting to real path:", real_path)
                return original_lfs_attributes(real_path, ...)
            end
            logger.dbg("KoboPlugin: Virtual path has no real counterpart:", filepath)
            return nil
        end

        return original_lfs_attributes(filepath, ...)
    end
end

---
-- Applies filesystem virtualization patches.
-- Monkey-patches lfs.attributes to transparently redirect virtual paths to real files.
-- Only applies patches if the virtual library is active.
function FilesystemExt:apply()
    if not self.virtual_library:isActive() then
        logger.info("KoboPlugin: Kobo plugin not active, skipping filesystem patches")
        return
    end

    logger.info("KoboPlugin: Applying filesystem virtualization for Kobo kepub files")

    local virtual_library = self.virtual_library
    local original_lfs_attributes = lfs.attributes

    self.original_functions.lfs_attributes = original_lfs_attributes
    lfs.attributes = createPatchedAttributesFunction(virtual_library, original_lfs_attributes)
end

---
-- Removes filesystem virtualization patches.
-- Restores original lfs functions to their unpatched state.
function FilesystemExt:unapply()
    logger.info("KoboPlugin: Removing filesystem virtualization")

    if self.original_functions.lfs_attributes then
        lfs.attributes = self.original_functions.lfs_attributes
    end

    self.original_functions = {}
end

return FilesystemExt
