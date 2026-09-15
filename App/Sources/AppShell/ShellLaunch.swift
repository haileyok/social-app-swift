import DesignSystem
import DesignSystemCore
import Foundation

/**
 The launch arguments that put the app into a deterministic state for CI.

 `ShellLaunchArgument` names the keys; this type reads them and decides what they
 mean, so the root view holds no parsing and the capture keys have exactly one
 consumer. Everything here is opt-in: an app launched by a person sees no
 arguments and behaves normally.
 */
public struct ShellLaunch: Sendable, Equatable {
  /// The zero-based tab to select on launch.
  public let initialTab: AppTab

  /// The full-screen surface requested for capture, when any.
  public let screen: String?

  /**
   The capture theme's name (`light|dark|dim`), or nil for the stored
   preference.

   Stored as its raw name rather than as a `ThemePreference` value so this type
   - and therefore the shell's unit tests, which link only the `AppShell`
   product - does not reference a `DesignSystemCore` symbol. `theme` resolves it
   for callers that want the enum.
   */
  public let themeName: String?

  /// The capture theme, resolved from ``themeName``.
  public var theme: ThemePreference? {
    themeName.flatMap(ThemePreference.init(rawValue:))
  }

  /** Whether `-uiTestInitialTab` was passed (as opposed to falling back to Home). */
  public let hasTabArgument: Bool

  /**
   Whether the launch explicitly asked for a fixture/demo session.

   Read from `-uiTestDemo`, a bare flag rather than a key/value pair, so a
   `simctl launch` call can pass it without inventing a value to ignore. It is a
   `UserDefaults` domain key like the others, which is also what the shell's own
   unit tests use to exercise the parser.
   */
  public let isDemoArgument: Bool

  /**
   Whether the launch should land inside the tab shell with no account.

   Any of the three CI-only launch forms implies it: the screenshot loop passes
   `-uiTestInitialTab`, the gallery loop passes `-uiTestScreen`, and a future
   fixture run can pass `-uiTestDemo`. What they have in common is that the
   process was launched to exercise the shell, so the session gate steps aside
   rather than showing a sign-in form the run has no credentials for.

   A launch under XCUITest counts too (``isUITestLaunch``), which is what keeps
   a UI test that passes *no* arguments - the tab smoke test - deterministic
   instead of dependent on whatever session the simulator happens to hold.
   */
  public var isDemoLaunch: Bool {
    isDemoArgument || hasTabArgument || screen != nil || Self.isUITestLaunch
  }

  /**
   Whether this process was launched by XCUITest.

   The runner sets `XCTestConfigurationFilePath` in the app-under-test's
   environment. Reading it is the difference between "a test launched me and
   cannot sign in" and "a person launched me"; the app treats the former as a
   demo launch so a test never lands on a root it has no credentials to leave.
   */
  public static var isUITestLaunch: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
  }

  /// The launch state of the process, read from `UserDefaults.standard`.
  public static var current: ShellLaunch { read(from: .standard) }

  /**
   Reads a launch state from a defaults domain.

   Parameterizing the domain keeps this testable without a process launch: the
   shell's unit tests construct a suite, write the keys, and read them back.
   */
  public static func read(from defaults: UserDefaults) -> ShellLaunch {
    let index = defaults.integer(forKey: ShellLaunchArgument.initialTab)
    let tabs = AppTab.allCases
    let screen = defaults.string(forKey: ShellLaunchArgument.screen)
      .flatMap { $0.isEmpty ? nil : $0 }
    return ShellLaunch(
      initialTab: tabs.indices.contains(index) ? tabs[index] : .home,
      screen: screen,
      themeName: defaults.string(forKey: ShellLaunchArgument.theme),
      hasTabArgument: defaults.object(forKey: ShellLaunchArgument.initialTab) != nil,
      isDemoArgument: Self.hasDemoFlag(in: defaults))
  }

  /**
   Reads the demo flag.

   `UserDefaults`' argument domain parses `-key value` pairs, so a *bare*
   `-uiTestDemo` can be dropped depending on what follows it. Both forms are
   therefore accepted: the keyed one (which is also what the unit tests can set
   in a scratch suite) and the literal argument.
   */
  private static func hasDemoFlag(in defaults: UserDefaults) -> Bool {
    defaults.bool(forKey: ShellLaunchArgument.demo)
      || ProcessInfo.processInfo.arguments.contains("-\(ShellLaunchArgument.demo)")
  }
}
