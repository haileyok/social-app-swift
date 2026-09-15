import LoginLogic

/// The view-owned copy for the login screens, keyed by ``LoginMessageID``.
///
/// This is the seam a String Catalog replaces later: every user-facing string on
/// a login screen is read through one of these static members, so swapping them
/// for `String(localized:)` calls is a single-file change and no view carries a
/// scattered literal.
///
/// The failure copy deliberately defers to `LoginError.message` rather than
/// restating it: `LoginLogic` already holds the RN-sourced English text and is
/// the single source of truth for it, so a reworded message never has to be
/// fixed in two packages. The catalog adds only the strings the logic layer has
/// no reason to know about (button labels, field placeholders, screen chrome).
public enum LoginCopy {
  // MARK: - Screen chrome

  /// The sign-in screen's title.
  public static let screenTitle = LoginStrings.signInTitle
  /// The sign-in screen's supporting line.
  public static let screenDescription = LoginStrings.signInDescription
  /// The title of the stored-account chooser.
  public static let chooseAccountTitle = LoginStrings.chooseAccountDescription

  // MARK: - Fields

  /// The identifier field's placeholder.
  public static let identifierPlaceholder = "Username or email address"
  /// The identifier field's accessibility label.
  public static let identifierLabel = "Username or email address"
  /// The password field's placeholder.
  public static let passwordPlaceholder = "Password"
  /// The password field's accessibility label.
  public static let passwordLabel = "Password"
  /// The 2FA code field's placeholder.
  public static let authFactorPlaceholder = "Confirmation code"
  /// The reset-code field's placeholder.
  public static let resetCodePlaceholder = "Reset code"
  /// The new-password field's placeholder.
  public static let newPasswordPlaceholder = "New password"
  /// The email field's placeholder.
  public static let emailPlaceholder = "Email address"
  /// The custom-server field's placeholder.
  public static let serverPlaceholder = "Server address"

  // MARK: - Actions

  /// The primary submit button on the sign-in form.
  public static let signInAction = "Sign in"
  /// The link into the forgot-password journey.
  public static let forgotPasswordAction = "Forgot password?"
  /// The retry button on a failed sign-in.
  public static let retryAction = "Retry"
  /// The submit button on the 2FA sheet.
  public static let confirmAction = "Confirm"
  /// The dismiss button on a sheet.
  public static let cancelAction = "Cancel"
  /// The "chosen server" affordance that opens the service picker.
  public static let changeServerAction = "Change server"
  /// The default-server row in the picker.
  public static let defaultServerAction = "Bluesky (bsky.social)"
  /// The custom-server submit button.
  public static let connectToServerAction = "Connect to server"
  /// The request-reset submit button.
  public static let requestResetAction = "Request reset code"
  /// The set-password submit button.
  public static let updatePasswordAction = "Update password"
  /// The "done" button on the password-updated screen.
  public static let backToSignInAction = "Back to sign in"
  /// Resuming a stored account.
  public static let resumeAccountAction = "Resume"
  /// Forgetting a stored account.
  public static let forgetAccountAction = "Forget"

  // MARK: - Status

  /// The label above the chosen service address.
  public static let serviceLabel = "Server"
  /// The "checking the server" preflight status.
  public static let checkingServer = "Checking server…"
  /// The preflight success status.
  public static func connectedToServer(_ host: String) -> String {
    "Connected to \(host)"
  }
  /// The empty stored-accounts state.
  public static let noStoredAccounts = "No accounts on this device yet."
  /// The signed-in success line.
  public static let signedInTitle = "Signed in"

  // MARK: - Failure mapping

  /// The user-facing copy for a sign-in failure.
  ///
  /// `LoginError.message` is already the RN-sourced English; the catalog exists
  /// so this indirection is one edit away from `String(localized:)`.
  public static func message(for error: LoginError) -> String { error.message }

  /// The user-facing copy for a password-reset failure.
  public static func message(for error: PasswordResetError) -> String { error.message }

  /// The user-facing copy for a service-preflight failure.
  public static func message(for error: ServiceResolutionError) -> String { error.message }
}
