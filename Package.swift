// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WWMD",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "WWMDCore", targets: ["WWMDCore"]),
        .library(name: "WWMDStorage", targets: ["WWMDStorage"]),
        .library(name: "WWMDAnalytics", targets: ["WWMDAnalytics"]),
        .library(name: "WWMDAdapters", targets: ["WWMDAdapters"]),
        .library(name: "WWMDIPC", targets: ["WWMDIPC"]),
        .library(name: "WWMDAgentRuntime", targets: ["WWMDAgentRuntime"]),
        .executable(name: "wwmdd", targets: ["wwmdd"]),
        .executable(name: "wwmd", targets: ["wwmd"]),
        .executable(name: "WWMDApp", targets: ["WWMDApp"])
    ],
    targets: [
        .target(name: "WWMDCore"),
        .target(
            name: "WWMDStorage",
            dependencies: ["WWMDCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "WWMDAnalytics", dependencies: ["WWMDCore"]),
        .target(name: "WWMDAdapters", dependencies: ["WWMDCore"]),
        .target(name: "WWMDIPC", dependencies: ["WWMDCore"]),
        .target(
            name: "WWMDAgentRuntime",
            dependencies: ["WWMDCore", "WWMDStorage", "WWMDAnalytics", "WWMDAdapters", "WWMDIPC"]
        ),
        .executableTarget(
            name: "wwmdd",
            dependencies: ["WWMDAgentRuntime"]
        ),
        .executableTarget(
            name: "wwmd",
            dependencies: ["WWMDIPC"]
        ),
        .executableTarget(
            name: "WWMDApp",
            dependencies: ["WWMDCore", "WWMDStorage", "WWMDIPC", "WWMDAgentRuntime"]
        ),
        .testTarget(name: "WWMDCoreTests", dependencies: ["WWMDCore"]),
        .testTarget(name: "WWMDStorageTests", dependencies: ["WWMDCore", "WWMDStorage"]),
        .testTarget(name: "WWMDAnalyticsTests", dependencies: ["WWMDCore", "WWMDAnalytics"]),
        .testTarget(name: "WWMDAdaptersTests", dependencies: ["WWMDCore", "WWMDAdapters"]),
        .testTarget(name: "WWMDIPCTests", dependencies: ["WWMDCore", "WWMDIPC"]),
        .testTarget(
            name: "WWMDAgentRuntimeTests",
            dependencies: ["WWMDCore", "WWMDStorage", "WWMDAdapters", "WWMDIPC", "WWMDAgentRuntime"]
        )
    ]
)
