# swift-injection-peer

The channel between an injected payload and the host tool that injected it, over whichever transport
that particular target allows — plus the endpoint registry a long-lived app needs to find its
payload again after a restart.

Extracted from [swift-helper-service](https://github.com/Mx-Iris/swift-helper-service), where it
used to live as `HelperPeer`. Module and API names are unchanged: switching to this package is a
change to one dependency declaration, not to your code.

## Which transport you get

Two, and the roles are **inverted** between them. You do not choose — `PeerTransportSelection`
probes the target and both sides compute the same answer, because in the case where they would need
to negotiate, the hop they would negotiate over is the one that is blocked.

| | Who listens | Who dials | When |
|---|---|---|---|
| **Brokered XPC** | the payload | the host | the target can look up your Mach service |
| **Loopback socket** | the host | the payload | the target's sandbox denies that lookup |

The inversion is forced, not stylistic. A sandboxed process may open an outbound connection to
localhost, but nothing can discover a port it bound: the two sides share no channel to announce it
on — not the tool (that is the hop the sandbox blocked) and not the file system (a sandboxed app and
its host have no directory in common). Having the host listen turns "announce a port" into "agree on
one".

**Reconnection works on the XPC path only.** It works there because the payload's listener outlives
the host app; on the socket path the host is the listener, so a host that restarts leaves its payload
holding a dead connection with no way to be told about the new one. Callers that try anyway get
`PeerLink.Failure.reconnectionNeedsXPC` rather than a link that silently never connects.

## Why the port is derived and not allocated

`PeerPortDerivation` hashes the channel identifier with **djb2**. Binding port 0 and letting the
kernel choose is the better answer everywhere it is available, and it is not available here: the
side that would bind is the sandboxed payload, and it has no way to tell the host what it got.

djb2 specifically, and **never `Hasher`**: `Hasher` is seeded per process, so the two sides would
compute different ports — and that class of bug only ever shows up across a process boundary, which
is exactly where it is hardest to see. djb2 is also trivial to reimplement identically in another
language, which matters more here than distribution quality.

The identifier **must include the target pid**. Two payloads in two processes derived from one
identifier would collide on a single port, and the second listener would fail to bind. Collisions
with unrelated software are possible and not preventable from here — the dynamic range is shared
with every ephemeral socket on the machine. The listening side detects a failed bind and reports it;
it does not silently try another port, because the other side would have no way to follow.

## Where to mount the endpoint registry

`InjectedEndpointRegistryService` remembers where each injected payload can be reached. Mount it on
**your own daemon**:

```swift
let server = try await HelperServer(
    serverType: .machService(name: MyToolMachServiceName),
    version: MyToolServiceVersion,
    services: [
        InjectionService(),
        InjectedEndpointRegistryService(),
    ]
)
```

The shared injection platform deliberately does **not** mount it, and the reason is worth knowing
before you copy its choice:

`xpc_connection_set_peer_code_signing_requirement` checks the **connecting process**. A payload is a
`dlopen`ed image with no process identity of its own, so what actually gets checked is the
**injected application** — Dock, Finder, somebody else's app. None of them carry your Team ID, so a
daemon that sets a requirement can never accept a check-in from a payload. A daemon shared across
tools has to set one (it injects code into arbitrary processes; accepting requests from anyone makes
it a local privilege-escalation primitive), so it cannot host this registry. **A daemon that serves
only its own app can leave the requirement off and has no such problem** — which is why this is
normal, working infrastructure for a tool with its own daemon, and why it was moved out of the
shared platform rather than deleted.

If you have no daemon of your own — a CLI using the shared platform, say — use the socket transport
and skip the registry: the host is the listener there, so there is no endpoint to publish.

## Two-phase lifecycle

Construction wires nothing up on the wire. **Install every handler, then call `activate()`.**

```swift
let link = try await PeerLink.host(
    machServiceName: MyToolMachServiceName,
    isPrivilegedHelperTool: true,
    targetProcessIdentifier: targetPID
)
link.channel.setMessageHandler(SomeRequest.self) { request in try await handle(request) }
try await link.channel.activate()
```

Folding the two together races the far side against handler registration: over XPC the peer is told
to connect before the handlers exist, and over a socket the payload's first frame can arrive before
the registry has anything in it. Both lose the message the same way — the far side gets "no handler
is registered", which reads like a programming error rather than a race.

The host's link must be **open and activated before the injection**. On the XPC path the payload
looks the host up as it starts; on the socket path it dials immediately, and a listener that is not
up yet means connection refused with nothing to retry against.

## Requirements

macOS 10.15+ / macCatalyst 13+, Swift 6.2. Depends on `HelperCommunication` and `HelperService` from
swift-helper-service for the `Request` protocol and the mountable-service shape. The arrow points
that way and only that way — swift-helper-service does not depend on this package, so a consumer
depending on both is not a cycle.
