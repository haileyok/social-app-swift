import Foundation
import Testing

@testable import SettingsLogic

/// The navigation tree and menu data, ported from `src/routes.ts` and the
/// settings screens' JSX.
@Suite struct SettingsRouteTests {

  /// Every route's path is the RN path verbatim.
  @Test func pathsMatchRoutesTable() {
    #expect(SettingsRoute.settings.path == "/settings")
    #expect(SettingsRoute.account.path == "/settings/account")
    #expect(SettingsRoute.privacyAndSecurity.path == "/settings/privacy-and-security")
    #expect(SettingsRoute.appPasswords.path == "/settings/app-passwords")
    #expect(SettingsRoute.moderation.path == "/moderation")
    #expect(SettingsRoute.contentAndMedia.path == "/settings/content-and-media")
    #expect(SettingsRoute.followingFeedPreferences.path == "/settings/following-feed")
    #expect(SettingsRoute.threads.path == "/settings/threads")
    #expect(SettingsRoute.savedFeeds.path == "/settings/saved-feeds")
    #expect(SettingsRoute.appearance.path == "/settings/appearance")
    #expect(SettingsRoute.language.path == "/settings/language")
  }

  /// Only the root has no parent, and every other route hangs off one.
  @Test func treeIsConnected() {
    #expect(SettingsRoute.settings.parent == nil)
    for route in SettingsRoute.allCases where route != .settings {
      #expect(route.parent != nil, "\(route) has no parent")
    }
  }

  /// The app-password screen is reached through privacy and security, matching
  /// the RN `PrivacyAndSecuritySettings.tsx` link.
  @Test func appPasswordsHangOffPrivacyAndSecurity() {
    #expect(SettingsRoute.appPasswords.parent == .privacyAndSecurity)
  }

  /// The feed and thread preference screens hang off content and media,
  /// matching `ContentAndMediaSettings.tsx`.
  @Test func feedAndThreadPrefsHangOffContentAndMedia() {
    #expect(SettingsRoute.followingFeedPreferences.parent == .contentAndMedia)
    #expect(SettingsRoute.threads.parent == .contentAndMedia)
    #expect(SettingsRoute.savedFeeds.parent == .contentAndMedia)
  }

  /// The out-of-scope v1 surfaces are marked, so the menu builder can skip
  /// them.
  @Test func outOfScopeRoutesAreMarked() {
    #expect(!SettingsRoute.appIcon.isInScope)
    #expect(!SettingsRoute.betaFeatures.isInScope)
    #expect(!SettingsRoute.about.isInScope)
    #expect(SettingsRoute.appearance.isInScope)
    #expect(SettingsRoute.appPasswords.isInScope)
  }

  /// A deep link resolves to its route, including one with a trailing segment.
  @Test func pathResolution() {
    #expect(SettingsRoute.resolve(path: "/settings/appearance") == .appearance)
    #expect(SettingsRoute.resolve(path: "/settings/account/") == .account)
    #expect(SettingsRoute.resolve(path: "/settings/app-passwords") == .appPasswords)
    #expect(SettingsRoute.resolve(path: "/settings") == .settings)
    #expect(SettingsRoute.resolve(path: "/nope") == nil)
  }

  /// The longest matching path wins, so `/settings/app-passwords` does not
  /// resolve to `/settings`.
  @Test func pathResolutionPrefersLongestMatch() {
    #expect(SettingsRoute.resolve(path: "/settings/content-and-media") == .contentAndMedia)
  }

  /// The root menu lists the in-scope rows in RN's order.
  @Test func rootMenuOrder() {
    let titles = SettingsMenu.root[0].rows.map(\.title)
    #expect(
      titles == [
        "Account", "Privacy and security", "Moderation and content filters",
        "Content and media", "Appearance", "Languages", "Help", "Sign out",
      ])
  }

  /// Sign out is the only destructive row on the root in v1.
  @Test func rootDestructiveRows() {
    let destructive = SettingsMenu.root[0].rows.filter(\.isDestructive).map(\.title)
    #expect(destructive == ["Sign out"])
  }

  /// The account menu lists the destructive actions RN marks.
  @Test func accountMenuDestructiveRows() {
    let destructive = SettingsMenu.account[0].rows.filter(\.isDestructive).map(\.title)
    #expect(destructive == ["Deactivate account", "Delete account"])
  }

  /// Every menu row's navigate action points at a route that is in scope.
  @Test func menuRowsNavigateToInScopeRoutes() {
    for section in SettingsMenu.all {
      for row in section.rows {
        guard let route = row.route else { continue }
        #expect(route.isInScope, "\(row.title) navigates to out-of-scope \(route)")
      }
    }
  }
}
