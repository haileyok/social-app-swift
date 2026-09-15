// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "TestSupport",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "TestSupport", targets: ["TestSupport"])
  ],
  targets: [
    .target(name: "TestSupport", dependencies: []),
    .testTarget(name: "TestSupportTests", dependencies: ["TestSupport"]),
  ]
)
