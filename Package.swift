// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    let value = Context.environment[key]
    guard let value else {
        return defaultValue
    }
    if value == "1" {
        return true
    } else if value == "0" {
        return false
    } else {
        return defaultValue
    }
}

let usingLocalDependencies = envEnable("USING_LOCAL_DEPENDENCIES")

extension Package.Dependency {
    enum LocalSearchPath {
        /// - Parameter name: Pass this when the directory's basename is not the package name.
        ///   SwiftPM derives a path dependency's identity from the basename, so a checkout under
        ///   `.worktrees/<project>-<suffix>/` resolves to that directory name and every
        ///   `package:` reference spelled with the real package name fails. Carried over from
        ///   ViewHierarchyCapture, which hit exactly this.
        case package(path: String, isRelative: Bool, isEnabled: Bool = usingLocalDependencies, name: String? = nil, traits: Set<PackageDescription.Package.Dependency.Trait> = [.defaults])
    }

    static func package(local localSearchPaths: LocalSearchPath..., remote: Package.Dependency) -> Package.Dependency {
        let currentFilePath = #filePath
        let isClonedDependency = currentFilePath.contains("/checkouts/") ||
            currentFilePath.contains("/SourcePackages/") ||
            currentFilePath.contains("/.build/")

        if isClonedDependency {
            return remote
        }
        for local in localSearchPaths {
            switch local {
            case .package(let path, let isRelative, let isEnabled, let name, let traits):
                guard isEnabled else { continue }
                let url = if isRelative {
                    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: #filePath))
                } else {
                    URL(fileURLWithPath: path)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    if let name {
                        return .package(name: name, path: url.path)
                    }
                    return .package(path: url.path, traits: traits)
                }
            }
        }
        return remote
    }
}

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
        // Pointed at the `feature/shared-injection-daemon` worktree, not the main checkout: this
        // package can only resolve against a swift-helper-service that has *already* moved these
        // targets out. SPM requires target names to be unique across the whole package graph, so
        // for as long as that library still declares `HelperPeer`, resolving both is an error.
        // **Switch to a version requirement once that branch lands and ships.**
        .package(
            local: .package(
                path: "/Volumes/Repositories/Private/Personal/Library/macOS/swift-helper-service/.worktrees/swift-helper-service-SharedInjectionDaemon",
                isRelative: false,
                name: "swift-helper-service",
            ),
            remote: .package(
                url: "https://github.com/Mx-Iris/swift-helper-service",
                from: "0.4.0",
            ),
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
