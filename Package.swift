// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fling",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Fling",
            path: "Fling",
            exclude: [
                "Info.plist",
                "Fling.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
