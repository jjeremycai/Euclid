// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EuclidCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "EuclidCore", targets: ["EuclidCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Clipy/Sauce", branch: "master"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
    ],
    targets: [
	    .target(
	        name: "EuclidCore",
		        dependencies: [
		            "Sauce",
		            .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
		            .product(name: "Dependencies", package: "swift-dependencies"),
		            .product(name: "DependenciesMacros", package: "swift-dependencies"),
		            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
		            .product(name: "Logging", package: "swift-log"),
		        ],
	        path: "Sources/EuclidCore",
	        linkerSettings: [
	            .linkedFramework("IOKit")
	        ]
	    ),
        .testTarget(
            name: "EuclidCoreTests",
            dependencies: ["EuclidCore"],
            path: "Tests/EuclidCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
