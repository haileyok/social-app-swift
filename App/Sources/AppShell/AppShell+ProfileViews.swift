import DesignSystem
import ProfileViews
import SwiftUI

/// The profile surfaces the app shell mounts.
///
/// This is the single seam between the app and the `ProfileViews` package: the
/// shell navigates to ``profileScreen(theme:)`` and everything profile-shaped
/// stays behind it. It is fixture-driven for now, so the profile screen can be
/// mounted and screenshotted before the session/query wiring lands; the fixture
/// variants are ``ProfileFixtureSurface``'s.
///
/// ```swift
/// ProfileSurfaces.profileScreen(theme: nil)
/// ```
public enum ProfileSurfaces {
  /// The profile screen, driven by fixture data.
  ///
  /// - Parameter theme: an optional theme override. When `nil` the screen uses
  ///   the ambient `alfTheme` the app shell injects.
  public static func profileScreen(theme: Theme? = nil) -> some View {
    ProfileFixtureSurface()
      .modifier(OptionalThemeModifier(theme: theme))
  }
}

/// Applies a theme when one was supplied, and leaves the ambient theme alone
/// otherwise. `Theme` is not optional-injectable, so the branch is explicit.
private struct OptionalThemeModifier: ViewModifier {
  let theme: Theme?

  func body(content: Content) -> some View {
    if let theme {
      content.theme(theme)
    } else {
      content
    }
  }
}

#Preview("Profile surfaces") {
  ProfileSurfaces.profileScreen()
}
