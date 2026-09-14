import Foundation

/// The English source copy for the login flow.
///
/// This is a port of the user-facing strings the RN sign-in screens render
/// (`screens/Login/*.tsx`), reduced to a table of message templates. There is
/// deliberately no i18n framework here: a `LoginViews` package maps these
/// cases onto its own catalogs, and tests assert against the same values the
/// RN screens pass to Lingui.
///
/// Values are Swift interpolations with named parameters, so a caller that
/// needs the final text only has to supply the arguments.
public enum LoginStrings {

  // MARK: - Screen titles and descriptions

  /// `Sign in`
  public static let signInTitle = "Sign in"
  /// `Enter your username and password`
  public static let signInDescription = "Enter your username and password"
  /// `Select from an existing account`
  public static let chooseAccountDescription = "Select from an existing account"
  /// `Forgot Password`
  public static let forgotPasswordTitle = "Forgot Password"
  /// `Let's get your password reset!`
  public static let forgotPasswordDescription = "Let's get your password reset!"
  /// `You can now sign in with your new password.`
  public static let passwordUpdatedDescription = "You can now sign in with your new password."

  // MARK: - Field-level validation

  /// `Please enter your username`
  public static let pleaseEnterUsername = "Please enter your username"
  /// `Please enter your password`
  public static let pleaseEnterPassword = "Please enter your password"
  /// `Please enter a password.`
  public static let pleaseEnterNewPassword = "Please enter a password."
  /// `Your email appears to be invalid.`
  public static let invalidEmail = "Your email appears to be invalid."
  /// `You have entered an invalid code. It should look like XXXXX-XXXXX.`
  public static let invalidResetCode = "You have entered an invalid code. It should look like XXXXX-XXXXX."

  // MARK: - Sign-in failures

  /// `Incorrect username or password`
  public static let incorrectCredentials = "Incorrect username or password"
  /// `Invalid 2FA confirmation code.`
  public static let invalidAuthFactorToken = "Invalid 2FA confirmation code."
  /// `Unable to contact your service. Please check your Internet connection.`
  public static let unableToContactService =
    "Unable to contact your service. Please check your Internet connection."
  /// `This feature is not available while using an App Password. Please sign in with your main password.`
  public static let appPasswordNotAllowed =
    "This feature is not available while using an App Password. Please sign in with your main password."
  /// `Too many attempts. Please wait a moment and try again.`
  public static let rateLimited = "Too many attempts. Please wait a moment and try again."
  /// `We couldn't verify your hosting provider. Check your internet connection.`
  public static let hostingProviderUnverifiable =
    "We couldn't verify your hosting provider. Check your internet connection."
  /// `Please enter a valid server address.`
  public static let invalidServiceUrl = "Please enter a valid server address."

  // MARK: - Two-factor prompt

  /// `2FA Confirmation`
  public static let twoFactorLabel = "2FA Confirmation"
  /// `Check your email for a sign in code and enter it here.`
  public static let twoFactorPrompt = "Check your email for a sign in code and enter it here."

  // MARK: - Choose-account

  /// `Already signed in as @<handle>`
  public static func alreadySignedIn(handle: String) -> String {
    "Already signed in as @\(handle)"
  }

  /// `Signed in as @<handle>`
  public static func signedInAs(handle: String) -> String {
    "Signed in as @\(handle)"
  }

  // MARK: - Hosting provider confirmation

  /// The copy the RN `ConfirmHostingProviderDialog` shows before sending a
  /// password to a non-Bluesky server.
  public static func confirmHostingProvider(host: String) -> String {
    "You are signing in to \(host), which is not operated by Bluesky."
  }
}
