// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "ATProtoClient",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "ATProtoClient", targets: ["ATProtoClient"])
  ],
  dependencies: [
    .package(path: "../ATSyntax"),
    .package(path: "../Persistence"),
  ],
  targets: [
    .target(
      name: "ATProtoClient",
      dependencies: ["ATSyntax", "Persistence"]),
    .testTarget(
      name: "ATProtoClientTests",
      dependencies: ["ATProtoClient", "Persistence"]),
  ]
)
