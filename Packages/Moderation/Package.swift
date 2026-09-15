// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Moderation",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  // This package is consumed by the iOS app, so it needs an explicit minimum
  // deployment target: without one, SwiftPM builds it at the iOS 12 floor and
  // rejects the Regex APIs it uses.
  products: [
    .library(name: "Moderation", targets: ["Moderation"])
  ],
  targets: [
    .target(name: "Moderation", dependencies: []),
    .testTarget(name: "ModerationTests", dependencies: ["Moderation"]),
  ]
)
