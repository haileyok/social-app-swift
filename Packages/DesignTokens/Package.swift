// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "DesignTokens",
  platforms: [.iOS(.v18), .macOS(.v14)],
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "DesignTokens", targets: ["DesignTokens"])
  ],
  targets: [
    .target(name: "DesignTokens", dependencies: []),
    .testTarget(name: "DesignTokensTests", dependencies: ["DesignTokens"]),
  ]
)
