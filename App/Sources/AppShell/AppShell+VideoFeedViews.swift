import DesignSystem
import DesignSystemCore
import Foundation
import SwiftUI
import VideoFeedLogic
import VideoFeedViews

/// The video feed's debug entry point.
///
/// Mirrors `AppShell+Login.swift` and `AppShell+Components.swift`: the hook lives
/// in its own file so work on the root view and this surface do not conflict.
/// Nothing here is referenced by the root view by default, so the 5-tab shell and
/// its smoke tests are untouched while the immersive feed is reachable from a
/// debug toolbar:
///
/// ```swift
/// // A tab's toolbar, alongside the login and component-gallery links:
/// NavigationLink("Video") { VideoFeedSurfaces.videoFeedScreen(theme: .light) }
/// ```
///
/// The screen it mounts is the real ``VideoFeedScreen`` - pager, player pool,
/// scrubber, moderation overlay - driven by fixture items, so the player is
/// exercisable without a signed-in account or a feed fetch.
public enum VideoFeedSurfaces {
  /// The ALF theme preference the shell persists, falling back to `.system` when
  /// the key is missing or holds an unknown value.
  ///
  /// Read from `UserDefaults` rather than `@AppStorage` so the entry point stays a
  /// plain static function with a default argument, matching
  /// `AppShell+Components.swift`. This is the same `alfTheme` key the shell writes.
  public static var storedThemePreference: ThemePreference {
    ThemePreference(rawValue: UserDefaults.standard.string(forKey: themeStorageKey) ?? "")
      ?? .system
  }

  /// The `@AppStorage` key the shell persists its theme preference under.
  public static let themeStorageKey = "alfTheme"

  /// The immersive video feed, built from fixture items.
  ///
  /// - Parameter theme: the ALF theme to inject. A screen presented on its own has
  ///   no ancestor supplying one, so it is applied here. Defaults to the stored
  ///   preference, which keeps the parameter a value and the call site free of
  ///   state.
  @MainActor
  public static func videoFeedScreen(
    theme: ThemePreference = storedThemePreference
  ) -> some View {
    VideoFeedScreen(
      items: VideoFeedFixtures.items(),
      settings: VideoFeedSettings.fixture)
      .theme(theme)
  }
}

/// The autoplay inputs the fixture screen runs with.
///
/// The real value comes from ``VideoAutoplayPreference/settings(account:did:)``
/// against the account-scoped store. The fixture has no account, so it uses the
/// documented defaults: autoplay on, muted, and not inside a message thread.
enum VideoFeedSettings {
  static let fixture = VideoAutoplaySettings()
}

#Preview {
  VideoFeedSurfaces.videoFeedScreen(theme: .dark)
}
