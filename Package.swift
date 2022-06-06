// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ARVideoKit",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "ARVideoKit",
            targets: ["ARVideoKit"]),
    ],
    dependencies: [ .package(url: "https://github.com/shogo4405/HaishinKit.swift.git",from: "1.2.3")],
    targets: [
        .target(
            name: "ARVideoKit",
            dependencies: [],
            path: "ARVideoKit")
    ]
)
