// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "BookRenderer",
    defaultLocalization: "en",
    platforms: [ .iOS("26.0"), .macOS(.v15) ],
    products: [
        .library(name: "BookRenderer", targets: [ "BookRenderer" ])
    ],
    dependencies: [
        .package(path: "../BookKit"),
        .package(url: "https://github.com/bealex/memoirs-ios.git", from: "2.1.4"),
    ],
    targets: [
        .target(
            name: "BookRenderer",
            dependencies: [ "BookKit", .product(name: "Memoirs", package: "memoirs-ios") ],
            resources: [ .process("Resources") ],
            swiftSettings: [ .swiftLanguageMode(.v6) ]
        )
    ]
)
