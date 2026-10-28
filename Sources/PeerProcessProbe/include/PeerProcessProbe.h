//
//  PeerProcessProbe.h
//  swift-injection-peer
//
//  A thin C wrapper over the one piece of kernel SPI the transport choice needs.
//
//  Split out of swift-helper-service's `HelperProcessProbe`, which carried three
//  probes with no overlap in their callers: the path check and the code-signing
//  status word gate the *injection* path and stayed behind with the injection
//  service, while this one answers "can a payload in that process reach the
//  daemon over XPC at all", which is a question about the *channel*.
//
//  Renamed rather than carried over under the old name so both libraries can be
//  linked into one process: two targets of the same name collide as modules, and
//  two C functions of the same name collide as symbols.
//

#ifndef PeerProcessProbe_h
#define PeerProcessProbe_h

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

/// Asks `pid`'s sandbox whether it would permit looking up the Mach service
/// `globalName` — the question that decides whether an injected payload can
/// reach the daemon over XPC at all.
///
/// Two unrelated sandbox flavours answer "no", which is why this probes rather
/// than sniffing entitlements: App Sandbox apps run a `(deny default)` profile
/// whose `mach-lookup` allowlist will not contain a third-party service, and
/// seatbelt-profiled system daemons are equally closed while carrying no
/// `com.apple.security.app-sandbox` entitlement to notice.
///
/// Lives in C because `sandbox_check` is variadic: the arm64 variadic ABI passes
/// variadic arguments on the stack, which cannot be expressed through Swift's
/// `@convention(c)` function pointers, so the call must be emitted by the C
/// compiler.
///
/// Returns `0` when permitted (including for an unsandboxed process), a positive
/// value when the sandbox denies it, and `-1` on error. Callable for any pid,
/// including `getpid()`, so a host and the payload inside its target reach the
/// same conclusion about that target. Note that a pid the kernel cannot find
/// answers "denied" rather than reporting an error.
int PeerProcessProbeSandboxCheckMachLookup(pid_t pid, const char *globalName);

#endif /* PeerProcessProbe_h */
