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
    // Views packages are macOS-CI-built. Added as they land:
    .package(path: "../Packages/DesignSystem"),
    .package(path: "../Packages/Features/OnboardingViews"),
    .package(path: "../Packages/DesignTokens"),
    .package(path: "../Packages/Persistence"),
    .package(path: "../Packages/UIComponents"),
    .package(path: "../Packages/Features/ProfileViews"),
    .package(path: "../Packages/Features/PostThreadViews"),
    .package(path: "../Packages/Features/PostThread"),
    .package(path: "../Packages/Features/HomeFeedViews"),
    .package(path: "../Packages/Features/HomeFeed"),
    .package(path: "../Packages/Moderation"),
    .package(path: "../Packages/Features/LoginViews"),
    .package(path: "../Packages/Features/SettingsViews"),
    .package(path: "../Packages/Features/SearchViews"),
    .package(path: "../Packages/Features/Login"),
    .package(path: "../Packages/Features/ComposerViews"),
    .package(path: "../Packages/Features/Composer"),
    .package(path: "../Packages/Features/StarterPacksViews"),
    .package(path: "../Packages/Features/StarterPacks"),
    .package(path: "../Packages/Features/NotificationsViews"),
    .package(path: "../Packages/Features/ModerationUIViews"),
    .package(path: "../Packages/Features/MessagesViews"),
    .package(path: "../Packages/Features/VideoFeed"),
    .package(path: "../Packages/Features/VideoFeedViews"),
    .package(path: "../Packages/ATProtoClient"),
    // Tab wiring: the live tab screens import the Logic products their Views
    // sit on, plus the query/store/lexicon/preference/richtext modules the
    // shell itself touches.
    .package(path: "../Packages/Lexicons"),
    .package(path: "../Packages/QueryStore"),
    .package(path: "../Packages/RichText"),
    .package(path: "../Packages/Preferences"),
    .package(path: "../Packages/Features/Messages"),
    .package(path: "../Packages/Features/Notifications"),
    .package(path: "../Packages/Features/Profile"),
  ],
  targets: [
    .target(
      name: "AppShell",
      dependencies: [
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "DesignSystemCore", package: "DesignSystem"),
        .product(name: "PostThreadViews", package: "PostThreadViews"),
        // `PostThreadScreen.init` reaches `PostThreadLogic` through its
        // `showMore: ThreadShowMore = .initial()` default argument, so the
        // logic product has to be linked here directly.
        .product(name: "PostThreadLogic", package: "PostThread"),
        .product(name: "OnboardingViews", package: "OnboardingViews"),
        // DesignTokens is imported directly (the resolved theme type) and
        // Persistence is imported directly (PersistedAccount), so both are
        // declared: the iOS product-framework link closure needs a direct dep
        // for every imported module.
        .product(name: "DesignTokens", package: "DesignTokens"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "UIComponents", package: "UIComponents"),
        .product(name: "ProfileViews", package: "ProfileViews"),
        .product(name: "HomeFeedViews", package: "HomeFeedViews"),
        .product(name: "HomeFeedLogic", package: "HomeFeed"),
        .product(name: "Moderation", package: "Moderation"),
        .product(name: "LoginViews", package: "LoginViews"),
        .product(name: "SettingsViews", package: "SettingsViews"),
        .product(name: "SearchViews", package: "SearchViews"),
        .product(name: "LoginLogic", package: "Login"),
        .product(name: "ComposerViews", package: "ComposerViews"),
        .product(name: "ComposerLogic", package: "Composer"),
        .product(name: "StarterPacksViews", package: "StarterPacksViews"),
        .product(name: "StarterPacksLogic", package: "StarterPacks"),
        .product(name: "NotificationsViews", package: "NotificationsViews"),
        .product(name: "ModerationUIViews", package: "ModerationUIViews"),
        .product(name: "MessagesViews", package: "MessagesViews"),
        .product(name: "VideoFeedViews", package: "VideoFeedViews"),
        .product(name: "VideoFeedLogic", package: "VideoFeed"),
        .product(name: "ATProtoClient", package: "ATProtoClient"),
        // Live tab screens (TabScreen) import these directly; the iOS
        // product-framework link closure needs a direct dep per module.
        .product(name: "Lexicons", package: "Lexicons"),
        .product(name: "QueryStore", package: "QueryStore"),
        .product(name: "RichText", package: "RichText"),
        .product(name: "Preferences", package: "Preferences"),
        .product(name: "MessagesLogic", package: "Messages"),
        .product(name: "NotificationsLogic", package: "Notifications"),
        .product(name: "ProfileLogic", package: "Profile"),
        .product(name: "UIComponentsCore", package: "UIComponents"),
      ],
      path: "Sources/AppShell"
    )
  ]
)
