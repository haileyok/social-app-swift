import Foundation

/// The settings navigation tree, mirroring the RN app's route table.
///
/// Port of the settings-related entries in `src/routes.ts` plus the `LinkItem`
/// targets the settings screens render. Each case carries the RN path verbatim
/// so a deep link, a test, and a future view layer all agree on one identity.
///
/// Routes that the v1 port deliberately excludes (app icons, beta features,
/// moderation inbox, notifications, find-contacts, about) are still enumerated
/// so the tree is complete, and marked ``SettingsRoute/isInScope`` false. The
/// store builds its menu from the in-scope subset only.
public enum SettingsRoute: String, CaseIterable, Sendable, Hashable {
  case settings
  case account
  case privacyAndSecurity
  case appPasswords
  case moderation
  case contentAndMedia
  case followingFeedPreferences
  case threads
  case savedFeeds
  case appearance
  case language

  // Out of v1 scope, present so the tree mirrors `routes.ts`.
  case appIcon
  case betaFeatures
  case notificationSettings
  case findContacts
  case about

  /// The RN path for this route, as written in `src/routes.ts`.
  public var path: String {
    switch self {
    case .settings: return "/settings"
    case .account: return "/settings/account"
    case .privacyAndSecurity: return "/settings/privacy-and-security"
    case .appPasswords: return "/settings/app-passwords"
    case .moderation: return "/moderation"
    case .contentAndMedia: return "/settings/content-and-media"
    case .followingFeedPreferences: return "/settings/following-feed"
    case .threads: return "/settings/threads"
    case .savedFeeds: return "/settings/saved-feeds"
    case .appearance: return "/settings/appearance"
    case .language: return "/settings/language"
    case .appIcon: return "/settings/app-icon"
    case .betaFeatures: return "/settings/beta-features"
    case .notificationSettings: return "/settings/notifications"
    case .findContacts: return "/settings/find-contacts"
    case .about: return "/settings/about"
    }
  }

  /// The route that links to this one, or nil for the root.
  public var parent: SettingsRoute? {
    switch self {
    case .settings: return nil
    case .account, .privacyAndSecurity, .moderation, .contentAndMedia,
      .appearance, .language, .appIcon, .betaFeatures, .notificationSettings,
      .findContacts, .about:
      return .settings
    case .appPasswords: return .privacyAndSecurity
    case .followingFeedPreferences, .threads, .savedFeeds: return .contentAndMedia
    }
  }

  /// The routes linked from this one, in the order the RN screens list them.
  public var children: [SettingsRoute] {
    SettingsRoute.allCases.filter { $0.parent == self }
  }

  /// Whether the v1 port implements this route's logic.
  public var isInScope: Bool {
    switch self {
    case .settings, .account, .privacyAndSecurity, .appPasswords, .moderation,
      .contentAndMedia, .followingFeedPreferences, .threads, .savedFeeds,
      .appearance, .language:
      return true
    case .appIcon, .betaFeatures, .notificationSettings, .findContacts, .about:
      return false
    }
  }

  /// The screen title RN renders for this route.
  public var title: String {
    switch self {
    case .settings: return "Settings"
    case .account: return "Account"
    case .privacyAndSecurity: return "Privacy and security"
    case .appPasswords: return "App Passwords"
    case .moderation: return "Moderation and content filters"
    case .contentAndMedia: return "Content and media"
    case .followingFeedPreferences: return "Following Feed Preferences"
    case .threads: return "Thread Preferences"
    case .savedFeeds: return "Feeds"
    case .appearance: return "Appearance"
    case .language: return "Languages"
    case .appIcon: return "App Icon"
    case .betaFeatures: return "Beta features"
    case .notificationSettings: return "Notifications"
    case .findContacts: return "Find and invite friends"
    case .about: return "About"
    }
  }

  /// The route a path resolves to, for deep links. Matches on the path's
  /// leading segments so a route with params still resolves to its screen.
  public static func resolve(path: String) -> SettingsRoute? {
    let clean = path.split(separator: "?").first.map(String.init) ?? path
    return allCases
      .sorted { $0.path.count > $1.path.count }
      .first { clean == $0.path || clean.hasPrefix($0.path + "/") }
  }
}

/// One row in a settings menu.
///
/// `SettingsList.LinkItem` and `SettingsList.PressableItem` in the RN app are
/// two shapes of the same row; the distinction is carried here as
/// ``SettingsRowAction`` rather than as two row types, because the v1 port has
/// no press handling of its own.
public struct SettingsRow: Sendable, Hashable {
  /// What activating the row does.
  public enum Action: Sendable, Hashable {
    /// Navigates to another settings route.
    case navigate(SettingsRoute)
    /// Opens an external URL (the Help row).
    case openURL(String)
    /// Opens an in-screen flow, named by the owning section.
    case flow(String)
  }

  /// Visible label.
  public let title: String
  /// The action the row performs.
  public let action: Action
  /// Whether RN renders the row as destructive (delete, deactivate, sign out).
  public let isDestructive: Bool
  /// Optional trailing detail text, e.g. "On"/"Off" for the automation label.
  public let badge: String?

  public init(
    title: String,
    action: Action,
    isDestructive: Bool = false,
    badge: String? = nil
  ) {
    self.title = title
    self.action = action
    self.isDestructive = isDestructive
    self.badge = badge
  }

  /// The route this row navigates to, when it navigates.
  public var route: SettingsRoute? {
    if case .navigate(let route) = action { return route }
    return nil
  }
}

/// A titled group of rows, the unit `SettingsList.Container` renders.
public struct SettingsSection: Sendable, Hashable {
  /// The route whose screen owns this section.
  public let route: SettingsRoute
  /// Visible heading, when the RN screen renders one.
  public let title: String?
  /// The rows, in screen order.
  public let rows: [SettingsRow]
  /// A plain-text note the screen shows above the rows (`SettingsList.Item` +
  /// `Admonition`), when it has one.
  public let note: String?

  public init(
    route: SettingsRoute,
    title: String? = nil,
    rows: [SettingsRow],
    note: String? = nil
  ) {
    self.route = route
    self.title = title
    self.rows = rows
    self.note = note
  }
}

/// The settings menu content, as data.
///
/// This is the port of the JSX in `screens/Settings/Settings.tsx`,
/// `AccountSettings.tsx`, `PrivacyAndSecuritySettings.tsx` and
/// `ContentAndMediaSettings.tsx`: the rows, their order, and which of them the
/// v1 scope includes. Keeping it as data means the tree is testable on Linux
/// without a renderer.
public enum SettingsMenu {

  /// The root settings screen's sections.
  public static var root: [SettingsSection] {
    [
      SettingsSection(
        route: .settings,
        rows: [
          SettingsRow(title: "Account", action: .navigate(.account)),
          SettingsRow(
            title: "Privacy and security", action: .navigate(.privacyAndSecurity)),
          SettingsRow(
            title: "Moderation and content filters", action: .navigate(.moderation)),
          SettingsRow(title: "Content and media", action: .navigate(.contentAndMedia)),
          SettingsRow(title: "Appearance", action: .navigate(.appearance)),
          SettingsRow(title: "Languages", action: .navigate(.language)),
          SettingsRow(title: "Help", action: .openURL(SettingsConstants.helpDeskURL)),
          SettingsRow(
            title: "Sign out", action: .flow("signOut"), isDestructive: true),
        ])
    ]
  }

  /// The account screen's sections.
  public static var account: [SettingsSection] {
    [
      SettingsSection(
        route: .account,
        rows: [
          SettingsRow(title: "Handle", action: .flow("changeHandle")),
          SettingsRow(title: "Password", action: .flow("changePassword")),
          SettingsRow(title: "Update email", action: .flow("updateEmail")),
          SettingsRow(title: "Birthday", action: .flow("birthday")),
          SettingsRow(title: "Automation label", action: .flow("automationLabel")),
          SettingsRow(title: "Export my data", action: .flow("exportData")),
          SettingsRow(
            title: "Deactivate account", action: .flow("deactivateAccount"),
            isDestructive: true),
          SettingsRow(
            title: "Delete account", action: .flow("deleteAccount"),
            isDestructive: true),
        ])
    ]
  }

  /// The privacy-and-security screen's sections.
  public static var privacyAndSecurity: [SettingsSection] {
    [
      SettingsSection(
        route: .privacyAndSecurity,
        rows: [
          SettingsRow(title: "App passwords", action: .navigate(.appPasswords))
        ])
    ]
  }

  /// The content-and-media screen's sections, including the two links into the
  /// feed and thread preference screens.
  public static var contentAndMedia: [SettingsSection] {
    [
      SettingsSection(
        route: .contentAndMedia,
        rows: [
          SettingsRow(
            title: "Following feed preferences",
            action: .navigate(.followingFeedPreferences)),
          SettingsRow(title: "Thread preferences", action: .navigate(.threads)),
          SettingsRow(title: "Feeds", action: .navigate(.savedFeeds)),
        ])
    ]
  }

  /// Every section, for the whole in-scope tree.
  public static var all: [SettingsSection] {
    [root, account, privacyAndSecurity, contentAndMedia].flatMap { $0 }
  }
}

/// Constants the settings surfaces share.
public enum SettingsConstants {
  /// `HELP_DESK_URL` from `lib/constants.ts` (`HELP_DESK_LANG` is `en-us`),
  /// opened by the Help row.
  public static let helpDeskURL = "https://blueskyweb.zendesk.com/hc/en-us"

  /// `BSKY_SERVICE_DID` from `lib/constants.ts`. The entryway, which answers
  /// `com.atproto.temp.checkHandleAvailability`.
  public static let blueskyServiceDID = "did:web:bsky.social"
  /// `BSKY_SERVICE` from `lib/constants.ts`.
  public static let blueskyService = "https://bsky.social"
  /// `PUBLIC_BSKY_SERVICE` from `lib/constants.ts`.
  public static let publicBlueskyService = "https://public.api.bsky.app"

  /// The URI `com.atproto.sync.getRepo` / `getCheckout` are fetched from,
  /// relative to the PDS base URL. Both are GETs returning CAR bytes.
  public static let getRepoPath = "com.atproto.sync.getRepo"
  public static let getCheckoutPath = "com.atproto.sync.getCheckout"
  /// The CAR content type the repo export is saved as.
  public static let carContentType = "application/vnd.ipld.car"
}
