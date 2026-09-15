import DesignSystem
import DesignSystemCore
import LoginLogic
import SwiftUI

// Re-exported so the app and its test targets reach `LoginAccessibility` (and
// the rest of the surface) through `import AppShell` alone, the same way they
// reach `ShellAccessibility`. XCUITest bundles are built by the project rather
// than by a package, so they link only the AppShell product. The `@_exported`
// form is also what makes the plain `import LoginViews` redundant above.
@_exported import LoginViews

/**
 The login entry point for the debug toolbar.

 Mirrors `AppShell+Components.swift`: the hook lives in its own file so the shell
 agent's work on the root view and this debug surface do not conflict. Nothing
 here is referenced by the root view by default - the login flow is presented as
 a sheet from a tab toolbar, which keeps the 5-tab root and its smoke tests
 untouched while the first real screen is reachable.

 ```swift
 // A tab's toolbar, alongside the token-gallery link:
 LoginDebugButton()
 ```
 */
public struct LoginDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "person.crop.circle")
    }
    .accessibilityLabel("Login")
    .accessibilityIdentifier(ShellAccessibility.loginButton)
    .sheet(isPresented: $isPresented) {
      LoginDebugSheet()
    }
  }
}

/**
 The presented login screen, wrapped in its own `NavigationStack` for a title bar
 and the platform's close affordance.

 `showsStoredAccounts` is off so the debug entry point always lands on the
 credential form: the smoke test asserts the form's fields exist, and what
 happens to be stored on the simulator's device must not change that.
 */
public struct LoginDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      LoginScreen(showsStoredAccounts: false)
        .navigationTitle(LoginStrings.signInTitle)
      .navigationBarTitleDisplayMode(.inline)
      .theme(ThemePreference(rawValue: themePreference) ?? .system)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
            .accessibilityIdentifier(ShellAccessibility.loginCloseButton)
        }
      }
    }
    .accessibilityIdentifier(ShellAccessibility.loginSheet)
  }
}

#Preview {
  LoginDebugSheet()
}
