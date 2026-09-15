import DesignSystemCore
import StarterPacksLogic
import StarterPacksViews
import SwiftUI

// Re-exported so the app and its test targets reach `StarterPackAccessibility`
// (and the rest of the surface) through `import AppShell` alone, the same way
// they reach `ShellAccessibility` and `LoginAccessibility`. XCUITest bundles are
// built by the project rather than by a package, so they link only the AppShell
// product.
@_exported import StarterPacksViews

/**
 The starter-pack entry point for the debug toolbar.

 Mirrors `AppShell+Login.swift`: the hook lives in its own file so the shell
 agent's work on the root view and this debug surface do not conflict. Nothing
 here is referenced by the root view by default - the pack surfaces are mounted
 from a tab toolbar, which leaves the 5-tab root and its smoke tests untouched
 while the feature is reachable:

 ```swift
 // A tab's toolbar, alongside the login and token-gallery links:
 StarterPacksDebugButton()
 ```
 */
public enum StarterPacksSurfaces {
  /**
   The pack fixture screen, themed as the shell themes its other debug surfaces.

   - Parameter theme: the resolved preference, so the gallery follows the debug
     toolbar's theme picker rather than the OS alone.
   */
  public static func starterPackScreen(theme: ThemePreference) -> some View {
    StarterPacksGallery(theme: theme)
      .navigationTitle(StarterPackCopy.screenTitle)
      .navigationBarTitleDisplayMode(.inline)
  }
}

/// The toolbar button that presents the starter-pack fixture gallery.
public struct StarterPacksDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "square.stack.3d.up")
    }
    .accessibilityLabel(StarterPackCopy.screenTitle)
    .accessibilityIdentifier(StarterPackAccessibility.screen)
    .sheet(isPresented: $isPresented) {
      StarterPacksDebugSheet()
    }
  }
}

/**
 The presented gallery, wrapped in its own `NavigationStack` for a title bar and
 the platform's close affordance.

 The theme comes from the same `@AppStorage` key the component gallery reads, so
 the two debug surfaces agree about the active theme.
 */
public struct StarterPacksDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      StarterPacksSurfaces.starterPackScreen(theme: themePreferenceValue)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close") { dismiss() }
          }
        }
    }
  }

  /// The stored preference, falling back to `.system` for an unknown value.
  private var themePreferenceValue: ThemePreference {
    ThemePreference(rawValue: themePreference) ?? .system
  }
}

#Preview {
  StarterPacksDebugSheet()
}
