/**
 The view-owned copy for the app shell.

 This is the shell's strings seam, mirroring `LoginCopy` in `LoginViews`: every
 user-facing string the shell renders is read through one of these static
 members, so swapping them for `String(localized:)` calls is a single-file
 change and no view carries a scattered literal.

 Copy that belongs to a feature stays in that feature's catalog (a login button
 is `LoginCopy`'s, not the shell's); what lives here is shell chrome - the
 account menu the shell owns today, and whatever the shell grows next.
 */
public enum ShellCopy {
  // MARK: - Account menu

  /// The accessibility label of the debug-toolbar account control.
  public static let accountMenuLabel = "Account"

  /// The heading above the account menu's entries.
  public static let accountMenuTitle = "Account"

  /// The menu row naming the signed-in account, e.g. `@alice.test`.
  ///
  /// The leading `@` is deliberate: a handle is one, and the menu reads as the
  /// same "signed in as" line the login chooser uses.
  public static func currentAccount(_ handle: String) -> String {
    "@\(handle)"
  }

  /// The sign-out action.
  public static let signOutAction = "Sign out"

  /// The fallback label when the account has no handle recorded.
  public static let unknownAccount = "Signed in"

  // MARK: - Login root

  /// The title of the signed-out root, which is the sign-in screen itself.
  public static let loginTitle = "Sign in"

  /// The dismiss control on the debug login sheet.
  public static let loginCancelAction = "Close"
}
