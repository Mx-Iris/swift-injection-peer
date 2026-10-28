// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// No `local:` / `remote:` dependency switch here, unlike swift-helper-service. That helper picks a
// local checkout only when `USING_LOCAL_DEPENDENCIES` is set and falls back to a published version
// otherwise — and this package has no version to fall back to: it can only resolve against a
// swift-helper-service that has already moved these targets out, which exists on one branch and in
// no release. A conditional switch here silently resolved to a non-existent version for any
// consumer that did not set the variable, which is how `RunScript.sh` failed. Reintroduce the
// helper when this package and that branch are both released.


let package = Package(
    name: "swift-injection-peer",
    platforms: [.macOS(.v10_15), .macCatalyst(.v13)],
    products: [
        .library(
            name: "HelperPeer",
            targets: ["HelperPeer"],
        ),
        .library(
            name: "InjectedEndpointRegistryService",
            targets: ["InjectedEndpointRegistryServiceInterface", "InjectedEndpointRegistryServiceImplementation"],
        ),
        .library(
            name: "InjectedEndpointRegistryServiceInterface",
            targets: ["InjectedEndpointRegistryServiceInterface"],
        ),
        .library(
            name: "InjectedEndpointRegistryServiceImplementation",
            targets: ["InjectedEndpointRegistryServiceImplementation"],
        ),
    ],
    dependencies: [
        // For `HelperCommunication` (the `Request` protocol and its serialization) and
        // `HelperService` (what a mountable service looks like). Kept rather than reinvented:
        // every consumer of this library already depends on swift-helper-service, so the
        // dependency costs them nothing and their request types need no adapting.
        //
        // The arrow points this way and only this way. A consumer depends on both, which is not
        // a cycle; swift-helper-service must never depend on this library.
        //
        // An unconditional path, not a local/remote pair, and **not** gated on
        // `USING_LOCAL_DEPENDENCIES`: there is nothing to fall back to yet. This package can only
        // resolve against a swift-helper-service that has *already* moved these targets out,
        // because SPM requires target names to be unique across the whole package graph — for as
        // long as that library still declares `HelperPeer`, resolving both is an error. That is
        // now true of its `main`, which is what this points at; the version a `remote:` would name
        // still does not exist. Making it conditional meant a consumer that did not happen to set
        // that variable resolved to the non-existent version instead, which is how
        // `RunScript.sh` failed.
        //
        // **Switch to a version requirement once swift-helper-service ships a release** — that is
        // also what makes this package usable from its own GitHub remote by anyone else.
        .package(
            path: "/Volumes/Repositories/Private/Personal/Library/macOS/swift-helper-service"
        ),
        .package(
            url: "https://github.com/MxIris-macOS-Library-Forks/SwiftyXPC",
            from: "0.5.104",
        ),
        .package(
            url: "https://github.com/Mx-Iris/FrameworkToolbox",
            from: "0.9.0",
        ),
    ],
    targets: [
        // The channel between a host and the payload injected into it, over whichever transport
        // that particular target allows. Module name deliberately unchanged from when this lived
        // in swift-helper-service: consumers switch which package they take it from and nothing
        // else.
        .target(
            name: "HelperPeer",
            dependencies: [
                "PeerProcessProbe",
                .product(name: "HelperCommunication", package: "swift-helper-service"),
                .product(name: "HelperService", package: "swift-helper-service"),
                .product(name: "SwiftyXPC", package: "SwiftyXPC"),
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            ],
        ),

        // The mach-lookup probe that decides whether a payload can reach the tool over XPC at
        // all, or has to fall back to a loopback socket. See the header for why it is C and why
        // it is not called HelperProcessProbe.
        .target(
            name: "PeerProcessProbe",
        ),

        // Remembers where each injected payload can be reached, so a host that restarted can
        // find its payload again. Mount it on your *own* daemon: the shared injection platform
        // deliberately does not, because its code-signing requirement cannot admit the identity
        // of an arbitrary injected process. A daemon that serves only its own app sets its own
        // requirement and has no such problem.
        .target(
            name: "InjectedEndpointRegistryServiceInterface",
            dependencies: [
                .product(name: "HelperCommunication", package: "swift-helper-service"),
            ],
            path: "Sources/InjectedEndpointRegistryService/Interface",
        ),
        .target(
            name: "InjectedEndpointRegistryServiceImplementation",
            dependencies: [
                "InjectedEndpointRegistryServiceInterface",
                .product(name: "HelperCommunication", package: "swift-helper-service"),
                .product(name: "HelperService", package: "swift-helper-service"),
            ],
            path: "Sources/InjectedEndpointRegistryService/Implementation",
        ),

        .testTarget(
            name: "HelperPeerTests",
            dependencies: ["HelperPeer"],
        ),
    ],
)
