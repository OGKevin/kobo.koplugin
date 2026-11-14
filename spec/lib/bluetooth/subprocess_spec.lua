---
-- Unit tests for the Subprocess module.

local helper = require("spec.helper")

describe("Subprocess", function()
    local Subprocess
    local lfs
    local ffi = require("ffi")

    pcall(ffi.cdef, "int open(const char *pathname, int flags, ...);")
    pcall(ffi.cdef, "int close(int fd);")
    pcall(ffi.cdef, "int usleep(unsigned int useconds);")

    local O_RDWR = 2
    local FD_LIMIT = 64
    local CHILD_PID = 4242
    local DAEMON_PID = 4243
    local EINTR = 4
    local FILES = {
        pwd = "/tmp/kobo-subprocess-spec-pwd",
        stdio = "/tmp/kobo-subprocess-spec-stdio",
        leaked_fd = "/tmp/kobo-subprocess-spec-fd",
        daemon = "/tmp/kobo-subprocess-spec-daemon",
    }

    local real_posix
    local files

    local function file_exists(path)
        local fd = ffi.C.open(path, O_RDWR)

        if fd < 0 then
            return false
        end

        ffi.C.close(fd)

        return true
    end

    local function read_file(path)
        local file = io.open(path, "r")

        if not file then
            return nil
        end

        local content = file:read("*a")
        file:close()

        return content
    end

    local function remove_files()
        for _, path in pairs(FILES) do
            os.remove(path)
        end
    end

    local function wait_for_file(path, attempts)
        for _ = 1, attempts or 100 do
            if file_exists(path) then
                local content = read_file(path)

                if content and #content > 0 then
                    return content
                end
            end

            ffi.C.usleep(50000)
        end

        return nil
    end

    local function inherited_fds()
        local fds = {}

        for fd = 3, FD_LIMIT - 1 do
            table.insert(fds, fd)
        end

        return fds
    end

    local function with_fds(...)
        local fds = { ... }

        for _, fd in ipairs(inherited_fds()) do
            table.insert(fds, fd)
        end

        return fds
    end

    local function bounded_posix()
        local adapter = {}

        for name, syscall in pairs(real_posix) do
            adapter[name] = syscall
        end

        adapter.sysconf = function()
            return FD_LIMIT
        end

        return adapter
    end

    local function make_posix_mock()
        local calls = {
            chdir = {},
            closed = {},
            opened = {},
            dup2 = {},
            execvp = {},
            exit = {},
            waitpid = {},
            setsid = 0,
            forks = 0,
        }
        local statuses = {}
        local mock = {
            errno = function()
                return 0
            end,
            chdir = function(path)
                table.insert(calls.chdir, path)

                return 0
            end,
            sysconf = function()
                return FD_LIMIT
            end,
            open = function(path, flags)
                table.insert(calls.opened, { path = path, flags = flags })

                return 44
            end,
            close = function(fd)
                table.insert(calls.closed, fd)

                return 0
            end,
            dup2 = function(oldfd, newfd)
                table.insert(calls.dup2, { oldfd = oldfd, newfd = newfd })

                return newfd
            end,
            fork = function()
                calls.forks = calls.forks + 1

                return CHILD_PID
            end,
            setsid = function()
                calls.setsid = calls.setsid + 1

                return 0
            end,
            execvp = function(file, argv)
                local args = {}
                local i = 0

                while argv[i] ~= nil do
                    table.insert(args, ffi.string(argv[i]))
                    i = i + 1
                end

                table.insert(calls.execvp, { file = file, argv = args })

                return -1
            end,
            waitpid = function(pid, status, options)
                table.insert(calls.waitpid, { pid = pid, options = options })
                status[0] = table.remove(statuses, 1) or 0

                return pid
            end,
            _exit = function(status)
                table.insert(calls.exit, status)
            end,
        }

        return mock, calls, statuses
    end

    local function text_file(content)
        return {
            read = function()
                return content
            end,
            close = function()
                return true
            end,
        }
    end

    setup(function()
        lfs = require("libs/libkoreader-lfs")
        Subprocess = dofile("src/lib/bluetooth/subprocess.lua")
        real_posix = Subprocess._posix
    end)

    before_each(function()
        remove_files()
    end)

    after_each(function()
        Subprocess._posix = real_posix
        remove_files()
    end)

    describe("detachFromStorage", function()
        it("should move to the working directory and close inherited descriptors", function()
            local mock, calls = make_posix_mock()
            Subprocess._posix = mock

            Subprocess.detachFromStorage()

            assert.same({ Subprocess.WORKING_DIRECTORY }, calls.chdir)
            assert.same(inherited_fds(), calls.closed)
        end)
    end)

    describe("isProcessRunning", function()
        before_each(function()
            files = helper.createIOOpenMocker()
            files.install()
            lfs._clearFileStates()
        end)

        after_each(function()
            files.uninstall()
            files.clear()
            lfs._clearFileStates()
        end)

        it("should match a process by its full argv[0] and by its basename", function()
            lfs._setDirectoryContents(Subprocess.PROC_DIR, { "1", "1878", "self" })
            files.setMockFile("/proc/1/cmdline", text_file("init\0"))
            files.setMockFile("/proc/1878/cmdline", text_file("/sbin/rtk_hciattach\0-s\0115200\0ttymxc1\0rtk_h5\0"))

            assert.is_true(Subprocess.isProcessRunning("/sbin/rtk_hciattach"))
            assert.is_true(Subprocess.isProcessRunning("rtk_hciattach"))
            assert.is_false(Subprocess.isProcessRunning("/libexec/bluetooth/bluetoothd"))
        end)

        it("should ignore zombies and entries that are not process IDs", function()
            lfs._setDirectoryContents(Subprocess.PROC_DIR, { "1", "1878", "self" })
            files.setMockFile("/proc/1/cmdline", text_file(""))

            assert.is_false(Subprocess.isProcessRunning("rtk_hciattach"))
        end)

        it("should be false when /proc cannot be read", function()
            lfs._setDirectoryContents(Subprocess.PROC_DIR, nil)

            assert.is_false(Subprocess.isProcessRunning("rtk_hciattach"))
        end)

        it("should reject an empty target", function()
            assert.is_false(Subprocess.isProcessRunning(nil))
            assert.is_false(Subprocess.isProcessRunning(""))
        end)
    end)

    describe("runDetached", function()
        it("should wait for the forked child", function()
            local mock, calls = make_posix_mock()
            Subprocess._posix = mock

            assert.is_true(Subprocess.runDetached({ "/sbin/rtk_hciattach", "-s", "115200" }))
            assert.are.equal(1, calls.forks)
            assert.same({ { pid = CHILD_PID, options = 0 } }, calls.waitpid)
            assert.same({}, calls.execvp)
        end)

        it("should report a non-zero exit status", function()
            local mock, calls, statuses = make_posix_mock()
            Subprocess._posix = mock
            table.insert(statuses, 42 * 256)

            assert.is_false(Subprocess.runDetached({ "sh", "-c", "exit 42" }))
            assert.are.equal(1, #calls.waitpid)
        end)

        it("should report a child killed by a signal", function()
            local mock, calls, statuses = make_posix_mock()
            Subprocess._posix = mock
            table.insert(statuses, 15)

            assert.is_false(Subprocess.runDetached({ "sh", "-c", "sleep 1" }))
            assert.are.equal(1, #calls.waitpid)
        end)

        it("should retry the wait across EINTR", function()
            local mock, calls, statuses = make_posix_mock()
            local attempts = 0
            mock.errno = function()
                return EINTR
            end
            mock.waitpid = function(pid, status, options)
                attempts = attempts + 1
                table.insert(calls.waitpid, { pid = pid, options = options })
                status[0] = table.remove(statuses, 1) or 0

                if attempts == 1 then
                    return -1
                end

                return pid
            end
            Subprocess._posix = mock

            assert.is_true(Subprocess.runDetached({ "sh", "-c", "exit 0" }))
            assert.are.equal(2, #calls.waitpid)
        end)

        it("should report a failed fork", function()
            local mock, calls = make_posix_mock()
            mock.fork = function()
                return -1
            end
            Subprocess._posix = mock

            assert.is_false(Subprocess.runDetached({ "sh", "-c", "exit 0" }))
            assert.same({}, calls.waitpid)
        end)

        it("should reject an empty argv", function()
            assert.is_false(Subprocess.runDetached({}))
            assert.is_false(Subprocess.runDetached({ "" }))
            assert.is_false(Subprocess.runDetached(nil))
        end)

        it("should reject a non-string argument before forking", function()
            local mock, calls = make_posix_mock()
            Subprocess._posix = mock

            assert.is_false(Subprocess.runDetached({ "/sbin/rtk_hciattach", 115200 }))
            assert.are.equal(0, calls.forks)
            assert.same({}, calls.execvp)
        end)

        it("should exit 127 when the child setup raises", function()
            local mock, calls = make_posix_mock()
            mock.fork = function()
                return 0
            end
            mock.open = function()
                error("cannot open /dev/null")
            end
            Subprocess._posix = mock

            assert.is_false(Subprocess.runDetached({ "/sbin/rtk_hciattach" }))
            assert.same({}, calls.execvp)
            assert.same({ 127 }, calls.exit)
        end)

        it("should detach and exec the program in the child", function()
            local mock, calls = make_posix_mock()
            mock.fork = function()
                return 0
            end
            Subprocess._posix = mock

            Subprocess.runDetached({ "/libexec/bluetooth/bluetoothd", "-n" })

            assert.same({ Subprocess.WORKING_DIRECTORY }, calls.chdir)
            assert.same({ { path = "/dev/null", flags = O_RDWR } }, calls.opened)
            assert.same({
                { oldfd = 44, newfd = 0 },
                { oldfd = 44, newfd = 1 },
                { oldfd = 44, newfd = 2 },
            }, calls.dup2)
            assert.same(with_fds(44), calls.closed)
            assert.same(
                { { file = "/libexec/bluetooth/bluetoothd", argv = { "/libexec/bluetooth/bluetoothd", "-n" } } },
                calls.execvp
            )
            assert.same({ 127 }, calls.exit)
        end)
    end)

    describe("startDaemon", function()
        it("should reap the intermediate child and report success", function()
            local mock, calls = make_posix_mock()
            mock.fork = function()
                return DAEMON_PID
            end
            Subprocess._posix = mock

            assert.is_true(Subprocess.startDaemon({ "/libexec/bluetooth/bluetoothd" }))
            assert.same({ { pid = DAEMON_PID, options = 0 } }, calls.waitpid)
            assert.same({}, calls.execvp)
        end)

        it("should create a session, fork again and exit the intermediate child", function()
            local mock, calls = make_posix_mock()
            local forks = 0
            mock.fork = function()
                forks = forks + 1

                if forks == 1 then
                    return 0
                end

                return DAEMON_PID
            end
            Subprocess._posix = mock

            Subprocess.startDaemon({ "/libexec/bluetooth/bluetoothd" })

            assert.are.equal(1, calls.setsid)
            assert.same({ 0 }, calls.exit)
            assert.same({}, calls.execvp)
        end)

        it("should exec the daemon in the grandchild", function()
            local mock, calls = make_posix_mock()
            mock.fork = function()
                return 0
            end
            Subprocess._posix = mock

            Subprocess.startDaemon({ "/libexec/bluetooth/bluetoothd" })

            assert.are.equal(1, calls.setsid)
            assert.same(
                { { file = "/libexec/bluetooth/bluetoothd", argv = { "/libexec/bluetooth/bluetoothd" } } },
                calls.execvp
            )
            assert.same({ 127 }, calls.exit)
        end)

        it("should exit when setsid fails", function()
            local mock, calls = make_posix_mock()
            mock.fork = function()
                return 0
            end
            mock.setsid = function()
                return -1
            end
            Subprocess._posix = mock

            Subprocess.startDaemon({ "/libexec/bluetooth/bluetoothd" })

            assert.same({ 127 }, calls.exit)
            assert.same({}, calls.execvp)
        end)

        it("should report a failed fork", function()
            local mock, calls = make_posix_mock()
            mock.fork = function()
                return -1
            end
            Subprocess._posix = mock

            assert.is_false(Subprocess.startDaemon({ "/libexec/bluetooth/bluetoothd" }))
            assert.same({}, calls.waitpid)
        end)

        it("should reject an empty argv", function()
            assert.is_false(Subprocess.startDaemon({}))
            assert.is_false(Subprocess.startDaemon(nil))
        end)

        it("should reject a non-string argument before forking", function()
            local mock, calls = make_posix_mock()
            Subprocess._posix = mock

            assert.is_false(Subprocess.startDaemon({ "/libexec/bluetooth/bluetoothd", false }))
            assert.are.equal(0, calls.forks)
            assert.same({}, calls.execvp)
        end)
    end)

    describe("runDetached with real POSIX calls", function()
        before_each(function()
            Subprocess._posix = bounded_posix()
        end)

        it("should run the program from the working directory", function()
            assert.is_true(Subprocess.runDetached({ "sh", "-c", "pwd > " .. FILES.pwd }))
            assert.are.equal("/tmp\n", read_file(FILES.pwd))
        end)

        it("should report the exit status of the program", function()
            assert.is_true(Subprocess.runDetached({ "sh", "-c", "exit 0" }))
            assert.is_false(Subprocess.runDetached({ "sh", "-c", "exit 42" }))
        end)

        it("should close inherited descriptors and detach standard streams", function()
            local probe = assert(io.open(FILES.leaked_fd, "w"))
            probe:close()

            local fd = ffi.C.open(FILES.leaked_fd, O_RDWR)
            assert.is_true(fd > 2 and fd < FD_LIMIT)

            local script = "if [ -e /proc/self/fd/"
                .. fd
                .. " ]; then echo leaked; else echo closed; fi > "
                .. FILES.stdio
                .. "; readlink /proc/self/fd/0 >> "
                .. FILES.stdio
                .. "; readlink /proc/self/fd/2 >> "
                .. FILES.stdio

            assert.is_true(Subprocess.runDetached({ "sh", "-c", script }))
            ffi.C.close(fd)
            assert.are.equal("closed\n/dev/null\n/dev/null\n", read_file(FILES.stdio))
        end)
    end)

    describe("startDaemon with real POSIX calls", function()
        before_each(function()
            Subprocess._posix = bounded_posix()
        end)

        it("should start the daemon from the working directory", function()
            assert.is_true(Subprocess.startDaemon({ "sh", "-c", "pwd > " .. FILES.daemon }))
            assert.are.equal("/tmp\n", wait_for_file(FILES.daemon))
        end)

        it("should close inherited descriptors in the daemon", function()
            local probe = assert(io.open(FILES.leaked_fd, "w"))
            probe:close()

            local fd = ffi.C.open(FILES.leaked_fd, O_RDWR)
            assert.is_true(fd > 2 and fd < FD_LIMIT)

            local script = "if [ -e /proc/self/fd/"
                .. fd
                .. " ]; then echo leaked; else echo closed; fi > "
                .. FILES.daemon

            assert.is_true(Subprocess.startDaemon({ "sh", "-c", script }))
            ffi.C.close(fd)
            assert.are.equal("closed\n", wait_for_file(FILES.daemon))
        end)
    end)
end)
