// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
        // RevenueCat (audit M1, 2026-10-02). A dependency of Core, not only of the app target,
        // because `Monetization/RevenueCatManager.swift` is the one file that talks to the SDK and
        // its `#if canImport(RevenueCat)` blocks only compile in when *this* package can see the
        // module. Same URL and lower bound as project.yml's `packages: RevenueCat` entry so Xcode
        // resolves a single copy. Every Core consumer (the shield/monitor/widget extensions too)
        // links it; the extensions never call it. Key handling: see RevenueCatManager.configure.
        .package(url: "https://github.com/RevenueCat/purchases-ios", from: "5.92.0")
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios")
            ],
            path: "Sources/Core"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        )
    ]
)
