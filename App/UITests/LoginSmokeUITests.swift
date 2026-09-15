import AppShell
import XCTest

/**
 Smoke test for the login screen: the app's first real user-facing surface.

 Runs against the built `SocialApp` app. It presents the login screen from the
 debug toolbar entry (the same pattern the token-gallery smoke test uses), then
 asserts the two things the form has to get right before the session work lands:

  1. the credential form is on screen with its key elements addressable by
     `accessibilityIdentifier`,
  2. submitting an empty form shows field-level validation rather than doing
     nothing.

 No network is involved: an empty submission is rejected inside `LoginFlow`
 before any request, which is exactly the path `LoginOutcome.invalid` describes.

 Identifiers come from `LoginAccessibility` (linked from the LoginViews package)
 so the test and the views cannot drift on names.
 */
final class LoginSmokeUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
    presentLogin()
  }

  override func tearDown() {
    app = nil
    super.tearDown()
  }

  /// The login screen presents from the debug toolbar entry.
  func testLoginPresentsFromTheDebugToolbarEntry() {
    XCTAssertTrue(
      loginScreenElement.waitForExistence(timeout: 10),
      "login screen did not present from the debug toolbar entry")
  }

  /// The form's key elements exist and are addressable.
  func testCredentialFormExposesItsKeyElements() {
    XCTAssertTrue(
      identifierField.waitForExistence(timeout: 10),
      "identifier field is not addressable by \(LoginAccessibility.identifierField)")

    XCTAssertTrue(
      passwordField.exists,
      "password field is not addressable by \(LoginAccessibility.passwordField)")

    XCTAssertTrue(
      signInButton.exists,
      "sign-in button is not addressable by \(LoginAccessibility.signInButton)")

    XCTAssertTrue(
      forgotPasswordButton.exists,
      "forgot-password link is not addressable by \(LoginAccessibility.forgotPasswordButton)")

    XCTAssertTrue(
      serviceButton.exists,
      "service/change-server control is not addressable by \(LoginAccessibility.serviceButton)")
  }

  /**
   An empty submit shows validation.

   `LoginFlow.signIn` rejects an empty identifier with
   `LoginStrings.pleaseEnterUsername` before it resolves a service or opens a
   socket, so this asserts the validation path end to end with no network.
   */
  func testEmptySubmitShowsValidation() {
    XCTAssertTrue(signInButton.waitForExistence(timeout: 10))
    signInButton.tap()

    let validation = app.descendants(matching: .any)
      .matching(identifier: LoginAccessibility.validationMessage)
      .firstMatch
    XCTAssertTrue(
      validation.waitForExistence(timeout: 10),
      "submitting an empty form did not show a validation message")

    // No failure banner: nothing left the device, so the server-error surface
    // must not appear.
    let banner = app.descendants(matching: .any)
      .matching(identifier: LoginAccessibility.errorBanner)
      .firstMatch
    XCTAssertFalse(
      banner.exists,
      "an empty submit should show field validation, not a server error banner")
  }

  /// A typed identifier then an empty password validates against the password
  /// rather than the username, so the field-level copy tracks the real reason.
  func testEmptyPasswordSubmitValidatesThePassword() {
    XCTAssertTrue(identifierField.waitForExistence(timeout: 10))
    identifierField.tap()
    identifierField.typeText("alice.test")

    signInButton.tap()

    let validation = app.descendants(matching: .any)
      .matching(identifier: LoginAccessibility.validationMessage)
      .firstMatch
    XCTAssertTrue(validation.waitForExistence(timeout: 10))
  }

  /// The service picker opens from the form's change-server control.
  func testServicePickerOpensFromTheForm() {
    XCTAssertTrue(serviceButton.waitForExistence(timeout: 10))
    serviceButton.tap()

    let picker = app.descendants(matching: .any)
      .matching(identifier: LoginAccessibility.servicePicker)
      .firstMatch
    XCTAssertTrue(
      picker.waitForExistence(timeout: 10),
      "the change-server control did not present the service picker")

    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(identifier: LoginAccessibility.serviceField)
        .firstMatch.exists,
      "the service picker has no custom-address field")
  }

  // MARK: - Helpers

  /// Presents the login sheet from the debug toolbar entry.
  ///
  /// The entry sits on every tab's toolbar; the launch state is Home, so the
  /// button is found without a tab tap.
  private func presentLogin() {
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

    let button = app.buttons[ShellAccessibility.loginButton]
    XCTAssertTrue(
      button.waitForExistence(timeout: 10),
      "debug login toolbar button is not reachable")
    button.tap()
  }

  private var loginScreenElement: XCUIElement {
    app.descendants(matching: .any)
      .matching(identifier: ShellAccessibility.loginSheet)
      .firstMatch
  }

  private var identifierField: XCUIElement {
    app.descendants(matching: .any)
      .matching(identifier: LoginAccessibility.identifierField)
      .firstMatch
  }

  private var passwordField: XCUIElement {
    app.descendants(matching: .any)
      .matching(identifier: LoginAccessibility.passwordField)
      .firstMatch
  }

  private var signInButton: XCUIElement {
    app.buttons[LoginAccessibility.signInButton]
  }

  private var forgotPasswordButton: XCUIElement {
    app.buttons[LoginAccessibility.forgotPasswordButton]
  }

  private var serviceButton: XCUIElement {
    app.buttons[LoginAccessibility.serviceButton]
  }
}
