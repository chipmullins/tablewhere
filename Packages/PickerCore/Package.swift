// swift-tools-version: 5.9
import PackageDescription

// PickerCore holds the logic shared by the ForkRoad app and (in Phase 2)
// its iMessage extension: the Place model, cuisine filters, and the randomizer.
// It has no UI and no network code, so it is fast to unit test.
let package = Package(
    name: "PickerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PickerCore", targets: ["PickerCore"])
    ],
    targets: [
        .target(name: "PickerCore"),
        .testTarget(name: "PickerCoreTests", dependencies: ["PickerCore"])
    ]
)
