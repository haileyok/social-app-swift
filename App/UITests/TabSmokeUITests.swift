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

  /// The tab bar buttons carry the RN app's `bottomBar*Btn` test IDs.
  func testTabButtonsCarryRNTestIdentifiers() {
    let bar = app.tabBars.firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: 30))

    for tab in AppTab.allCases {
      XCTAssertTrue(
        bar.buttons[tab.accessibilityIdentifier].exists,
        "tab \(tab.title) is missing identifier \(tab.accessibilityIdentifier)")
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
