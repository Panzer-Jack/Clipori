// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipori",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CliporiCore", targets: ["CliporiCore"]),
        .executable(name: "Clipori", targets: ["CliporiMac"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "CliporiCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CliporiMac", dependencies: ["CliporiCore"]),
        .testTarget(name: "CliporiCoreTests", dependencies: ["CliporiCore"]),
        .testTarget(name: "CliporiMacTests", dependencies: ["CliporiMac"])
    ],
    swiftLanguageModes: [.v5]
)
