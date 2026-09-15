import AppShell
import XCTest

/**
 Smoke test for `AppShell`'s pure (non-UI) surface.

 This target is the repo's "unit-ish" tier: it links the app's package but has
 no view-rendering assertions, so it stays fast and can grow to cover shell
 state (tab selection, launch-argument parsing, session bootstrap) without a
 running simulator. The heavy SwiftUI rendering paths are covered by the
 package's own macOS-CI tests and by the UI test target.
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

  /**
   The RN `testID`s are still the source of truth for the tab bar, but iOS does
   not deliver them to `UITabBarButton` (SwiftUI drops identifiers set inside
   `.tabItem`), so the UI test addresses buttons by the RN label and asserts the
   identifiers on each tab's screen container. The list is kept (and tested) so
   the mapping is one edit away if a future SwiftUI starts propagating them.
   */
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

  /**
   The two roots carry distinct identifiers, and the login *root* is not the
   login *sheet*: the UI tests assert different things about each.
   */
  func testRootIdentifiersAreDistinct() {
    XCTAssertEqual(ShellAccessibility.root, "app.root")
    XCTAssertEqual(ShellAccessibility.loginRoot, "app.root.login")
    XCTAssertEqual(ShellAccessibility.loginSheet, "app.login")
    XCTAssertNotEqual(ShellAccessibility.loginRoot, ShellAccessibility.loginSheet)
  }
}

/**
 Launch-argument parsing.

 The CI screenshot loop depends on `-uiTestInitialTab` and `-uiTestScreen`, so
 these tests pin the exact behaviour the loop relies on, and the demo-launch rule
 that keeps the shell reachable with no account.
 */
final class ShellLaunchTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "shell.launch.tests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testNoArgumentsMeansHomeAndNoCaptureSurface() {
    let launch = ShellLaunch.read(from: defaults)

    XCTAssertEqual(launch.initialTab, .home)
    XCTAssertNil(launch.screen)
    XCTAssertNil(launch.themeName)
    XCTAssertFalse(launch.hasTabArgument)
    XCTAssertFalse(launch.isDemoArgument)
    XCTAssertFalse(launch.isDemoLaunch)
  }

  func testInitialTabArgumentSelectsTheTab() {
    defaults.set(2, forKey: ShellLaunchArgument.initialTab)

    let launch = ShellLaunch.read(from: defaults)

    XCTAssertEqual(launch.initialTab, .messages)
    XCTAssertTrue(launch.hasTabArgument)
  }

  func testOutOfRangeInitialTabFallsBackToHome() {
    defaults.set(99, forKey: ShellLaunchArgument.initialTab)

    XCTAssertEqual(ShellLaunch.read(from: defaults).initialTab, .home)
  }

  func testScreenAndThemeArgumentsAreRead() {
    defaults.set(ShellLaunchArgument.loginSurface, forKey: ShellLaunchArgument.screen)
    defaults.set("dim", forKey: ShellLaunchArgument.theme)

    let launch = ShellLaunch.read(from: defaults)

    XCTAssertEqual(launch.screen, ShellLaunchArgument.loginSurface)
    // Asserted through the raw name: this bundle links only `AppShell`, so
    // binding the `ThemePreference` value itself would not resolve (see
    // `AppSessionTests`).
    XCTAssertEqual(launch.themeName, "dim")
  }

  func testEmptyScreenArgumentIsTreatedAsUnset() {
    defaults.set("", forKey: ShellLaunchArgument.screen)

    XCTAssertNil(ShellLaunch.read(from: defaults).screen)
  }

  /// The screenshot loop pins a tab with no account; that must keep landing on
  /// the tab shell rather than the login root.
  func testInitialTabArgumentImpliesADemoLaunch() {
    defaults.set(0, forKey: ShellLaunchArgument.initialTab)

    XCTAssertTrue(ShellLaunch.read(from: defaults).isDemoLaunch)
  }

  /// The gallery loop captures full-screen surfaces; those are demo launches
  /// too, so the capture surfaces are what a CI run screenshots.
  func testScreenArgumentImpliesADemoLaunch() {
    defaults.set("tokens", forKey: ShellLaunchArgument.screen)

    XCTAssertTrue(ShellLaunch.read(from: defaults).isDemoLaunch)
  }

  func testDemoFlagImpliesADemoLaunch() {
    defaults.set(true, forKey: ShellLaunchArgument.demo)

    let launch = ShellLaunch.read(from: defaults)

    XCTAssertTrue(launch.isDemoArgument)
    XCTAssertTrue(launch.isDemoLaunch)
    XCTAssertEqual(launch.initialTab, .home)
  }
}

/**
 The session owner's settle behaviour.

 Only the no-account path is asserted: it needs no network, and it is the path a
 fresh simulator takes, which is what the UI tests run against.
 */
@MainActor
final class AppSessionTests: XCTestCase {
  /**
   Bootstrap with no stored account.

   The assertions deliberately stay on `AppShell`'s own surface (`isSignedIn`,
   `currentHandle`, and the state's `String(describing:)`) rather than reading
   the associated `PersistedAccount`: this test bundle links only the `AppShell`
   product, so binding a `Persistence` type here would not resolve at link time.
   */
  func testASessionWithNoStoredAccountSettlesSignedOut() async {
    let session = AppSession.withStorage(directory: temporaryDirectory())

    await session.start()

    XCTAssertFalse(session.isSignedIn)
    XCTAssertNil(session.currentHandle)
    XCTAssertEqual(String(describing: session.state), "signedOut")
  }

  /// Bootstrap is idempotent: a view that re-runs its task must not start a
  /// second resume.
  func testStartIsIdempotent() async {
    let session = AppSession.withStorage(directory: temporaryDirectory())

    await session.start()
    await session.start()

    XCTAssertFalse(session.isSignedIn)
  }

  /// A listener registered after bootstrap receives the settled state
  /// immediately, which is what lets a view mount late without waiting.
  func testListenerReceivesTheCurrentStateOnRegistration() async {
    let session = AppSession.withStorage(directory: temporaryDirectory())
    await session.start()

    var received: [String] = []
    session.addListener { received.append(String(describing: $0)) }

    XCTAssertEqual(received, ["signedOut"])
  }

  /// Signing out with nothing signed in is a no-op that leaves the root where
  /// it was, rather than throwing.
  func testSignOutWithNoAccountStaysSignedOut() async {
    let session = AppSession.withStorage(directory: temporaryDirectory())
    await session.start()

    await session.signOut()

    XCTAssertFalse(session.isSignedIn)
    XCTAssertFalse(session.loginIsStale)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("appsession-tests-\(UUID().uuidString)", isDirectory: true)
  }
}

/// The shell's strings seam: the shell's own chrome copy resolves here and
/// nowhere else.
final class ShellCopyTests: XCTestCase {
  func testAccountMenuCopy() {
    XCTAssertEqual(ShellCopy.currentAccount("alice.test"), "@alice.test")
    XCTAssertEqual(ShellCopy.signOutAction, "Sign out")
    XCTAssertEqual(ShellCopy.accountMenuLabel, "Account")
    XCTAssertEqual(ShellCopy.loginCancelAction, "Close")
  }
}
