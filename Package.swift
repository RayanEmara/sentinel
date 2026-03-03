// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sentinel",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.1"),
    ],
    targets: [
        .executableTarget(
            name: "Sentinel",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftMath", package: "SwiftMath"),
            ],
            path: "Sources/Sentinel",
            exclude: ["Sentinel.entitlements"]
        ),
    ]
)
