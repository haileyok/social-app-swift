// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Persistence",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "Persistence", targets: ["Persistence"])
  ],
  targets: [
    .target(name: "Persistence", dependencies: []),
    .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
  ]
)
