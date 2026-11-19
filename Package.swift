// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenPaste",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OpenPaste"),
        .testTarget(name: "OpenPasteTests", dependencies: ["OpenPaste"]),
    ],
    swiftLanguageModes: [.v5]
)
