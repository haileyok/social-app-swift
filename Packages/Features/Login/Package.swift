// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Login",
  defaultLocalization: "en",
  products: [
    .library(name: "LoginLogic", targets: ["LoginLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Persistence"),
  ],
  targets: [
    .target(
      name: "LoginLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Persistence", package: "Persistence"),
      ],
      path: "Sources/LoginLogic"
    ),
    .testTarget(
      name: "LoginLogicTests",
      dependencies: ["LoginLogic"],
      path: "Tests/LoginLogicTests"
    ),
  ]
)
