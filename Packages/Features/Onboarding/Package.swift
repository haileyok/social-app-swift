// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Onboarding",
  platforms: [.iOS(.v18), .macOS(.v14)],
  defaultLocalization: "en",
  products: [
    .library(name: "OnboardingLogic", targets: ["OnboardingLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
  ],
  targets: [
    .target(
      name: "OnboardingLogic",
      dependencies: [
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "QueryStore", package: "QueryStore"),
      ],
      path: "Sources/OnboardingLogic"
    ),
    .testTarget(
      name: "OnboardingLogicTests",
      dependencies: ["OnboardingLogic"],
      path: "Tests/OnboardingLogicTests"
    ),
  ]
)
