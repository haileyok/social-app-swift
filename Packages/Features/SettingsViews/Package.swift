// swift-tools-version: 6.3
// The SwiftUI half of the Settings feature: the settings root, the appearance
// screen, app passwords, the saved-feeds editor, the feed/thread preference
// screens, the content-label matrix, the language picker, and the account
// flows (change handle, deactivate, delete, export) as sheets.
//
// Views packages are macOS-CI-only by convention (see root AGENTS.md): the Linux
// build/test loop skips any package whose name ends in `Views` and the
// boundary-lint does not scan them, because they import SwiftUI by design. All
// decision logic lives in the SettingsLogic package next door; nothing here
// re-derives a rule the flow already owns.
//
// This package is a UI package, so MainActor-default isolation is allowed here.
import PackageDescription

let package = Package(
  name: "SettingsViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "SettingsViews", targets: ["SettingsViews"])
  ],
  dependencies: [
    .package(path: "../Settings"),
    .package(path: "../../ATProtoClient"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Persistence"),
    .package(path: "../../UIComponents"),
  ],
  targets: [
    .target(
      name: "SettingsViews",
      dependencies: [
        .product(name: "SettingsLogic", package: "Settings"),
        // SettingsLogic's public API (LiveAppPasswordService, ExportData.url,
        // the XrpcClient-backed services) exposes ATProtoClient types through
        // default arguments and stored clients; the iOS product-framework link
        // closure needs the direct dependency.
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        // `AppearancePreferences.colorMode` is `Persistence.ColorMode`, so the
        // appearance screen reads that type directly.
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/SettingsViews"
    )
  ]
)
