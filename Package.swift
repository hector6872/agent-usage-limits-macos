// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentUsageLimits",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AgentUsageLimits",
            targets: ["AgentUsageLimits"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "AgentUsageLimits",
            path: "Sources/AgentUsageLimits"
        ),
    ]
)
