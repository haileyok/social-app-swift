// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "RichText",
  defaultLocalization: "en",
  products: [
    .library(name: "RichText", targets: ["RichText"])
  ],
  targets: [
    .target(name: "RichText", dependencies: []),
    .testTarget(name: "RichTextTests", dependencies: ["RichText"]),
  ]
)
