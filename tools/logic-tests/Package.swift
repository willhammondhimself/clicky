// swift-tools-version: 6.2
//
// Terminal test harness for Clicky's pure-logic files. The app itself can
// only be built from Xcode (running xcodebuild from the terminal resets the
// app's TCC permissions), so files with no AppKit/FluidAudio dependency are
// symlinked into this package and tested with `swift test`.
//
// Settings mirror the app target: Swift 5 language mode with main-actor
// default isolation, so code that compiles here compiles in the app.

import PackageDescription

let mirroredAppTargetSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "ClickyLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClickyLogic",
            swiftSettings: mirroredAppTargetSettings
        ),
        .testTarget(
            name: "ClickyLogicTests",
            dependencies: ["ClickyLogic"],
            swiftSettings: mirroredAppTargetSettings
        ),
    ]
)
