// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "WatchSwiftyCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WatchSwiftyCore", targets: ["WatchSwiftyCore"]),
    ],
    dependencies: [
        // During development: the server checkout next to this repo (see README). Pinned to a release tag later.
        // Release tag of the server repo. For unreleased server changes switch to
        // `.package(path: "../../../watchswifty")` locally – never commit that.
        .package(url: "https://github.com/PaddXy95/watchswifty.git", from: "0.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.4"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "WatchSwiftyCore",
            dependencies: [
                .product(name: "WatchSwiftyClient", package: "watchswifty"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .testTarget(
            name: "WatchSwiftyCoreTests",
            dependencies: [
                "WatchSwiftyCore",
                .product(name: "WatchSwiftyClient", package: "watchswifty"),
            ]
        ),
    ]
)
