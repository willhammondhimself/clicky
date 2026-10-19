// swift-tools-version: 6.2
//
// Terminal test harness for Lumen's pure-logic files. The app itself can
// only be built from Xcode (running xcodebuild from the terminal resets the
// app's TCC permissions), so files with no AppKit/FluidAudio dependency are
// symlinked into this package and tested with `swift test`.
//
// Settings mirror the Xcode targets exactly: the app target compiles with
// Swift 5 language mode and main-actor default isolation; the unit-test
// target (leanring-buddyTests) has Swift 5 language mode but NO default
// isolation. Keeping that asymmetry here means a test that would fail to
// compile under Cmd+U also fails here.

import PackageDescription

let mirroredAppTargetSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
]

let mirroredTestTargetSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
]

let package = Package(
    name: "LumenLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LumenLogic",
            swiftSettings: mirroredAppTargetSettings
        ),
        .testTarget(
            name: "LumenLogicTests",
            dependencies: ["LumenLogic"],
            swiftSettings: mirroredTestTargetSettings
        ),
    ]
)
