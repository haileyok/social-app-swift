// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Domain",
  defaultLocalization: "en",
  products: [
    .library(name: "Domain", targets: ["Domain"])
  ],
  dependencies: [
    // Generated lexicon types (App.Bsky.FeedDefs_*, Com.Atproto.*) used by the
    // feed tuner, link-meta and url helpers.
    .package(path: "../Lexicons"),
    // at-uri parsing for the url helpers that convert record uris to app paths.
    .package(path: "../ATSyntax"),
    // Vendored generator runtime, for the `FormatString`/`ATURI`/`AnyCodable`
    // types that the generated lexicon fields are expressed in.
    .package(path: "../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "Domain",
      dependencies: [
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "ATSyntax", package: "ATSyntax"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/Domain"
    ),
    .testTarget(
      name: "DomainTests",
      dependencies: ["Domain"],
      path: "Tests/DomainTests"
    ),
  ]
)
