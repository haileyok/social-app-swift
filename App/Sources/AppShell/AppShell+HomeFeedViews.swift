import HomeFeedViews
import SwiftUI

/**
 The Home feed's entry points for the app shell.

 Kept in its own file so wiring this package does not touch `AppRootView.swift`
 or `AppShell.swift`: routing, the session dependency and the screenshot case
 are the app-shell owner's call, and this file only offers the surfaces to wire.

 Two things are exposed:

 - ``feedScreen(theme:)`` - the screenshot/verification surface. It returns the
   fixture-driven demo feed, which needs no session and no appview, so the
   screenshot loop can capture the real Home feed view path on a cold launch.
 - ``feedScreen(model:theme:)`` - the live screen, for the shell to mount once a
   session, a `HomeFeedModel` and moderation options exist.

 The launch argument is `-uiTestHomeFeed <variant>`, matching the shell's
 existing `-uiTestScreen` convention; an unknown value falls back to the
 populated feed.
 */
public enum HomeFeedSurfaces {
  /// The launch argument the screenshot loop passes to pick a demo variant.
  public static let variantArgument = "uiTestHomeFeed"

  /// The fixture-driven screen, wrapped in the requested theme.
  ///
  /// This is the surface the screenshot loop captures: it renders the production
  /// `HomeFeedScreen` building blocks over `HomeFeedFixtures` slices, so the
  /// image shows real layout, real embeds and real moderation masks without a
  /// session.
  @MainActor
  public static func feedScreen(theme: ThemePreference) -> some View {
    let variant =
      UserDefaults.standard.string(forKey: variantArgument)
      ?? ProcessInfo.processInfo.environment["HOME_FEED_VARIANT"]
    return HomeFeedDemoScreen(argument: variant)
      .theme(theme)
  }

  /// The live Home feed screen over a caller-built model.
  ///
  /// The shell owns the model's construction (a `QueryStore`, the pinned feeds
  /// and a fetcher per descriptor), because those are session and preference
  /// concerns. This entry point only states the shape the screen expects.
  @MainActor
  public static func feedScreen(
    model: HomeFeedModel,
    theme: ThemePreference,
    moderationOpts: ModerationOpts? = nil,
    viewerDid: String? = nil
  ) -> some View {
    HomeFeedScreen(
      model: HomeFeedViewModel(
        model: model,
        presentation: .feeds,
        moderationOpts: moderationOpts,
        viewerDid: viewerDid))
      .theme(theme)
  }
}
