// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Search",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "SearchLogic", targets: ["SearchLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Persistence"),
    .package(path: "../../QueryStore"),
    // The generated lexicon types expose formats (FormatString, ATURI, TID)
    // from the vendored runtime; depend on it directly rather than relying on a
    // transitive import.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "SearchLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/SearchLogic"
    ),
    .testTarget(
      name: "SearchLogicTests",
      dependencies: [
        "SearchLogic",
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Tests/SearchLogicTests"
    ),
  ]
)
