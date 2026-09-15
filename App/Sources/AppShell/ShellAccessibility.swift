import Foundation

/**
 Accessibility identifiers shared by the app and its XCUITest target.

 The UI test bundle links this same package, so both sides read the identifiers
 from one place instead of duplicating string literals. Tab identifiers live on
 `AppTab.accessibilityIdentifier` (RN `testID` parity).
 */
public enum ShellAccessibility {
  /** The root shell view: whichever root the session state selected. */
  public static let root = "app.root"

  /** The debug toolbar button that opens the token gallery. */
  public static let tokenGalleryButton = "app.debug.tokenGallery"

  /** The presented token gallery. */
  public static let tokenGallery = "app.tokenGallery"

  /**
   The signed-out root: the login screen presented full-screen.

   Distinct from `loginSheet` because it is a *root*, not a presentation: the
   UI test asserts that a launched-with-no-account app lands here, while the
   sheet identifier marks the debug entry point's presentation on top of the
   shell.
   */
  public static let loginRoot = "app.root.login"

  /** The debug toolbar button that presents the login screen over the shell. */
  public static let loginButton = "app.debug.login"

  /** The login screen presented as a sheet over the shell. */
  public static let loginSheet = "app.login"

  /** The login sheet's dismiss control. */
  public static let loginCloseButton = "app.login.close"

  /** The placeholder shown while the session bootstrap is in flight. */
  public static let rootLoading = "app.root.loading"

  /** The debug toolbar button that opens the account menu. */
  public static let accountButton = "app.debug.account"

  /** The account menu's contents (handle row + sign-out). */
  public static let accountMenu = "app.accountMenu"

  /** The row naming the signed-in account inside the account menu. */
  public static let accountHandle = "app.accountMenu.handle"

  /** The sign-out control inside the account menu. */
  public static let signOutButton = "app.accountMenu.signOut"

  /** Per-screen content container, e.g. `screen.Home`. */
  public static func screen(_ routeName: String) -> String {
    "screen.\(routeName)"
  }
}

/**
 Launch arguments the CI screenshot loop and the UI tests use to put the app in
 a known state without a login.

 `ShellLaunch` reads these; nothing else should.
 */
public enum ShellLaunchArgument {
  /**
   The zero-based tab to select on launch (`-uiTestInitialTab 2`). Read through
   `UserDefaults`, which parses the `-key value` form automatically.

   Passing it also marks the launch as a demo launch (see
   ``ShellLaunchArgument/demo``).
   */
  public static let initialTab = "uiTestInitialTab"

  /**
   Full-screen surface to show for CI screenshot capture (`-uiTestScreen
   tokens|components|login|...`). Empty/unset means the normal tab shell. New
   capturable surfaces register in `AppRootView`'s capture switch.
   */
  public static let screen = "uiTestScreen"

  /**
   The `-uiTestScreen` value that presents the login screen full-screen, which
   is the surface the login smoke test drives.
   */
  public static let loginSurface = "login"

  /**
   Theme override for screenshot capture (`-uiTestTheme light|dark|dim`).
   Unset means the user's stored theme preference.
   */
  public static let theme = "uiTestTheme"

  /**
   A bare flag (`-uiTestDemo`) that puts the app into its fixture/demo session
   state: the tab shell with no account, which is exactly what the app showed
   before the session gate landed.

   The CI screenshot loop does not pass it - it passes `-uiTestInitialTab`,
   which `ShellLaunch` treats as the same request. It exists for runs that want
   the signed-out shell without pinning a tab.
   */
  public static let demo = "uiTestDemo"
}
