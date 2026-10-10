// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SafeShare",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SafeShareKit", targets: ["SafeShareKit"]),
        .executable(name: "SafeShare", targets: ["SafeShare"]),
        .executable(name: "FeasibilityPoC", targets: ["FeasibilityPoC"])
    ],
    targets: [
        .target(
            name: "SafeShareKit",
            path: "Sources/SafeShareKit"
        ),
        .executableTarget(
            name: "SafeShare",
            dependencies: ["SafeShareKit"],
            path: "Sources/SafeShare"
        ),
        .executableTarget(
            name: "FeasibilityPoC",
            dependencies: ["SafeShareKit"],
            path: "Sources/FeasibilityPoC"
        ),
        .testTarget(
            name: "SafeShareTests",
            dependencies: ["SafeShareKit"],
            path: "Tests/UnitTests"
        )
    ]
)
