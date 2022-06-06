// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ARVideoKit",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "ARVideoKit",
            targets: ["ARVideoKit"]),
    ],
    dependencies: [ .package(url: "https://github.com/gorston/HaishinKit.swift.git", from: "1.2.2")],
    targets: [
        .target(
            name: "ARVideoKit",
            dependencies: [.product(name: "HaishinKit", package: "HaishinKit.swift")],
            path: "ARVideoKit")
    ]
)
