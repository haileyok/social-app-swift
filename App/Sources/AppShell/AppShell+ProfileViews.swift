import ProfileViews
import SwiftUI

/// The profile surfaces the app shell mounts.
///
/// This is the single seam between the app and the `ProfileViews` package: the
/// shell navigates to ``profileScreen()`` and everything profile-shaped stays
/// behind it. It is fixture-driven for now, so the profile screen can be mounted
/// and screenshotted before the session/query wiring lands; the fixture variants
/// are ``ProfileFixtureSurface``'s.
///
/// The surface reads the ALF theme from the environment (the shell wraps every
/// screen in `.theme(...)`), so the hook carries no theme parameter of its own.
///
/// ```swift
/// ProfileSurfaces.profileScreen()
/// ```
public enum ProfileSurfaces {
  /// The profile screen, driven by fixture data.
  public static func profileScreen() -> some View {
    ProfileFixtureSurface()
  }
}

#Preview("Profile surfaces") {
  ProfileSurfaces.profileScreen()
}
