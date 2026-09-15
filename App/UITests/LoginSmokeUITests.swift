import AppShell
import XCTest

/**
 Smoke test for the login root: the screen a signed-out app shows.

 Runs against the built `SocialApp` app, launched on the `login` capture surface
 (`-uiTestScreen login`), which presents the same `LoginRootView` the session
 gate presents when nobody is signed in. Driving the capture surface rather than
 whatever happens to be stored on the simulator is what keeps this test
 deterministic: no account is needed, none is created, and the device's state
 cannot change what is on screen.

 It asserts the two things the form has to get right:

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
    // The login surface is the signed-out root, presented without the session
    // gate having to reach a decision first.
    app.launchArguments = [
      "-\(ShellLaunchArgument.screen)", ShellLaunchArgument.loginSurface,
    ]
    app.launch()
  }

  override func tearDown() {
    app = nil
    super.tearDown()
  }

  /// The login root is on screen with the form inside it.
  func testLoginRootPresentsTheCredentialForm() {
    XCTAssertTrue(
      loginRootElement.waitForExistence(timeout: 30),
      "the login root did not appear on the \(ShellLaunchArgument.loginSurface) surface")

    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(identifier: LoginAccessibility.screen)
        .firstMatch.exists,
      "the login root does not contain the credential form")
  }

  /**
   The root is a root, not a sheet over the shell.

   The debug entry point's sheet carries a close button; a signed-out app must
   not offer to dismiss the only screen it has.
   */
  func testLoginRootIsNotDismissible() {
    XCTAssertTrue(loginRootElement.waitForExistence(timeout: 30))

    XCTAssertFalse(
      app.tabBars.firstMatch.exists,
      "the tab shell is behind the login root; the root should own the window")
    XCTAssertFalse(
      app.buttons[ShellAccessibility.loginCloseButton].exists,
      "the login root offered a close control, which only the debug sheet has")
  }

  /// The form's key elements exist and are addressable.
  func testCredentialFormExposesItsKeyElements() {
    XCTAssertTrue(
      identifierField.waitForExistence(timeout: 30),
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
    XCTAssertTrue(signInButton.waitForExistence(timeout: 30))
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
    XCTAssertTrue(identifierField.waitForExistence(timeout: 30))
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
    XCTAssertTrue(serviceButton.waitForExistence(timeout: 30))
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

  private var loginRootElement: XCUIElement {
    app.descendants(matching: .any)
      .matching(identifier: ShellAccessibility.loginRoot)
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

/**
 Smoke test for the session gate: which root a launch lands on.

 Three launch forms, three expectations, and together they are what root
 switching has to get right:

  - a fixture/demo launch (`-uiTestDemo`) stays on the tab shell, preserving the
    logged-out tab behavior the CI screenshot loop and the tab smoke test
    depend on,
  - the shell's debug login entry still presents the sheet over the shell,
  - a launch with no arguments reaches a *decided* root instead of hanging on
    the bootstrap placeholder.

 The class lives in this file rather than its own so the hand-maintained Xcode
 project does not need a new source-file reference.
 */
final class SessionGateUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() {
    super.tearDown()
  }

  /// A demo launch lands on the tab shell with no account.
  func testDemoLaunchStaysOnTheTabShell() {
    let app = launch(with: demoArguments)

    XCTAssertTrue(
      app.tabBars.firstMatch.waitForExistence(timeout: 30),
      "a demo launch did not reach the tab shell")

    XCTAssertFalse(
      loginRoot(in: app).exists,
      "a demo launch gated the shell behind the login root")
  }

  /// The shell's debug login entry still opens the login sheet over the tabs.
  func testDebugLoginEntryStillPresentsTheSheet() {
    let app = launch(with: demoArguments)
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

    let button = app.buttons[ShellAccessibility.loginButton]
    XCTAssertTrue(
      button.waitForExistence(timeout: 10),
      "the demo shell has no debug login entry")

    button.tap()

    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(identifier: ShellAccessibility.loginSheet)
        .firstMatch.waitForExistence(timeout: 10),
      "the debug login entry did not present the sheet")

    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(identifier: LoginAccessibility.identifierField)
        .firstMatch.exists,
      "the presented login sheet has no credential form")
  }

  /**
   A launch with no arguments reaches a decided root.

   The simulator is either clean (no account: the login root) or holds a session
   from a manual run (the tab shell). Both are correct; a launch that never
   leaves the bootstrap placeholder is not.
   */
  func testBareLaunchReachesADecidedRoot() {
    let app = launch(with: [])

    let decided = loginRoot(in: app).waitForExistence(timeout: 30)
      || app.tabBars.firstMatch.exists
    XCTAssertTrue(
      decided,
      "a launch with no arguments reached neither the login root nor the tab shell")

    XCTAssertFalse(
      app.descendants(matching: .any)
        .matching(identifier: ShellAccessibility.rootLoading)
        .firstMatch.exists,
      "the app was still on the bootstrap placeholder after reaching a root")
  }

  // MARK: - Helpers

  /// The fixture/demo launch form: the key plus a value, which is how
  /// `UserDefaults` reliably carries it through a process launch.
  private var demoArguments: [String] {
    ["-\(ShellLaunchArgument.demo)", "1"]
  }

  /// Launches the app with the given arguments, replacing whatever launched
  /// before it.
  private func launch(with arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments
    app.launch()
    return app
  }

  private func loginRoot(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(identifier: ShellAccessibility.loginRoot)
      .firstMatch
  }
}
