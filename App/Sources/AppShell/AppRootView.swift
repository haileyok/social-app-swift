import DesignSystem
import DesignSystemCore
import DesignTokens
import SwiftUI
import UIComponents

/**
 The app shell root: five tabs, one `NavigationStack` each.

 Tab titles and accessibility identifiers follow the RN app (`AppTab` documents
 the mapping). The whole shell is wrapped in `.theme(...)` so every screen reads
 the same ALF theme from the environment.

 Until the login/session flow lands (Phase 5) this is also the "login root": it
 is what the app shows with no account. `ShellAccessibility.root` marks it, and
 the UI test asserts a signed-out launch reaches the tab bar rather than a crash.
 */
public struct AppRootView: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @State private var selection: AppTab

  /** Capturable full-screen surface requested via `-uiTestScreen` ("" = tabs). */
  private let captureScreen: String

  /** Theme override from `-uiTestTheme light|dark|dim` (nil = stored preference). */
  private let captureTheme: ThemePreference?

  @Environment(\.colorScheme) private var colorScheme

  /**
   Reads `-uiTestInitialTab N` from the launch arguments (the CI screenshot loop
   passes it to capture a specific tab) and falls back to Home. Also reads the
   screen/theme capture overrides used by the gallery screenshot loop.
   */
  public init() {
    let defaults = UserDefaults.standard
    let index = defaults.integer(forKey: ShellLaunchArgument.initialTab)
    let tabs = AppTab.allCases
    _selection = State(initialValue: tabs.indices.contains(index) ? tabs[index] : .home)
    captureScreen = defaults.string(forKey: ShellLaunchArgument.screen) ?? ""
    captureTheme = defaults.string(forKey: ShellLaunchArgument.theme)
      .flatMap(ThemePreference.init(rawValue:))
  }

  public var body: some View {
    Group {
      switch captureScreen {
      case "tokens":
        TokenGallery(theme: resolvedTheme)
      case "components":
        ComponentGallery(theme: captureTheme ?? activePreference)
      case "composer":
        ComposerSurfaces.composerScreen(theme: captureTheme ?? activePreference)
      case "thread":
        PostThreadSurfaces.threadScreen(theme: captureTheme ?? activePreference)
      case "starterpacks":
        StarterPacksSurfaces.starterPackScreen(theme: captureTheme ?? activePreference)
      case "onboarding":
        OnboardingSurfaces.wizardScreen(theme: captureTheme ?? activePreference)
      case "settings":
        SettingsSurfaces.settingsScreen(theme: captureTheme ?? activePreference)
      default:
        tabView
      }
    }
    .accessibilityIdentifier(ShellAccessibility.root)
    .theme(resolvedTheme)
  }

  /** The normal five-tab shell. */
  private var tabView: some View {
    TabView(selection: $selection) {
      ForEach(AppTab.allCases) { tab in
        TabPlaceholderScreen(tab: tab)
          .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
              .accessibilityIdentifier(tab.accessibilityIdentifier)
          }
          .tag(tab)
      }
    }
  }

  private var activePreference: ThemePreference {
    ThemePreference(rawValue: themePreference) ?? .system
  }

  /**
   Resolves the capture override (if any) or the stored preference against the
   current appearance, so `.system` follows the OS and the explicit names win.
   */
  private var resolvedTheme: DesignTokens.Theme {
    ThemeResolver.resolve(
      preference: captureTheme ?? activePreference,
      systemScheme: colorScheme == .dark ? .dark : .light)
  }
}
