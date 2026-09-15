// swift-tools-version: 6.3
// The SwiftUI half of the profile feature: the profile screen (header + tab bar
// + paged content), the followers/follows/known-followers list screens, and the
// edit-profile sheet.
//
// Per the repo convention (AGENTS.md, "Feature package convention"), a feature
// is two SPM packages: `Profile` carries `ProfileLogic` and is Linux-verified,
// and this one is macOS-CI-only because it imports SwiftUI. The Linux CI matrix
// skips any package whose name ends in `Views`, so nothing here needs a Linux
// build.
//
// This is a UI package, so MainActor-default isolation is allowed (the Linux
// boundary rule applies to the 🌐 packages, not to this one).
import PackageDescription

let package = Package(
  name: "ProfileViews",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "ProfileViews", targets: ["ProfileViews"])
  ],
  dependencies: [
    .package(path: "../../DesignSystem"),
    .package(path: "../../DesignTokens"),
    .package(path: "../../Domain"),
    .package(path: "../../Lexicons"),
    .package(path: "../../Moderation"),
    .package(path: "../../UIComponents"),
    .package(path: "../Profile"),
    // The generated lexicon types express fields in the vendored runtime's
    // `FormatString`/`LexBlob`, so the runtime is a direct dependency of any
    // target that constructs them rather than a transitive one.
    .package(path: "../../../tools/lexicon-codegen/swift-atproto"),
  ],
  targets: [
    .target(
      name: "ProfileViews",
      dependencies: [
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Domain", package: "Domain"),
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
        .product(name: "ProfileLogic", package: "Profile"),
        .product(name: "SwiftAtproto", package: "swift-atproto"),
      ],
      path: "Sources/ProfileViews"
    )
  ]
)
