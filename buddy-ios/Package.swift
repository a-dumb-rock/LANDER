// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LANDERBuddy",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LANDERBuddy", targets: ["LANDERBuddy"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/danielgindi/Charts.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "LANDERBuddy",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "DGCharts", package: "Charts"),
            ],
            path: "LANDERBuddy"
        ),
    ]
)
