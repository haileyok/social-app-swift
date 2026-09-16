import AppShell
import XCTest

/**
 Launch smoke test for the app shell.

 Runs against the built `SocialApp` app (XCUITest launches it by bundle id, so
 this test bundle does not need the app to be signed). It asserts the three
 things the shell has to get right before any feature work lands:

 1. the app launches and shows the root shell,
 2. the tab bar carries the RN app's five tabs, in RN order,
 3. tapping each tab switches the visible screen.

 Tabs are addressed through `AppTab` (linked from the AppShell package) so the
 test and the app cannot drift on names or identifiers.
 */
final class TabSmokeUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    // A bare launch would consult the session gate, and a signed-out
    // simulator would show the login root instead of the tab shell this suite
    // asserts. The demo flag is the documented UI-test launch contract (the
    // same one the session-gate tests use): the tab shell, with no session.
    app.launchArguments = ["-\(ShellLaunchArgument.demo)", "1"]
    app.launch()
  }

  override func tearDown() {
    app = nil
    super.tearDown()
  }

  /// The app launches and the root shell is on screen.
  func testAppLaunchesIntoTheRootShell() {
    XCTAssertTrue(
      app.tabBars.firstMatch.waitForExistence(timeout: 30),
      "app did not present the root shell (no tab bar) within 30s")

    XCTAssertTrue(
      rootShellElement.exists,
      "root shell view did not expose identifier \(ShellAccessibility.root)")
  }

  /// The tab bar has exactly the five RN tabs, in the RN order.
  func testTabBarExposesTheFiveRNTabs() {
    let bar = app.tabBars.firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: 30))

    XCTAssertEqual(bar.buttons.count, AppTab.allCases.count)

    for (offset, tab) in AppTab.allCases.enumerated() {
      let button = tabButton(for: tab)
      XCTAssertTrue(
        button.exists,
        "tab \(offset) (\(tab.title)) is missing from the tab bar")
    }
  }

  /// Every tab bar button is addressable, and each tab's screen carries its
  /// identifier.
  ///
  /// SwiftUI does not propagate an `accessibilityIdentifier` set inside
  /// `.tabItem` down to the `UITabBarButton` (verified on iOS 26: the buttons
  /// expose only their label), so the RN `bottomBar*Btn` identifiers are applied
  /// on a best-effort basis there and the tab bar is addressed by the RN label
  /// instead. The identifiers are asserted where they *do* land: on the tab's
  /// screen container, which is what a test taps through to reach content.
  func testTabBarButtonsAreAddressableAndScreensCarryIdentifiers() {
    let bar = app.tabBars.firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: 30))

    for tab in AppTab.allCases {
      let button = tabButton(for: tab)
      XCTAssertTrue(
        button.exists,
        "tab \(tab.title) is not addressable by identifier or label")

      // Selecting the tab must reveal its identified screen container.
      button.tap()
      let screen = app.descendants(matching: .any)
        .matching(identifier: ShellAccessibility.screen(tab.routeName))
        .firstMatch
      XCTAssertTrue(
        screen.waitForExistence(timeout: 10),
        "tab \(tab.title) did not expose \(ShellAccessibility.screen(tab.routeName))")
    }
  }

  /// Every tab is reachable and swaps the visible screen.
  func testSwitchingTabsChangesTheVisibleScreen() {
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

    // Launch state: Home.
    XCTAssertTrue(
      app.navigationBars["Home"].waitForExistence(timeout: 10),
      "expected the Home screen at launch")

    for tab in AppTab.allCases {
      let button = tabButton(for: tab)
      XCTAssertTrue(button.exists, "tab \(tab.title) is not in the tab bar")
      button.tap()

      XCTAssertTrue(
        app.navigationBars[tab.title].waitForExistence(timeout: 10),
        "tapping \(tab.title) did not show the \(tab.title) screen")
    }
  }

  /// The image-composer fixture exposes every attachment and missing-alt guidance.
  func testImageComposerExposesAttachmentsAndAltTextGuidance() {
    app.terminate()
    let composerApp = XCUIApplication()
    composerApp.launchArguments = [
      "-\(ShellLaunchArgument.screen)", "composer",
      "-\(ComposerSurfaces.variantArgument)", "images",
    ]
    composerApp.launch()

    XCTAssertTrue(
      composerApp.descendants(matching: .any)
        .matching(identifier: "composer.image.image-0")
        .firstMatch
        .waitForExistence(timeout: 30),
      "image composer fixture did not expose its first attachment")
    XCTAssertTrue(
      composerApp.descendants(matching: .any)
        .matching(identifier: "composer.image.image-1")
        .firstMatch.exists,
      "second fixture image is missing")
    XCTAssertTrue(
      composerApp.descendants(matching: .any)
        .matching(identifier: "composer.image.altHelp")
        .firstMatch.exists,
      "missing-alt guidance is not exposed")
  }

  /// The token gallery stays reachable from the shell toolbar (AC.7 surface).
  func testTokenGalleryIsReachableFromTheHomeToolbar() {
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

    let galleryButton = app.buttons[ShellAccessibility.tokenGalleryButton]
    XCTAssertTrue(
      galleryButton.waitForExistence(timeout: 10),
      "debug token-gallery toolbar button is not reachable")
    galleryButton.tap()

    XCTAssertTrue(
      galleryElement.waitForExistence(timeout: 10),
      "tapping the debug button did not present the token gallery")
  }

  // MARK: - Helpers

  /**
   The tab bar button for a tab, addressed by its RN test ID and falling back to
   its label. The label fallback keeps the smoke test meaningful if a future
   SwiftUI release stops propagating identifiers set inside `.tabItem`.
   */
  private func tabButton(for tab: AppTab) -> XCUIElement {
    let bar = app.tabBars.firstMatch
    let byIdentifier = bar.buttons[tab.accessibilityIdentifier]
    if byIdentifier.exists {
      return byIdentifier
    }
    return bar.buttons[tab.title]
  }

  /**
   The root shell view. `accessibilityIdentifier` on a container surfaces as a
   generic element, so the lookup is not narrowed to a single element type.
   */
  private var rootShellElement: XCUIElement {
    app.descendants(matching: .any).matching(identifier: ShellAccessibility.root).firstMatch
  }

  private var galleryElement: XCUIElement {
    app.descendants(matching: .any).matching(identifier: ShellAccessibility.tokenGallery).firstMatch
  }
}
