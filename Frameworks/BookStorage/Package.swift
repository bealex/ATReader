// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "BookStorage",
    defaultLocalization: "en",
    platforms: [ .iOS("26.0"), .macOS(.v15) ],
    products: [
        .library(name: "BookStorage", targets: [ "BookStorage" ])
    ],
    dependencies: [
        .package(path: "../BookKit"),
        .package(url: "https://github.com/bealex/memoirs-ios.git", from: "2.1.4"),
    ],
    targets: [
        .target(
            name: "BookStorage",
            dependencies: [ "BookKit", .product(name: "Memoirs", package: "memoirs-ios") ],
            swiftSettings: [ .swiftLanguageMode(.v6) ]
        )
    ]
)
