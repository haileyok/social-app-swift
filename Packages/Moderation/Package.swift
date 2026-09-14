// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Moderation",
  defaultLocalization: "en",
  products: [
    .library(name: "Moderation", targets: ["Moderation"])
  ],
  targets: [
    .target(name: "Moderation", dependencies: []),
    .testTarget(name: "ModerationTests", dependencies: ["Moderation"]),
  ]
)
