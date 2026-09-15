import DesignSystem
import DesignSystemCore
import DesignTokens
import SwiftUI
import UIComponents

/**
 The app root: it picks a root from the session state.

 Two roots, one view. With an account the shell is the five-tab `TabView`; with
 no account it is the sign-in screen, full-screen, from `LoginViews`. What
 decides between them is ``AppSession``, and what the shell shows afterwards is
 whatever the session reports - including a session that expires while the app
 is open, which sends the user back to the form rather than leaving the tab
 shell rendering account-scoped content with dead tokens.

 ## Capture surfaces

 `-uiTestScreen tokens|components|login` still swaps in a full-screen surface
 inside the shell's theme, unchanged, and the login surface is the one the login
 smoke test drives. `-uiTestInitialTab N`/`-uiTestDemo` mark a *demo launch*
 (see ``ShellLaunch/isDemoLaunch``): the CI screenshot loop and the UI tests run
 with no account, and a demo launch deliberately keeps the tab shell they have
 always captured instead of gating it behind a sign-in form no run can pass.
 */
public struct AppRootView: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  private let launch: ShellLaunch

  /// The session owner: created here, so it lives exactly as long as the root.
  @State private var session: AppSession

  /// The session state, mirrored so SwiftUI re-reads the root on a transition.
  @State private var sessionState: AppSession.State = .loading

  @State private var selection: AppTab

  /** Capturable full-screen surface requested via `-uiTestScreen` ("" = root). */
  private let captureScreen: String

  @Environment(\.colorScheme) private var colorScheme

  /**
   Reads the launch arguments (the CI screenshot loop passes them to capture a
   specific surface or tab) and builds the session owner over them.
   */
  public init() {
    let launch = ShellLaunch.current
    let session = AppSession(launch: launch)
    self.launch = launch
    self.captureScreen = launch.screen ?? ""
    _session = State(initialValue: session)
    _selection = State(initialValue: launch.initialTab)
  }

  public var body: some View {
    Group {
      switch captureScreen {
      case "tokens":
        TokenGallery(theme: resolvedTheme)
      case "components":
        ComponentGallery(theme: launch.theme ?? activePreference)
      case ShellLaunchArgument.loginSurface:
        LoginRootView(session: session)
      default:
        root
      }
    }
    .accessibilityIdentifier(ShellAccessibility.root)
    .theme(resolvedTheme)
    .task { await bootstrap() }
  }

  /**
   Registers the state listener and starts the session.

   A named method rather than a closure body so the listener is created on the
   main actor regardless of how the `task` modifier's closure is isolated, and so
   the listener is in place *before* bootstrap can change the state.
   */
  @MainActor
  private func bootstrap() async {
    session.addListener { state in
      sessionState = state
    }
    await session.start()
  }

  // MARK: - Roots

  /** The root the session state selected. */
  @ViewBuilder
  private var root: some View {
    switch sessionState {
    case .signedIn:
      tabView
    case .signedOut:
      // A demo launch has no account to show and no credentials to sign in
      // with, so the session gate steps aside and the shell stays reachable.
      if launch.isDemoLaunch {
        tabView
      } else {
        LoginRootView(session: session)
      }
    case .loading:
      // Bootstrap is a local read plus (at most) one network refresh, so this
      // is visible only on a cold start. A demo launch skips it entirely: the
      // screenshot loop must never capture a spinner.
      if launch.isDemoLaunch {
        tabView
      } else {
        launchPlaceholder
      }
    }
  }

  /** The normal five-tab shell. */
  private var tabView: some View {
    TabView(selection: $selection) {
      ForEach(AppTab.allCases) { tab in
        TabPlaceholderScreen(tab: tab, session: session)
          .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
              .accessibilityIdentifier(tab.accessibilityIdentifier)
          }
          .tag(tab)
      }
    }
  }

  /** Shown while the session bootstrap is in flight. */
  private var launchPlaceholder: some View {
    ProgressView()
      .controlSize(.large)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(resolvedTheme.atomColors.bg)
      .accessibilityIdentifier(ShellAccessibility.rootLoading)
  }

  // MARK: - Theme

  private var activePreference: ThemePreference {
    ThemePreference(rawValue: themePreference) ?? .system
  }

  /**
   Resolves the capture override (if any) or the stored preference against the
   current appearance, so `.system` follows the OS and the explicit names win.
   */
  private var resolvedTheme: DesignTokens.Theme {
    ThemeResolver.resolve(
      preference: launch.theme ?? activePreference,
      systemScheme: colorScheme == .dark ? .dark : .light)
  }
}
