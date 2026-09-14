// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "DesignTokens",
  defaultLocalization: "en",
  products: [
    .library(name: "DesignTokens", targets: ["DesignTokens"])
  ],
  targets: [
    .target(name: "DesignTokens", dependencies: []),
    .testTarget(name: "DesignTokensTests", dependencies: ["DesignTokens"]),
  ]
)
