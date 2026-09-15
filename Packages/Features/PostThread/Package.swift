// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "PostThread",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "PostThreadLogic", targets: ["PostThreadLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../QueryStore"),
    // Vendored generator runtime, for `FormatString`/`ATURI`/`DID` used when
    // building lexicon fixtures in tests.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "PostThreadLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "QueryStore", package: "QueryStore"),
      ],
      path: "Sources/PostThreadLogic"
    ),
    .testTarget(
      name: "PostThreadLogicTests",
      dependencies: [
        "PostThreadLogic",
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/PostThreadLogicTests"
    ),
  ]
)
