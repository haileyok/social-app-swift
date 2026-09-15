import DesignSystemCore
import SwiftUI

// Re-exported so the app and its test targets reach `NotificationsAccessibility`
// (and the rest of the surface) through `import AppShell` alone, the same way
// they reach `ShellAccessibility` and the login surface. XCUITest bundles are
// built by the project rather than by a package, so they link only the AppShell
// product; the `@_exported` form is also what makes a plain `import
// NotificationsViews` redundant here.
@_exported import NotificationsViews

/**
 The notifications entry point for the debug toolbar.

 Mirrors `AppShell+Login.swift` and `AppShell+Components.swift`: the hook lives
 in its own file so the shell agent's work on the root view and this debug
 surface do not conflict. Nothing here is referenced by the root view by default;
 the five-tab shell and its smoke tests stay untouched while the notifications
 list is reachable from a tab toolbar.

 ```swift
 // A tab's toolbar, alongside the token-gallery and login links:
 NotificationsDebugButton()
 ```
 */
public struct NotificationsDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "bell")
    }
    .accessibilityLabel("Notifications")
    .accessibilityIdentifier(ShellAccessibility.notificationsButton)
    .sheet(isPresented: $isPresented) {
      NotificationsDebugSheet()
    }
  }
}

/**
 The presented notifications list, wrapped in the surface's own `NavigationStack`
 for a title bar and the platform's close affordance.

 The fixture rows are passed explicitly so the debug surface is deterministic: it
 does not depend on a session, a query, or the simulator's stored state, so a
 screenshot or a UI test sees the same list every run.
 */
public struct NotificationsDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      NotificationsSurfaces.notificationsScreen(theme: themePreferenceValue)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close") { dismiss() }
              .accessibilityIdentifier(ShellAccessibility.notificationsCloseButton)
          }
        }
    }
    .accessibilityIdentifier(ShellAccessibility.notificationsSheet)
  }

  /// The stored preference, falling back to `.system` for an unknown value.
  private var themePreferenceValue: ThemePreference {
    ThemePreference(rawValue: themePreference) ?? .system
  }
}

#Preview {
  NotificationsDebugSheet()
}
