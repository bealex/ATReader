// swift-tools-version: 6.0
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import PackageDescription

let package = Package(
    name: "BookKit",
    defaultLocalization: "en",
    platforms: [ .iOS("26.0"), .macOS(.v15) ],
    products: [
        .library(name: "BookKit", targets: [ "BookKit" ])
    ],
    targets: [
        .target(name: "BookKit", resources: [ .process("Resources") ], swiftSettings: [ .swiftLanguageMode(.v6) ]),
        .testTarget(name: "BookKitTests", dependencies: [ "BookKit" ], swiftSettings: [ .swiftLanguageMode(.v6) ]),
    ]
)
