import Foundation

#if !canImport(CoreGraphics)

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A minimal `posix_spawn` + `waitpid` process runner for the Linux rendering path.
///
/// Foundation's `Process` is deliberately not used here. `Process.waitUntilExit()`
/// has been observed to block forever on Linux/aarch64 *after* the child had already
/// exited and written a complete PDF: it waits on a termination notification that
/// never arrives, so the conversion wedges with no way for the caller to recover.
/// Waiting on our own child with `waitpid(2)` removes that layer, and the timeout
/// turns any remaining stall into a thrown error rather than an indefinite hang.
enum RsvgSubprocess {

    /// How a child process ended.
    enum Outcome {
        /// The child exited on its own with this status code.
        case exited(code: Int32)

        /// The child was killed by this signal.
        case signalled(signal: Int32)

        /// The child is gone, but something else in this process reaped it first,
        /// so its exit status is no longer available to us.
        case statusUnavailable
    }

    enum Failure: Error {
        /// The child could not be started at all.
        case launchFailed(reason: String)

        /// The child was still running when the timeout elapsed.
        case timedOut
    }

    /// Runs `executable`, redirecting the child's stderr to `stderrPath` and its
    /// stdout to `/dev/null`, and waits for it to finish.
    ///
    /// - Parameter timeout: Seconds to wait before giving up. On expiry the child
    ///   is sent `SIGTERM`, then `SIGKILL`, and `Failure.timedOut` is thrown.
    static func run(
        executable: String,
        arguments: [String],
        stderrPath: String,
        timeout: TimeInterval
    ) throws -> Outcome {
        let pid = try spawn(executable: executable, arguments: arguments, stderrPath: stderrPath)

        if let outcome = try reap(pid: pid, before: Date().addingTimeInterval(timeout)) {
            return outcome
        }

        // Timed out: ask the child to stop, then insist, so we neither leave it
        // running behind us nor leave a zombie in the process table.
        kill(pid, SIGTERM)
        if try reap(pid: pid, before: Date().addingTimeInterval(gracePeriod)) == nil {
            kill(pid, SIGKILL)
            _ = try? reap(pid: pid, before: Date().addingTimeInterval(gracePeriod))
        }
        throw Failure.timedOut
    }

    /// How long a signalled child is given to die before we escalate.
    private static let gracePeriod: TimeInterval = 2

    // MARK: - Spawning

    private static func spawn(executable: String, arguments: [String], stderrPath: String) throws -> pid_t {
        var fileActions = posix_spawn_file_actions_t()
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw Failure.launchFailed(reason: "could not allocate posix_spawn file actions")
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // stdout is unused — rsvg-convert writes the PDF to its -o path.
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, stderrPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        defer { argv.forEach { free($0) } }

        var envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &fileActions, nil, argv, envp)
        guard result == 0 else {
            throw Failure.launchFailed(
                reason: "posix_spawn(\(executable)) failed: \(String(cString: strerror(result)))"
            )
        }
        return pid
    }

    // MARK: - Waiting

    /// Reaps `pid` if it finishes before `deadline`, returning how it ended.
    /// Returns `nil` if the deadline passes while the child is still running.
    private static func reap(pid: pid_t, before deadline: Date) throws -> Outcome? {
        var pollInterval: useconds_t = 1_000    // 1 ms, backing off to 25 ms

        while true {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)

            if result == pid {
                return outcome(from: status)
            }
            if result == -1 {
                if errno == EINTR { continue }
                // ECHILD means the child is gone but someone else reaped it, so
                // there is no status left to read — still, it is not running.
                if errno == ECHILD { return .statusUnavailable }
                throw Failure.launchFailed(reason: "waitpid failed: \(String(cString: strerror(errno)))")
            }

            guard Date() < deadline else { return nil }
            usleep(pollInterval)
            pollInterval = min(pollInterval * 2, 25_000)
        }
    }

    /// `WIFEXITED` / `WEXITSTATUS` / `WTERMSIG` are C macros, so they are not
    /// imported into Swift; this decodes a wait status by hand.
    private static func outcome(from status: Int32) -> Outcome {
        if status & 0x7f == 0 {
            return .exited(code: (status >> 8) & 0xff)
        }
        return .signalled(signal: status & 0x7f)
    }
}

#endif
