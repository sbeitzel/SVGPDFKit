import XCTest
@testable import SVGPDFKit

// The subprocess runner only exists on platforms that render without CoreGraphics.
#if !canImport(CoreGraphics)

final class RsvgSubprocessTests: XCTestCase {

    private var stderrPath: String!

    override func setUp() {
        super.setUp()
        stderrPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).stderr").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: stderrPath)
        super.tearDown()
    }

    private var capturedStderr: Data {
        FileManager.default.contents(atPath: stderrPath) ?? Data()
    }

    func testReportsExitStatusOfAChildThatSucceeds() throws {
        let outcome = try RsvgSubprocess.run(
            executable: "/bin/sh",
            arguments: ["-c", "exit 0"],
            stderrPath: stderrPath,
            timeout: 10
        )

        guard case .exited(let code) = outcome else {
            return XCTFail("expected a normal exit, got \(outcome)")
        }
        XCTAssertEqual(code, 0)
    }

    func testReportsExitStatusOfAChildThatFails() throws {
        let outcome = try RsvgSubprocess.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo 'it went wrong' >&2; exit 3"],
            stderrPath: stderrPath,
            timeout: 10
        )

        guard case .exited(let code) = outcome else {
            return XCTFail("expected a normal exit, got \(outcome)")
        }
        XCTAssertEqual(code, 3)
        XCTAssertEqual(String(decoding: capturedStderr, as: UTF8.self), "it went wrong\n")
    }

    func testReportsTheSignalThatKilledTheChild() throws {
        let outcome = try RsvgSubprocess.run(
            executable: "/bin/sh",
            arguments: ["-c", "kill -TERM $$"],
            stderrPath: stderrPath,
            timeout: 10
        )

        guard case .signalled(let signal) = outcome else {
            return XCTFail("expected a signalled exit, got \(outcome)")
        }
        XCTAssertEqual(signal, SIGTERM)
    }

    /// The regression this guards: with the child's stderr on an undrained `Pipe`,
    /// a child that writes more than the pipe buffer (~64 KB) blocks in `write()`
    /// while the parent blocks waiting for it to exit, and neither ever finishes.
    func testChildWritingMoreThanAPipeBufferToStderrDoesNotDeadlock() throws {
        let byteCount = 1_000_000
        let outcome = try RsvgSubprocess.run(
            executable: "/bin/sh",
            arguments: ["-c", "head -c \(byteCount) /dev/zero | tr '\\0' 'x' >&2"],
            stderrPath: stderrPath,
            timeout: 20
        )

        guard case .exited(let code) = outcome else {
            return XCTFail("expected a normal exit, got \(outcome)")
        }
        XCTAssertEqual(code, 0)
        XCTAssertEqual(capturedStderr.count, byteCount)
    }

    /// A child that never finishes must fail the caller rather than hang it.
    func testAChildThatOutlivesTheTimeoutIsKilled() {
        let start = Date()

        XCTAssertThrowsError(
            try RsvgSubprocess.run(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 60"],
                stderrPath: stderrPath,
                timeout: 1
            )
        ) { error in
            XCTAssertEqual(error as? RsvgSubprocess.Failure, .timedOut)
        }

        // 1s timeout, then at most two 2s grace periods for SIGTERM and SIGKILL.
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
}

extension RsvgSubprocess.Failure: Equatable {
    public static func == (lhs: RsvgSubprocess.Failure, rhs: RsvgSubprocess.Failure) -> Bool {
        switch (lhs, rhs) {
        case (.timedOut, .timedOut): return true
        case (.launchFailed(let lhs), .launchFailed(let rhs)): return lhs == rhs
        default: return false
        }
    }
}

#endif
