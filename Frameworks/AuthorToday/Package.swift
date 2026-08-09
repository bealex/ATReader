// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "AuthorToday",
    defaultLocalization: "en",
    platforms: [ .iOS(.v18), .macOS(.v15) ],
    products: [
        .library(name: "AuthorToday", targets: [ "AuthorToday" ])
    ],
    targets: [
        .target(name: "AuthorToday", resources: [ .process("Resources") ], swiftSettings: [ .swiftLanguageMode(.v6) ]),
        .testTarget(
            name: "AuthorTodayTests",
            dependencies: [ "AuthorToday" ],
            swiftSettings: [ .swiftLanguageMode(.v6) ]
        ),
    ]
)
