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

 ## Where the session is actually consulted

 Only ``SessionGateView``. A demo launch renders the shell directly and never
 constructs a session, so no screenshot or fixture run can fail because a
 device secret is unreadable in a fresh simulator, and the captured shell is
 exactly the one the app rendered before the gate existed. The `login` capture
 surface behaves the same way: it is the signed-out root, not a bootstrap.
 */
public struct AppRootView: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  private let launch: ShellLaunch

  /** Capturable full-screen surface requested via `-uiTestScreen` ("" = root). */
  private let captureScreen: String

  @State private var selection: AppTab

  @Environment(\.colorScheme) private var colorScheme

  /** Reads the launch arguments the CI screenshot loop and the UI tests pass. */
  public init() {
    let launch = ShellLaunch.current
    self.launch = launch
    self.captureScreen = launch.screen ?? ""
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
        SessionGateView(launch: launch, surface: .loginOnly)
      default:
        // A demo launch is the shell as it was before the session gate: no
        // session is constructed, so nothing here can fail on a fixture run.
        if launch.isDemoLaunch {
          tabView(session: nil)
        } else {
          SessionGateView(launch: launch, surface: .session)
        }
      }
    }
    .accessibilityIdentifier(ShellAccessibility.root)
    .theme(resolvedTheme)
  }

  // MARK: - Roots

  /** The normal five-tab shell. */
  private func tabView(session: AppSession?) -> some View {
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

/**
 The session gate: bootstrap, then whatever root the session settled on.

 This is the only place a normal launch consults the session, and the only place
 a `.task` runs. It owns the session owner for as long as it is mounted, so the
 same store survives the signed-in/signed-out transitions and a sign-out lands
 on the login form without rebuilding anything.

 `surface` exists so the `login` capture surface can render the very same
 ``LoginRootView`` without booting a session at all: the login smoke test then
 touches no stored secret, which is what makes it deterministic on a fresh
 simulator.
 */
private struct SessionGateView: View {
  /** Which root this mount is responsible for. */
  enum Surface {
    /** Bootstrap, then the session's root. */
    case session
    /** The signed-out root, with no bootstrap. */
    case loginOnly
  }

  private let launch: ShellLaunch
  private let surface: Surface

  @State private var session: AppSession
  @State private var sessionState: AppSession.State = .loading
  @State private var selection: AppTab

  @Environment(\.colorScheme) private var colorScheme

  init(launch: ShellLaunch, surface: Surface) {
    self.launch = launch
    self.surface = surface
    _session = State(initialValue: AppSession(launch: launch))
    _selection = State(initialValue: launch.initialTab)
  }

  @ViewBuilder
  var body: some View {
    switch surface {
    case .loginOnly:
      LoginRootView(session: session)
    case .session:
      gate.task { await bootstrap() }
    }
  }

  private var gate: some View {
    Group {
      switch sessionState {
      case .signedIn:
        shell
      case .signedOut:
        LoginRootView(session: session)
      case .loading:
        // Bootstrap is a local read plus (at most) one network refresh, so this
        // is visible only on a cold start.
        launchPlaceholder
      }
    }
  }

  private var shell: some View {
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

  private var launchPlaceholder: some View {
    ProgressView()
      .controlSize(.large)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(resolvedTheme.atomColors.bg)
      .accessibilityIdentifier(ShellAccessibility.rootLoading)
  }

  private var resolvedTheme: DesignTokens.Theme {
    ThemeResolver.resolve(
      preference: launch.theme ?? .system,
      systemScheme: colorScheme == .dark ? .dark : .light)
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
}
