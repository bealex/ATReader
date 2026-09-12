// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "AuthorTodayBooks",
    defaultLocalization: "en",
    platforms: [ .iOS("26.0"), .macOS(.v15) ],
    products: [
        .library(name: "AuthorTodayBooks", targets: [ "AuthorTodayBooks" ])
    ],
    dependencies: [
        .package(path: "../BookKit"),
        .package(path: "../AuthorToday"),
    ],
    targets: [
        .target(
            name: "AuthorTodayBooks",
            dependencies: [ "BookKit", "AuthorToday" ],
            swiftSettings: [ .swiftLanguageMode(.v6) ]
        )
    ]
)
