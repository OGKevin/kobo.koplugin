---
--- Helpers for code that runs inside a forked subprocess.

local ffi = require("ffi")
local logger = require("logger")

require("ffi/posix_h")

pcall(ffi.cdef, "int chdir(const char *path);")

local C = ffi.C

local Subprocess = {}

---
--- Releases everything the subprocess inherited that pins the onboard storage:
--- the working directory (KOReader runs from /mnt/onboard/.adds/koreader) and
--- the open files (book, settings, databases). A child that keeps those while
--- it waits for D-Bus makes the storage impossible to unmount, so plugging in
--- the USB cable fails with a busy filesystem until the child has exited.
--- stdin/stdout/stderr are kept so the child can still log.
function Subprocess.detachFromStorage()
    if C.chdir("/") ~= 0 then
        logger.warn("Subprocess: chdir / failed, errno:", ffi.errno())
    end

    for fd = 3, 1023 do
        C.close(fd)
    end
end

return Subprocess
