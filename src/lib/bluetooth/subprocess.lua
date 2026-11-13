---
--- Helpers for detaching child processes and daemons from the onboard storage.

local bit = require("bit")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

require("ffi/posix_h")

pcall(ffi.cdef, "int chdir(const char *path);")
pcall(ffi.cdef, "long sysconf(int name);")
pcall(ffi.cdef, "int open(const char *pathname, int flags, ...);")
pcall(ffi.cdef, "int close(int fd);")
pcall(ffi.cdef, "int dup2(int oldfd, int newfd);")
pcall(ffi.cdef, "int fork(void);")
pcall(ffi.cdef, "int setsid(void);")
pcall(ffi.cdef, "int execvp(const char *file, char *const argv[]);")
pcall(ffi.cdef, "int waitpid(int pid, int *status, int options);")
pcall(ffi.cdef, "void _exit(int status);")

local C = ffi.C

local STDIN_FILENO = 0
local STDOUT_FILENO = 1
local STDERR_FILENO = 2
local O_RDWR = 2
local EINTR = 4
local EXEC_FAILURE_STATUS = 127

local posix_adapter = {
    chdir = function(path)
        return tonumber(C.chdir(path))
    end,
    sysconf = function(name)
        return tonumber(C.sysconf(name))
    end,
    open = function(path, flags)
        return tonumber(C.open(path, flags))
    end,
    close = function(fd)
        return tonumber(C.close(fd))
    end,
    dup2 = function(oldfd, newfd)
        return tonumber(C.dup2(oldfd, newfd))
    end,
    fork = function()
        return tonumber(C.fork())
    end,
    setsid = function()
        return tonumber(C.setsid())
    end,
    execvp = function(file, argv)
        return tonumber(C.execvp(file, argv))
    end,
    waitpid = function(pid, status, options)
        return tonumber(C.waitpid(pid, status, options))
    end,
    _exit = function(status)
        C._exit(status)
    end,
    errno = function()
        return tonumber(ffi.errno())
    end,
}

local Subprocess = {
    _posix = posix_adapter,
}

--- Directory the subprocess moves to: on tmpfs, so it holds nothing on the
--- onboard partition.
Subprocess.WORKING_DIRECTORY = "/tmp"

--- Directory scanned by isProcessRunning to inspect live process command lines.
Subprocess.PROC_DIR = "/proc"

--- sysconf name for the per-process limit on open files (_SC_OPEN_MAX on Linux).
Subprocess.SC_OPEN_MAX = 4

--- Fallback for the open-file limit when sysconf cannot tell.
Subprocess.DEFAULT_OPEN_MAX = 1024

---
--- Copies a Lua string into a NUL-terminated C char buffer for execvp.
--- @param value string
--- @return userdata
local function _cstring(value)
    local buf = ffi.new("char[?]", #value + 1)
    ffi.copy(buf, value)

    return buf
end

---
--- Reads the entire content of a file, returning nil when it cannot be opened.
--- @param path string
--- @return string|nil
local function _readFile(path)
    local file = io.open(path, "r")

    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()

    return content
end

---
--- Redirects stdin, stdout and stderr to /dev/null in a forked child so standard
--- streams pointing at KOReader's log on /mnt/onboard are released.
--- @param posix table Syscall table
local function _redirectStandardStreamsToNull(posix)
    local devnull_fd = posix.open("/dev/null", O_RDWR)

    if devnull_fd < 0 then
        return
    end

    posix.dup2(devnull_fd, STDIN_FILENO)
    posix.dup2(devnull_fd, STDOUT_FILENO)
    posix.dup2(devnull_fd, STDERR_FILENO)

    if devnull_fd > STDERR_FILENO then
        posix.close(devnull_fd)
    end
end

---
--- Detaches a forked child from onboard storage and replaces the process image
--- with argv[1] via execvp, exiting with status 127 if execvp fails.
--- @param posix table Syscall table
--- @param argv table Non-empty array of program path and arguments
local function _execDetachedChild(posix, argv)
    posix.chdir(Subprocess.WORKING_DIRECTORY)
    _redirectStandardStreamsToNull(posix)

    for fd = 3, Subprocess.openFileLimit() - 1 do
        posix.close(fd)
    end

    local c_argv = ffi.new("char *[?]", #argv + 1)
    local buffers = {}

    for i, arg in ipairs(argv) do
        buffers[i] = _cstring(arg)
        c_argv[i - 1] = buffers[i]
    end

    posix.execvp(argv[1], c_argv)
    posix._exit(EXEC_FAILURE_STATUS)
end

---
--- Waits for a forked child to terminate, retrying across EINTR, and checks
--- that it exited normally with status 0.
--- @param posix table Syscall table
--- @param pid number Child process ID
--- @return boolean True if the child exited cleanly with status 0
local function _waitForSuccess(posix, pid)
    local status_buf = ffi.new("int[1]")
    local waited = posix.waitpid(pid, status_buf, 0)

    while waited < 0 and posix.errno() == EINTR do
        waited = posix.waitpid(pid, status_buf, 0)
    end

    if waited ~= pid then
        logger.warn("Subprocess: waitpid failed for pid", pid, "errno:", posix.errno())

        return false
    end

    local raw_status = tonumber(status_buf[0])
    local terminating_signal = bit.band(raw_status, 0x7f)

    if terminating_signal ~= 0 then
        logger.warn("Subprocess: pid", pid, "terminated by signal", terminating_signal)

        return false
    end

    local exit_code = bit.band(bit.rshift(raw_status, 8), 0xff)

    if exit_code ~= 0 then
        logger.warn("Subprocess: pid", pid, "exited with status", exit_code)

        return false
    end

    return true
end

---
--- Highest file descriptor number a process can have open, plus one.
--- @return number
function Subprocess.openFileLimit()
    local limit = Subprocess._posix.sysconf(Subprocess.SC_OPEN_MAX)

    if not limit or limit <= 0 then
        return Subprocess.DEFAULT_OPEN_MAX
    end

    return limit
end

---
--- Releases everything the subprocess inherited that pins the onboard storage:
--- the working directory (KOReader runs from /mnt/onboard/.adds/koreader) and
--- the open files (book, settings, databases). A child that keeps those while
--- it waits for D-Bus makes the storage impossible to unmount, so plugging in
--- the USB cable fails with a busy filesystem until the child has exited.
--- This is what KOReader's own Kobo scripts do for the same reason
--- (platform/kobo/koreader.sh relocates itself off the onboard partition for
--- USB mass storage, platform/kobo/enable-wifi.sh closes every inherited fd).
--- stdin/stdout/stderr are kept so the child can still log.
function Subprocess.detachFromStorage()
    local posix = Subprocess._posix

    if posix.chdir(Subprocess.WORKING_DIRECTORY) ~= 0 then
        logger.warn("Subprocess: chdir", Subprocess.WORKING_DIRECTORY, "failed, errno:", posix.errno())
    end

    for fd = 3, Subprocess.openFileLimit() - 1 do
        posix.close(fd)
    end
end

---
--- Checks whether a live user-space process is running the given program by
--- reading /proc/<pid>/cmdline directly from Lua instead of spawning pgrep.
--- Matches either the full argv[0] path or its basename.
--- @param target string Program path or basename
--- @return boolean True if a matching live process exists
function Subprocess.isProcessRunning(target)
    if type(target) ~= "string" or target == "" then
        return false
    end

    local target_name = target:match("([^/]+)$") or target
    local ok, iterator, state = pcall(lfs.dir, Subprocess.PROC_DIR)

    if not ok then
        return false
    end

    for entry in iterator, state do
        if entry:match("^%d+$") then
            local cmdline = _readFile(Subprocess.PROC_DIR .. "/" .. entry .. "/cmdline") or ""
            local argv0 = cmdline:match("^[^%z]+")

            if argv0 then
                local argv0_name = argv0:match("([^/]+)$") or argv0

                if argv0 == target or argv0_name == target_name then
                    return true
                end
            end
        end
    end

    return false
end

---
--- Runs a program in a forked child detached from onboard storage (working
--- directory on WORKING_DIRECTORY, stdin/stdout/stderr on /dev/null, inherited
--- descriptors above stderr closed) and waits for it to exit.
--- @param argv table Non-empty array of program path and arguments
--- @return boolean True if the program exited with status 0
function Subprocess.runDetached(argv)
    if type(argv) ~= "table" or type(argv[1]) ~= "string" or argv[1] == "" then
        logger.warn("Subprocess: invalid argv for runDetached")

        return false
    end

    local posix = Subprocess._posix
    local pid = posix.fork()

    if pid < 0 then
        logger.warn("Subprocess: fork() failed for", argv[1], "errno:", posix.errno())

        return false
    end

    if pid == 0 then
        _execDetachedChild(posix, argv)

        return false
    end

    return _waitForSuccess(posix, pid)
end

---
--- Starts a long-lived daemon directly from Lua via setsid and double-fork,
--- detached from onboard storage (working directory on WORKING_DIRECTORY,
--- stdin/stdout/stderr on /dev/null, inherited descriptors above stderr closed)
--- with no shell wrapper and the intermediate child immediately reaped.
--- @param argv table Non-empty array of daemon path and arguments
--- @return boolean True if the intermediate launcher succeeded
function Subprocess.startDaemon(argv)
    if type(argv) ~= "table" or type(argv[1]) ~= "string" or argv[1] == "" then
        logger.warn("Subprocess: invalid argv for startDaemon")

        return false
    end

    local posix = Subprocess._posix
    local pid = posix.fork()

    if pid < 0 then
        logger.warn("Subprocess: fork() failed for daemon", argv[1], "errno:", posix.errno())

        return false
    end

    if pid == 0 then
        if posix.setsid() < 0 then
            posix._exit(EXEC_FAILURE_STATUS)

            return false
        end

        local daemon_pid = posix.fork()

        if daemon_pid < 0 then
            posix._exit(EXEC_FAILURE_STATUS)

            return false
        end

        if daemon_pid == 0 then
            _execDetachedChild(posix, argv)

            return false
        end

        posix._exit(0)

        return false
    end

    return _waitForSuccess(posix, pid)
end

return Subprocess
