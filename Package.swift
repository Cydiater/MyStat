// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyStat",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "MyStat",
            path: "Sources/MyStat",
            exclude: ["Info.plist"]
        )
    ]
)
