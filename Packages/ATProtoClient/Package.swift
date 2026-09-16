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
    .package(path: "../Lexicons"),
    .package(path: "../Persistence"),
    .package(path: "../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "ATProtoClient",
      dependencies: [
        "ATSyntax",
        "Persistence",
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ]),
    .testTarget(
      name: "ATProtoClientTests",
      dependencies: ["ATProtoClient", "Lexicons", "Persistence"]),
  ]
)
