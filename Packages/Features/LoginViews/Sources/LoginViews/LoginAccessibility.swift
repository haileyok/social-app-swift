/**
 Accessibility identifiers for the login screens.

 The XCUITest target links this package, so the app and the test read the same
 constants instead of duplicating string literals - the same arrangement
 `ShellAccessibility` uses for the shell. Names are dot-scoped (`login.*`) so a
 `descendants(matching:).matching(identifier:)` lookup cannot collide with the
 shell's `app.*` identifiers.
 */
public enum LoginAccessibility {
  /// The sign-in screen's content container.
  public static let screen = "login.screen"
  /// The identifier (username/email) text field.
  public static let identifierField = "login.identifier"
  /// The password secure text field.
  public static let passwordField = "login.password"
  /// The primary sign-in button.
  public static let signInButton = "login.signIn"
  /// The field-level validation message.
  public static let validationMessage = "login.validation"
  /// The failure banner that renders `LoginError.message`.
  public static let errorBanner = "login.error"
  /// The control showing the current server address.
  public static let serviceButton = "login.service"
  /// The forgot-password link.
  public static let forgotPasswordButton = "login.forgotPassword"

  /// The presented service picker.
  public static let servicePicker = "login.servicePicker"
  /// The custom server-address field inside the picker.
  public static let serviceField = "login.servicePicker.field"
  /// The "use the default server" row inside the picker.
  public static let defaultServiceOption = "login.servicePicker.default"
  /// The custom-server connect button inside the picker.
  public static let connectServiceButton = "login.servicePicker.connect"
  /// The picker's preflight status/error line.
  public static let serviceStatus = "login.servicePicker.status"

  /// The presented 2FA sheet.
  public static let authFactorSheet = "login.authFactor"
  /// The 2FA code field.
  public static let authFactorField = "login.authFactor.field"
  /// The 2FA confirm button.
  public static let authFactorSubmit = "login.authFactor.submit"

  /// The stored-account chooser.
  public static let chooseAccount = "login.chooseAccount"
  /// The resume control for one stored account, suffixed by its DID.
  public static func resumeAccount(_ did: String) -> String { "login.account.resume.\(did)" }
  /// The forget control for one stored account, suffixed by its DID.
  public static func forgetAccount(_ did: String) -> String { "login.account.forget.\(did)" }

  /// The request-reset screen.
  public static let forgotPasswordScreen = "login.forgotPassword.screen"
  /// The reset email field.
  public static let resetEmailField = "login.forgotPassword.email"
  /// The request-reset submit button.
  public static let requestResetButton = "login.forgotPassword.submit"
  /// The set-new-password screen.
  public static let setNewPasswordScreen = "login.setNewPassword.screen"
  /// The reset code field.
  public static let resetCodeField = "login.setNewPassword.code"
  /// The new password field.
  public static let newPasswordField = "login.setNewPassword.password"
  /// The set-password submit button.
  public static let updatePasswordButton = "login.setNewPassword.submit"
  /// The password-updated confirmation screen.
  public static let passwordUpdatedScreen = "login.passwordUpdated"
}
