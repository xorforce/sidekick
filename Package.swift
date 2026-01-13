// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "sidekick",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "sidekick", targets: ["SidekickCLI"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0")
  ],
  targets: [
    .executableTarget(
      name: "SidekickCLI",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/SidekickCLI",
      swiftSettings: [
        .unsafeFlags(["-parse-as-library"])
      ]
    )
  ]
)
