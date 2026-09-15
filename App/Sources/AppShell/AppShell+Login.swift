import DesignSystem
import DesignSystemCore
import LoginLogic
import SwiftUI

// Re-exported so the app and its test targets reach `LoginAccessibility` (and
// the rest of the surface) through `import AppShell` alone, the same way they
// reach `ShellAccessibility`. XCUITest bundles are built by the project rather
// than by a package, so they link only the AppShell product.
@_exported import LoginViews

/**
 The signed-out root: the sign-in screen, presented full-screen.

 This is the real login path - no sheet, no debug affordance - so the login
 smoke test drives exactly what a signed-out user gets. A success hands the
 account to the session, which switches the root to the tab shell; the flow has
 already recorded the account and its tokens in the session store by then, so
 the root only has to follow.

 The view model is created once, in `init`, from the session's own flow: a
 model rebuilt on every render would re-register its listener and drop the
 password the user had typed.
 */
public struct LoginRootView: View {
  private let session: AppSession

  @State private var viewModel: LoginViewModel

  @MainActor
  public init(session: AppSession) {
    self.session = session
    _viewModel = State(initialValue: LoginViewModel(flow: session.makeLoginFlow()))
  }

  public var body: some View {
    VStack(spacing: 0) {
      if let diagnosis = session.startDiagnosis {
        // Restart diagnostics: why the last launch landed on this screen.
        // Temporary scaffolding while the restart path is being hardened;
        // remove once resume is provably stable.
        Text(diagnosis)
          .font(.caption2)
          .foregroundStyle(.red)
          .padding(.horizontal, Spacing.md)
          .padding(.top, Spacing.xs)
          .lineLimit(4)
          .accessibilityIdentifier("start-diagnosis")
      }
      LoginScreen(
        viewModel: viewModel,
        onSignedIn: { account in
          Task { await session.adoptSignedInAccount(account) }
        },
        onForgotPassword: { _ in }
      )
    }
    // A container identifier for the signed-out root. It is a marker for
    // screenshots and accessibility review rather than an assertion target: the
    // UI test identifies the root by what it does not have (the shell's tab bar,
    // the sheet's close control) plus the credential form it does, because a
    // container identifier on a ScrollView-backed screen is not reliably
    // exposed to XCUITest.
    .accessibilityIdentifier(ShellAccessibility.loginRoot)
  }
}

/**
 The login entry point for the debug toolbar.

 Mirrors `AppShell+Components.swift`: the hook lives in its own file so the
 shell's root work and this debug surface do not conflict. The toolbar shows it
 only while nothing is signed in (see `ShellAccountControl`), so a real session
 gets the account menu instead.

 ```swift
 // A tab's toolbar, alongside the token-gallery link:
 LoginDebugButton(session: session)
 ```
 */
public struct LoginDebugButton: View {
  private let session: AppSession?

  @State private var isPresented = false

  public init(session: AppSession? = nil) {
    self.session = session
  }

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "person.crop.circle")
    }
    .accessibilityLabel(ShellCopy.loginTitle)
    .accessibilityIdentifier(ShellAccessibility.loginButton)
    .sheet(isPresented: $isPresented) {
      LoginDebugSheet(session: session)
    }
  }
}

/**
 The presented login screen, wrapped in its own `NavigationStack` for a title bar
 and the platform's close affordance.

 `showsStoredAccounts` is off so the debug entry point always lands on the
 credential form: the smoke test asserts the form's fields exist, and what
 happens to be stored on the simulator's device must not change that. A success
 is adopted by the session and the sheet closes itself.
 */
public struct LoginDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  private let session: AppSession?

  @State private var viewModel: LoginViewModel

  @MainActor
  public init(session: AppSession? = nil) {
    self.session = session
    _viewModel = State(
      initialValue: LoginViewModel(
        flow: session?.makeLoginFlow() ?? LoginFlow()))
  }

  public var body: some View {
    NavigationStack {
      LoginScreen(
        viewModel: viewModel,
        showsStoredAccounts: false,
        onSignedIn: { account in
          Task {
            await session?.adoptSignedInAccount(account)
            dismiss()
          }
        }
      )
      .navigationTitle(LoginStrings.signInTitle)
      .navigationBarTitleDisplayMode(.inline)
      .theme(ThemePreference(rawValue: themePreference) ?? .system)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(ShellCopy.loginCancelAction) { dismiss() }
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
