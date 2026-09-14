// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "QueryStore",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "QueryStore", targets: ["QueryStore"])
  ],
  targets: [
    .target(name: "QueryStore", dependencies: []),
    .testTarget(name: "QueryStoreTests", dependencies: ["QueryStore"]),
  ]
)
