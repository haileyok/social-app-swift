import DesignSystem
import DesignSystemCore
import SwiftUI

// Re-exported so the app and its test targets reach `ComposerAccessibility` (and
// the rest of the composer surface) through `import AppShell` alone, the way
// they reach `ShellAccessibility` and `LoginAccessibility`. The XCUITest bundle
// is built by the project rather than by a package, so it links only the AppShell
// product.
@_exported import ComposerViews

/**
 The composer entry point.

 Mirrors `AppShell+Components.swift` and `AppShell+Login.swift`: the hook lives
 in its own file so the shell agent's work on the root view and this surface do
 not conflict. Nothing here is referenced by the root view by default.

 ```swift
 // Any screen, to present the composer:
 ComposerDebugButton()
 ```

 The screen underneath is fixture-driven (`ComposerDebugView`): it mounts
 `ComposerScreen` over a `ComposerFixtures` state, so the composer is reviewable -
 and screenshot-able - without an account, a backend or a media picker. The
 app's real composer wires the same screen to its own `ComposerState` and
 callbacks; see the `ComposerScreen` initialiser.
 */
public enum ComposerSurfaces {
  /// The composer screen for a fixture surface, themed.
  ///
  /// This is the one function the app shell exposes: the debug button below is a
  /// thin presentation wrapper, and a real hosting screen can call this directly.
  public static func composerScreen(theme: ThemePreference = .system) -> some View {
    ComposerDebugView(theme: theme)
  }

  /// The composer screen pinned to one fixture surface.
  public static func composerScreen(
    surface: ComposerSurface,
    theme: ThemePreference = .system
  ) -> some View {
    ComposerDebugView(surface: surface, theme: theme)
  }
}

/// The shell-level identifiers this hook adds.
///
/// Declared here rather than in `ShellAccessibility.swift` so the hook stays one
/// self-contained file (the shell agent owns that file). Names are dot-scoped on
/// `app.` like the rest of the shell's identifiers.
enum ComposerShellAccessibility {
  /// The toolbar button that presents the composer.
  static let debugButton = "app.debug.composer"
  /// The presented composer screen.
  static let sheet = "app.composer"
}

/**
 The debug toolbar button that presents the composer.

 The stopgap entry point while the shell keeps the 5-tab root and its smoke tests
 untouched, exactly as `LoginDebugButton` is for the login flow.
 */
public struct ComposerDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "square.and.pencil")
    }
    .accessibilityLabel("Composer")
    .accessibilityIdentifier(ComposerShellAccessibility.debugButton)
    .sheet(isPresented: $isPresented) {
      ComposerDebugSheet()
    }
  }
}

/// The presented composer, wrapped in its own `NavigationStack` for a title bar
/// and the platform's close affordance.
public struct ComposerDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      // The screen carries its own cancel control, so the nav bar does not add
      // a second one (and a second `composer.cancel` identifier).
      ComposerDebugView(theme: resolvedTheme, onCancel: { dismiss() })
        .navigationTitle("New post")
        .navigationBarTitleDisplayMode(.inline)
    }
    .theme(resolvedTheme)
    .accessibilityIdentifier(ComposerShellAccessibility.sheet)
  }

  /// The stored preference, falling back to `.system` for an unknown value.
  private var resolvedTheme: ThemePreference {
    ThemePreference(rawValue: themePreference) ?? .system
  }
}

#Preview {
  ComposerDebugSheet()
}
