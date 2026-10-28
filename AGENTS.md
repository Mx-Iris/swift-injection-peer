# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a symlink to this file — edit
`AGENTS.md`, not the symlink.

## Purpose

`swift-injection-peer` provides the channel between an injected payload and the host tool that
injected it, plus the endpoint registry a long-lived host needs to find its payload again after a
restart. It was extracted from `swift-helper-service`, where it lived as `HelperPeer`.

**Module and API names are deliberately unchanged from before the extraction.** Consumers migrate by
editing one `package:` in their dependency declaration. Do not rename `HelperPeer`,
`InjectedEndpointRegistryService*`, or anything they export without a proposal that accounts for all
four consumers (RuntimeViewer, InjectionScaffold's template, InjectionPlatform, ViewHierarchyCapture).

## Build & Test

- Build: `swift build 2>&1 | xcsift`
- Tests: **`swift test` — judge by the exit code, never by `xcsift`'s summary.** xcsift's own exit
  code is always 0, and versions up to 1.0.21 report failed swift-testing tests as passing. Use
  `${PIPESTATUS[0]}` (zsh: `${pipestatus[1]}`), or redirect raw output to a file and check the code
  before feeding it to xcsift. Piping through xcsift stays useful for *build* diagnostics.
- `USING_LOCAL_DEPENDENCIES=1` resolves `swift-helper-service` from the sibling checkout instead of
  GitHub. **`FrameworkToolbox` and `SwiftyXPC` have no local candidate on purpose** — they are shared
  with swift-helper-service, and a root package resolving one of them to a path while a checked-out
  dependency resolves it to a URL is the same identity from two source locations, which SPM rejects.
- Swift toolchain 6.2; platforms macOS 10.15+ / macCatalyst 13+. Nearly every source file is wrapped
  in `#if os(macOS) || targetEnvironment(macCatalyst)`; the registry service uses a bare
  `#if os(macOS)` to exclude macCatalyst.

## Architecture

Two transports, and **the roles invert between them**:

| | Listens | Dials | Chosen when |
|---|---|---|---|
| `.brokeredXPC` | payload | host | the target can look up the tool's Mach service |
| `.loopbackSocket` | host | payload | the target's sandbox denies that lookup |

`PeerTransportSelection.transport(forProcess:machServiceName:channelIdentifier:)` is the only place
that decides. **Both sides call it and must agree** — the host about its target's pid before
injecting, the payload about `getpid()` once inside. A host that picks XPC while its payload picks a
socket does not fail, it hangs. There is no negotiation because in the case where they would need to
negotiate, the hop they would negotiate over is the blocked one.

`PeerLink` is the entry point: `host(...)` before injecting, `payload(...)` from inside the target,
`hostReconnecting(...)` for a payload that is already resident (**XPC only** — it throws
`Failure.reconnectionNeedsXPC` otherwise). `PeerMessaging` is the transport-agnostic protocol both
channel types conform to; `PeerConnection` describes only the XPC topology.

### Load-bearing details that look like style

- **Two-phase lifecycle.** Construction wires nothing up. Install handlers, *then* `activate()`.
  Collapsing them races the far side against handler registration, and the far side's error ("no
  handler is registered") reads like a programming error rather than a race.
- **The host's link must be open and activated before the injection.** On the XPC path the payload
  looks the host up as it starts; on the socket path it dials immediately.
- **`PeerPortDerivation` uses djb2, never `Hasher`.** `Hasher` is seeded per process, so the two
  sides would derive different ports — a bug that only shows up across a process boundary.
- **The channel identifier must include the target pid.** Two payloads derived from one identifier
  collide on one port and the second listener fails to bind.
- **A failed bind is reported, not retried on another port.** The other side has no way to follow.
- **`sandbox_check` lives in C** (`PeerProcessProbe`) because it is variadic, and the arm64 variadic
  ABI passes arguments on the stack — not expressible through Swift's `@convention(c)`.
- **A probe error answers "not blocked"**, keeping the XPC default: that path reports its own
  failures clearly, whereas wrongly choosing the socket leaves both sides waiting on a connection
  neither is making. `PeerTransportSelection` also checks the process exists first, because
  `sandbox_check` answers "denied" for a pid the kernel cannot find.

## Where the endpoint registry belongs

Mount `InjectedEndpointRegistryService` on **your own daemon**. The shared injection platform does
not mount it, and the reason constrains any change here:

`xpc_connection_set_peer_code_signing_requirement` checks the **connecting process**. A payload is a
`dlopen`ed image with no process identity, so what gets checked is the **injected application** —
which never carries your Team ID. A daemon shared across tools must set a requirement (it injects
into arbitrary processes; accepting anyone makes it a privilege-escalation primitive), so it cannot
host this registry. A daemon serving only its own app can leave the requirement off and has no such
problem.

**So "the shared platform does not do this" is not a verdict that the registry is wrong.** It is
normal infrastructure for a tool with its own daemon. See
`swift-helper-service`'s proposal *共享 daemon 只管注入，回传通道移到独立库* for the full argument.

## Test coverage

`HelperPeerTests` covers `PeerSocketFraming`, `PeerSocketChannel`, `PeerMessaging` and
`PeerTransport`. **The XPC handshake has no tests** — it needs two processes. Do not read a green run
as a verified system; the socket path is what is actually exercised.
