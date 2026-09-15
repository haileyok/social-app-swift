// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Composer",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "ComposerLogic", targets: ["ComposerLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../ATSyntax"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../QueryStore"),
    .package(path: "../../RichText"),
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "ComposerLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "ATSyntax", package: "ATSyntax"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/ComposerLogic"
    ),
    .testTarget(
      name: "ComposerLogicTests",
      dependencies: ["ComposerLogic"],
      path: "Tests/ComposerLogicTests"
    ),
  ]
)
