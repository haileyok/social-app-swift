import DesignSystem
import DesignSystemCore
import DesignTokens
import SwiftUI

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

  @Environment(\.colorScheme) private var colorScheme

  /**
   Reads `-uiTestInitialTab N` from the launch arguments (the CI screenshot loop
   passes it to capture a specific tab) and falls back to Home.
   */
  public init() {
    let index = UserDefaults.standard.integer(forKey: ShellLaunchArgument.initialTab)
    let tabs = AppTab.allCases
    _selection = State(initialValue: tabs.indices.contains(index) ? tabs[index] : .home)
  }

  public var body: some View {
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
    .accessibilityIdentifier(ShellAccessibility.root)
    .theme(resolvedTheme)
  }

  /**
   Resolves the stored preference against the current appearance, so `.system`
   follows the OS and the explicit names win.
   */
  private var resolvedTheme: DesignTokens.Theme {
    ThemeResolver.resolve(
      preference: ThemePreference(rawValue: themePreference) ?? .system,
      systemScheme: colorScheme == .dark ? .dark : .light)
  }
}
