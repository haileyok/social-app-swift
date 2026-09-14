import Foundation

/**
 Accessibility identifiers shared by the app and its XCUITest target.

 The UI test bundle links this same package, so both sides read the identifiers
 from one place instead of duplicating string literals. Tab identifiers live on
 `AppTab.accessibilityIdentifier` (RN `testID` parity).
 */
public enum ShellAccessibility {
  /** The root shell view. Sits above the tab bar; the login flow will take it over. */
  public static let root = "app.root"

  /** The debug toolbar button that opens the token gallery. */
  public static let tokenGalleryButton = "app.debug.tokenGallery"

  /** The presented token gallery. */
  public static let tokenGallery = "app.tokenGallery"

  /** Per-screen content container, e.g. `screen.Home`. */
  public static func screen(_ routeName: String) -> String {
    "screen.\(routeName)"
  }
}

/**
 Launch arguments the CI screenshot loop and the UI tests use to put the app in
 a known state without a login.
 */
public enum ShellLaunchArgument {
  /**
   The zero-based tab to select on launch (`-uiTestInitialTab 2`). Read through
   `UserDefaults`, which parses the `-key value` form automatically.
   */
  public static let initialTab = "uiTestInitialTab"

  /**
   Full-screen surface to show for CI screenshot capture (`-uiTestScreen
   tokens|components|...`). Empty/unset means the normal tab shell. New
   capturable screens register in `AppRootView.captureSurface`.
   */
  public static let screen = "uiTestScreen"

  /**
   Theme override for screenshot capture (`-uiTestTheme light|dark|dim`).
   Unset means the user's stored theme preference.
   */
  public static let theme = "uiTestTheme"
}
