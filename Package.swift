// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyStat",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "MyStatCore"),
        .executableTarget(
            name: "MyStat",
            dependencies: ["MyStatCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MyStat",
            exclude: ["Info.plist"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MyStatCoreTests", dependencies: ["MyStatCore"])
    ]
)
