// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "AuthorToday",
    defaultLocalization: "en",
    platforms: [ .iOS("26.0"), .macOS(.v15) ],
    products: [
        .library(name: "AuthorToday", targets: [ "AuthorToday" ])
    ],
    dependencies: [
        .package(url: "https://github.com/bealex/memoirs-ios.git", from: "2.1.4")
    ],
    targets: [
        .target(
            name: "AuthorToday",
            dependencies: [ .product(name: "Memoirs", package: "memoirs-ios") ],
            resources: [ .process("Resources") ],
            swiftSettings: [ .swiftLanguageMode(.v6) ]
        ),
        .testTarget(
            name: "AuthorTodayTests",
            dependencies: [ "AuthorToday" ],
            swiftSettings: [ .swiftLanguageMode(.v6) ]
        ),
    ]
)
