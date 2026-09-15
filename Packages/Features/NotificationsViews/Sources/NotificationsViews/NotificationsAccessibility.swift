import Foundation

/**
 The accessibility identifiers and launch arguments the notifications surface
 exposes to UI tests.

 Mirrors `AppShell`'s `ShellAccessibility` / `LoginViews`' `LoginAccessibility`:
 the strings live in one place so the XCUITest bundle links the package rather
 than duplicating literals. The `testID`s copy the RN app's
 (`~/bluesky/social-app/src/view/com/notifications/NotificationFeedItem.tsx`,
 which tags each row `feedItem-by-<handle>`), so the two apps' tests address the
 same elements.
 */
public enum NotificationsAccessibility {
  /** The scroll container of the notifications list. */
  public static let screen = "notificationsScreen"

  /** The reason-row list inside ``screen``. */
  public static let list = "notificationsList"

  /** The all / mentions / priority filter control. */
  public static let filterTabs = "notificationsFilterTabs"

  /** The empty state shown when the filter has no rows. */
  public static let emptyState = "notificationsEmptyState"

  /** The unread highlight on a row. */
  public static let unreadIndicator = "notificationsUnreadIndicator"

  /** The reason icon that leads a row. */
  public static let rowIcon = "notificationsRowIcon"

  /** The per-row accessibility label, e.g. "Alice liked your post". */
  public static let rowLabel = "notificationsRowLabel"

  /** The row's leading avatar, present on reasons that show one instead of an icon. */
  public static let rowAvatar = "notificationsRowAvatar"

  /** The post subject rendered under a like/repost row. */
  public static let rowSubject = "notificationsRowSubject"

  /** The identifier of one filter tab, e.g. `notificationsFilterTab-all`. */
  public static func filterTab(_ filter: NotificationsFilterTab) -> String {
    "notificationsFilterTab-\(filter.rawValue)"
  }

  /** The RN `testID` of a row, keyed by the author's handle. */
  public static func row(_ handle: String) -> String {
    "feedItem-by-\(handle)"
  }

  /**
   The launch argument that pins the surface's theme, so a screenshot run can
   capture the list in a specific appearance.
   */
  public static let themeLaunchArgument = "-notificationsTheme"
}
