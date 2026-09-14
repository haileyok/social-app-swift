import DesignSystem
import DesignSystemCore
import DesignTokens
import SwiftUI

/// Root app view. Placeholder until Phase 4 wires the real 5-tab shell.
///
/// For now it renders the DesignSystem token gallery, which proves the app
/// surface builds end-to-end against the new package: the SwiftUI wiring, the
/// bundled Inter font resource and the three themes all have to resolve for
/// this view to compile and run.
public struct SocialAppRootView: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.colorScheme) private var colorScheme

  public init() {}

  public var body: some View {
    NavigationStack {
      TokenGallery(theme: resolvedTheme)
        .navigationTitle("Token gallery")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Picker("Theme", selection: $themePreference) {
                ForEach(ThemePreference.allCases, id: \.self) { preference in
                  Text(preference.rawValue.capitalized).tag(preference.rawValue)
                }
              }
            } label: {
              Image(systemName: "circle.lefthalf.filled")
            }
          }
        }
    }
  }

  /// Resolves the stored preference against the current appearance, so
  /// `.system` follows the OS and the explicit names win.
  private var resolvedTheme: DesignTokens.Theme {
    ThemeResolver.resolve(
      preference: ThemePreference(rawValue: themePreference) ?? .system,
      systemScheme: colorScheme == .dark ? .dark : .light)
  }
}
