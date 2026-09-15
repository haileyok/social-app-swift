// swift-tools-version: 6.3
// The iOS app shell. NOT Linux-verifiable (imports SwiftUI/UIKit).
// All source code lives in Packages/; this target is the thin entry point.
//
// Two consumers: the hand-maintained App/SocialApp.xcodeproj (which owns the
// @main entry in App/App/ and the XCUITest target) and the app's own test
// targets, which link this product to read the shell's identifiers and tab
// metadata instead of duplicating string literals.
import PackageDescription

let package = Package(
  name: "AppShell",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "AppShell", targets: ["AppShell"])
  ],
  dependencies: [
    // UI packages (macOS-CI-built). Added as they land:
    .package(path: "../Packages/DesignSystem"),
    .package(path: "../Packages/UIComponents"),
    .package(path: "../Packages/Features/LoginViews"),
    .package(path: "../Packages/Features/Login"),
    .package(path: "../Packages/Features/ComposerViews"),
    .package(path: "../Packages/ATProtoClient"),
  ],
  targets: [
    .target(
      name: "AppShell",
      dependencies: [
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "LoginViews", package: "LoginViews"),
        .product(name: "LoginLogic", package: "Login"),
        .product(name: "ComposerViews", package: "ComposerViews"),
        .product(name: "ATProtoClient", package: "ATProtoClient"),
      ],
      path: "Sources/AppShell"
    )
  ]
)
