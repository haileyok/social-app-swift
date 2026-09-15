import DesignSystem
import DesignSystemCore
import SwiftUI
import SettingsViews

/**
 The app-side hook for the settings surfaces.

 This is the whole App-layer footprint of the SettingsViews package: one entry
 point that builds the settings root over *fixture* data, so the screen can be
 rendered and visually reviewed with no session, no network, and no store
 wiring. Everything below it lives in `Packages/Features/SettingsViews`.

 `settingsScreen(theme:)` takes the theme explicitly rather than reading
 `@AppStorage`, which keeps the fixture surface usable from a preview, a
 screenshot harness, or a test without touching the app's stored preference.

 Screenshot fixtures: `SettingsSurfaces.settingsScreen(theme:)` renders the
 settings root; the routes below it are reachable by tapping through, and each
 one is also directly constructible from its own view's `#Preview`.
 */
public enum SettingsSurfaces {
  /**
   The settings root screen, backed by fixture data and rendering under `theme`.

   - Parameter theme: the ALF theme preference to render with, e.g. `.light`.
   */
  @MainActor
  public static func settingsScreen(theme: ThemePreference) -> some View {
    NavigationStack {
      SettingsRootScreen(viewModel: SettingsViewModel.fixture())
    }
    .theme(theme)
  }
}

#Preview {
  SettingsSurfaces.settingsScreen(theme: .light)
}
