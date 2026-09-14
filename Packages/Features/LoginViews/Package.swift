// swift-tools-version: 6.3
// The SwiftUI half of the Login feature: the sign-in form, the service picker,
// the 2FA sheet, the stored-account chooser, and the password-reset screens.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. All
// decision logic lives in the LoginLogic package next door; nothing here
// re-derives a rule the flow already owns.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "LoginViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "LoginViews", targets: ["LoginViews"])
  ],
  dependencies: [
    .package(path: "../Login"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Persistence"),
    .package(path: "../../UIComponents"),
  ],
  targets: [
    .target(
      name: "LoginViews",
      dependencies: [
        .product(name: "LoginLogic", package: "Login"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/LoginViews"
    )
  ]
)
