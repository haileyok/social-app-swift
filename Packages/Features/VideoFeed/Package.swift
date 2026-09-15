// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "VideoFeed",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "VideoFeedLogic", targets: ["VideoFeedLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../Persistence"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types expose formats (FormatString, ATURI, TID) from
    // the vendored runtime; depend on it directly rather than relying on a
    // transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "VideoFeedLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/VideoFeedLogic"
    ),
    .testTarget(
      name: "VideoFeedLogicTests",
      dependencies: [
        "VideoFeedLogic",
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/VideoFeedLogicTests"
    ),
  ]
)
