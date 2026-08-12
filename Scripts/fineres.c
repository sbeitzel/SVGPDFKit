// fineres.c — workaround for hanging Foundation RunLoop deadlines on Linux
// containers running under Docker Desktop for Mac.
//
// WHY
//
// swift-corelibs-foundation derives CoreFoundation's timebase from the reported
// resolution of CLOCK_MONOTONIC:
//
//     __CFTSRRate = res.tv_sec + (1000000000 * res.tv_nsec);   // CFDate.c
//
// That yields the correct 1e9 only when the kernel reports a 1 ns resolution.
// Docker Desktop's VM kernel reports 1 ms, which makes the rate 1e15 and throws
// off every conversion CoreFoundation does between its timebase and real time.
// The practical result is that CFRunLoop's run deadline is never enforced:
// the dispatch timer meant to end a bounded run is scheduled at a moment in the
// past, so it fires immediately and — being one-shot — never fires again, while
// the loop itself sleeps in an untimed ppoll(). RunLoop.run(mode:before:) then
// blocks forever instead of returning at its limit date.
//
// Anything built on that deadline inherits the hang: Process.waitUntilExit(),
// XCTest's expectation waits (including the teardown sequence, which stalls
// unpredictably at the end of a test), Timer-driven waits, RunLoop.run(until:).
//
// This is a known corelibs bug, fixed on main but not in any released toolchain:
//     https://github.com/swiftlang/swift-corelibs-foundation/pull/5485
// Once a toolchain ships that fix, this file can be deleted.
//
// SVGPDFKit's own conversion path does not depend on it — RsvgSubprocess waits
// with waitpid(2), never a RunLoop — but `swift test` in an affected container
// still hangs in XCTest's teardown, which this restores to working order.
//
// USAGE
//
//     clang -shared -fPIC -o /tmp/fineres.so Scripts/fineres.c
//     LD_PRELOAD=/tmp/fineres.so swift test
//
// Only processes launched with LD_PRELOAD are affected, and only their view of
// the clock's advertised *resolution* changes — no clock value is altered.

#define _GNU_SOURCE
#include <time.h>

// Reports the 1 ns resolution a non-virtualised Linux kernel reports, which is
// the value CFDate.c's timebase calculation assumes.
int clock_getres(clockid_t clk_id, struct timespec *res) {
    (void)clk_id;
    if (res) {
        res->tv_sec = 0;
        res->tv_nsec = 1;
    }
    return 0;
}
