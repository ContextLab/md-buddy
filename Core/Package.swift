// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDBuddyCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MDBuddyCore", targets: ["MDBuddyCore"]),
        .executable(name: "mdbuddy-render", targets: ["mdbuddy-render"]),
    ],
    dependencies: [
        // Apple's fork of GitHub's cmark-gfm (BSD-2-Clause). Fast C parser for
        // CommonMark + GFM extensions (tables, strikethrough, autolinks, task lists).
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MDBuddyCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "mdbuddy-render",
            dependencies: ["MDBuddyCore"]
        ),
        .testTarget(
            name: "MDBuddyCoreTests",
            dependencies: ["MDBuddyCore"]
        ),
    ]
)
