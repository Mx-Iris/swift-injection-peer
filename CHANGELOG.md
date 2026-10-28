# Changelog

All notable changes to this package are documented here. Versions follow
[Semantic Versioning](https://semver.org); while the package is pre-1.0, a minor bump may carry
source-breaking changes.

## [0.1.0] — 2026-10-28

First release. `HelperPeer` and `InjectedEndpointRegistryService` were extracted from
[`swift-helper-service`](https://github.com/Mx-Iris/swift-helper-service), whose 0.4.0 removed them
in the same release. Neither needs root, and a *shared* injection daemon could not broker that
channel in any case: the code signing requirement such a listener must carry checks the
**connecting process**, and a payload is a `dlopen`ed image with no process identity of its own, so
what actually gets checked is whichever third-party app was injected. A tool with its own daemon can
leave the requirement off and mount the registry there; a shared one cannot.

The API moved unchanged — a downstream switching over changes its import and nothing else.

**Requires swift-helper-service 0.4.0 or later.** Anything earlier still declares `HelperPeer`
itself, and SPM requires target names to be unique across the whole package graph, so resolving both
at once fails outright.

### Added

The entries below were written while this code still lived in swift-helper-service and were never
part of any release of it — it gained and lost them inside one unreleased window. They are reproduced
here because they are where the reasoning lives; references to "the tool" mean the daemon a payload
was injected from.

- **A loopback socket transport for peers that cannot use XPC** (`PeerSocketChannel`,
  `PeerTransportSelection`, `PeerPortDerivation`).

  The brokered XPC handshake needs both sides to look up the tool's Mach service, and a
  sandboxed target cannot: App Sandbox runs a `(deny default)` profile whose `mach-lookup`
  allowlist will not contain a third-party service, and seatbelt-profiled system daemons are
  closed the same way without carrying an entitlement that would reveal it.

  On the socket path **the roles invert — the host listens and the payload connects out.** A
  sandboxed process can dial localhost, but nothing can discover a port it bound: the tool is
  the blocked hop and a sandboxed app shares no directory with its host. Both sides therefore
  derive the same port from one identifier instead of announcing it.

  `PeerPortDerivation` uses djb2, **not `Hasher`** — `Hasher` is seeded per process, so the two
  sides would derive different ports and wait on each other, a failure that only appears across
  a process boundary.

  Selection is a probe (`sandbox_check`), not entitlement sniffing, because the two sandbox
  flavours that block this do not look alike. Callers use
  `PeerTransportSelection.transport(forProcess:machServiceName:channelIdentifier:)`; the host
  asks about its target before injecting, the payload asks about `getpid()` afterwards, and they
  reach the same answer without negotiating.

  Not covered: a real sandboxed target. Nothing here performs an injection, so that conclusion
  rests on `sandbox_check`'s semantics and on RuntimeViewer's production experience.

- **`PeerMessaging` and `PeerLink` — one surface over both transports.**

  `PeerMessaging` is the four things every transport can do: send a typed request, answer one,
  watch the state, cancel. `PeerConnection` now refines it and keeps the two members that are
  specific to XPC — the publishable listener endpoint and the untyped name-keyed RPC.
  `PeerSocketChannel` conforms, so code holding `any PeerMessaging` works on either path.

  Making `PeerSocketChannel` conform to `PeerConnection` instead was the obvious move and the
  wrong one: `listenerEndpoint` has no socket meaning — deriving the port is what the two sides
  do *because* they have no channel on which to exchange an address — so conformance would be a
  set of methods whose only behaviour is to throw.

  `PeerLink.host(...)` / `PeerLink.payload(...)` probe, choose the transport, and construct the
  matching end in one step, returning the link together with the `PeerTransport` that was
  chosen. Both sides must compute the same answer, and keeping that computation in one place is
  what stops them drifting: a host on XPC with its payload on a socket does not fail, it hangs.
  The payload factory deliberately takes no pid — the payload is the target, so it asks
  `getpid()`.

  `PeerLink.hostReconnecting(...)` throws for a sandboxed target rather than returning a link
  that never connects. Reconnecting works over XPC because the payload's listener outlives the
  host app; on the socket path the host is the listener, so a restarted host leaves its payload
  holding a dead connection with no way to be told about the new one.

  `HelperService`s mount on a socket link too (`PeerSocketHelperHandler`). Without that, a
  service written once would work on unsandboxed targets and silently do nothing on sandboxed
  ones.

- **`PeerSocketChannel` has the same two-phase lifecycle as the XPC peers.**
  `preparedListener(onPort:)` / `preparedDialer(toPort:)` construct without touching the wire;
  `activate()` starts it. Install handlers in between — the payload's first frame can arrive
  before the handler registry has anything in it, and the far side is then told no handler
  exists, which reads like a programming error rather than a race.

  `listen(onPort:)` and `connect(toPort:)` remain as the both-phases convenience.

  The order between the two ends is fixed: **host first, then payload.** The dialer needs
  something to dial; in production that reads as "open the host link before injecting".
