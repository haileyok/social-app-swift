import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents

/// The component-gallery entry point.
///
/// Kept in its own file so the app-shell agent's work on `AppShell.swift` and
/// this hook do not conflict: nothing here is referenced by the root view yet.
/// The root view can mount it with a debug control once the 5-tab shell lands:
///
/// ```swift
/// #if DEBUG
/// NavigationLink("Components") { ComponentGalleryScreen() }
/// #endif
/// ```
public struct ComponentGalleryScreen: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue
  @Environment(\.colorScheme) private var colorScheme

  public init() {}

  public var body: some View {
    NavigationStack {
      ComponentGallery(theme: resolvedTheme)
        .navigationTitle("Components")
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

  /// Resolves the stored preference against the current appearance, matching the
  /// token gallery's behaviour so the two screens agree.
  private var resolvedTheme: DesignTokens.Theme {
    ThemeResolver.resolve(
      preference: ThemePreference(rawValue: themePreference) ?? .system,
      systemScheme: colorScheme == .dark ? .dark : .light)
  }
}

#Preview {
  ComponentGalleryScreen()
}
