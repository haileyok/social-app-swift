// swift-tools-version: 6.3
// The SwiftUI half of onboarding: the post-signup wizard's step screens.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. All
// decision logic lives in the OnboardingLogic package next door; nothing here
// re-derives a rule the flow already owns.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "OnboardingViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "OnboardingViews", targets: ["OnboardingViews"])
  ],
  dependencies: [
    .package(path: "../Onboarding"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Preferences"),
    .package(path: "../../UIComponents"),
  ],
  targets: [
    .target(
      name: "OnboardingViews",
      dependencies: [
        .product(name: "OnboardingLogic", package: "Onboarding"),
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/OnboardingViews",
      swiftSettings: [.defaultIsolation(nil)]
    )
  ]
)
