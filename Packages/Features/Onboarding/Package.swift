// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Onboarding",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "OnboardingLogic", targets: ["OnboardingLogic"])
  ],
  dependencies: [
    .package(path: "../../ATProtoClient"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Preferences"),
    .package(path: "../../QueryStore"),
    // Vendored generator runtime, for the `FormatString`/`ATURI`/`Handle`
    // types the generated lexicon fields (and the Lexicons default arguments
    // OnboardingLogic passes) are expressed in.
    .package(path: "../../tools/lexicon-codegen/swift-atproto"),
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
        .product(name: "SwiftAtproto", package: "swift-atproto"),
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
