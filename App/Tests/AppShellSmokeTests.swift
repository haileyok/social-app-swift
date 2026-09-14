import AppShell
import XCTest

/**
 Smoke test for `AppShell`'s pure (non-UI) surface.

 This target is the repo's "unit-ish" tier: it links the app's package but has
 no view-rendering assertions, so it stays fast and can grow to cover shell
 state (tab selection, launch-argument parsing) without a running simulator.
 The heavy SwiftUI rendering paths are covered by the package's own macOS-CI
 tests and by the UI test target.
 */
final class AppShellSmokeTests: XCTestCase {
  func testShellExposesFiveTabsInRNOrder() {
    XCTAssertEqual(AppTab.allCases.map(\.routeName), [
      "Home", "Search", "Messages", "Notifications", "Profile",
    ])
  }

  func testTabLabelsMatchTheRNBottomBar() {
    // `Messages` is the route; `Chat` is what the RN bottom bar labels it.
    XCTAssertEqual(AppTab.messages.routeName, "Messages")
    XCTAssertEqual(AppTab.messages.title, "Chat")
    XCTAssertEqual(
      AppTab.allCases.map(\.title),
      ["Home", "Search", "Chat", "Notifications", "Profile"])
  }

  func testTabAccessibilityIdentifiersMatchRNTestIDs() {
    XCTAssertEqual(
      AppTab.allCases.map(\.accessibilityIdentifier),
      [
        "bottomBarHomeBtn", "bottomBarSearchBtn", "bottomBarMessagesBtn",
        "bottomBarNotificationsBtn", "bottomBarProfileBtn",
      ])
  }

  func testTabIndicesAreStableForLaunchArguments() {
    XCTAssertEqual(AppTab.allCases.map(\.index), [0, 1, 2, 3, 4])
    XCTAssertEqual(AppTab.home.index, 0)
    XCTAssertEqual(AppTab.profile.index, 4)
  }

  func testEveryTabHasDistinctIdentifierAndIcon() {
    XCTAssertEqual(Set(AppTab.allCases.map(\.accessibilityIdentifier)).count, AppTab.allCases.count)
    XCTAssertEqual(Set(AppTab.allCases.map(\.systemImage)).count, AppTab.allCases.count)
  }

  func testScreenIdentifiersAreNamespacedByRoute() {
    XCTAssertEqual(ShellAccessibility.screen("Home"), "screen.Home")
    XCTAssertEqual(ShellAccessibility.screen("Messages"), "screen.Messages")
  }
}
