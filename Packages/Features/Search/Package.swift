// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Search",
  platforms: [.iOS(.v18), .macOS(.v14)],
  defaultLocalization: "en",
  products: [
    .library(name: "SearchLogic", targets: ["SearchLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Persistence"),
    .package(path: "../../QueryStore"),
  ],
  targets: [
    .target(
      name: "SearchLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "QueryStore", package: "QueryStore"),
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
      ],
      path: "Tests/SearchLogicTests"
    ),
  ]
)
