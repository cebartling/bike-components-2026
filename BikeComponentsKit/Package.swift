// swift-tools-version: 6.2
import PackageDescription

// ADR-0005: every target enables the same upcoming features, in Swift 6 mode.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

// ADR-0005: BikeComponentsUI and its tests are main-actor by default.
let mainActorSwiftSettings = swiftSettings + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "BikeComponentsKit",
    // ADR-0002: the latest iOS release only, written as a string for the point release.
    platforms: [.iOS("27.2")],
    products: [
        // ADR-0004: the one product the app links; it lists every library target.
        .library(name: "BikeComponentsKit", targets: ["BikeComponentsCore", "BikeComponentsUI"]),
    ],
    targets: [
        .target(name: "BikeComponentsCore", swiftSettings: swiftSettings),
        .target(
            name: "BikeComponentsUI",
            dependencies: ["BikeComponentsCore"],
            swiftSettings: mainActorSwiftSettings,
        ),
        .testTarget(
            name: "BikeComponentsCoreTests",
            dependencies: ["BikeComponentsCore"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "BikeComponentsUITests",
            dependencies: ["BikeComponentsUI"],
            swiftSettings: mainActorSwiftSettings,
        ),
    ],
)
