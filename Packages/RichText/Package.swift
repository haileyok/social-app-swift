// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "RichText",
  defaultLocalization: "en",
  // This package is consumed by the iOS app, so it needs an explicit minimum
  // deployment target: without one, SwiftPM builds it at the iOS 12 floor and
  // rejects the iOS 16 URL and Regex APIs it uses.
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "RichText", targets: ["RichText"])
  ],
  targets: [
    .target(name: "RichText", dependencies: []),
    .testTarget(name: "RichTextTests", dependencies: ["RichText"]),
  ]
)
