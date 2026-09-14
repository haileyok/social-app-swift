import Foundation

/**
 The five top-level destinations of the app shell.

 Route names follow the RN app's navigator (`~/bluesky/social-app/src/routes.ts`
 and `src/view/shell/bottom-bar/BottomBar.tsx`): the routes are `Home`,
 `Search`, `Messages`, `Notifications`, `Profile`, while the RN bottom bar's
 user-facing label for `Messages` is "Chat". The `title` here is the RN
 *label*, and the `accessibilityIdentifier` mirrors the RN `testID` so the two
 apps' UI tests address the same controls.

 Order is the RN bottom-bar order.
 */
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
  case home
  case search
  case messages
  case notifications
  case profile

  public var id: String { rawValue }

  /** The RN bottom bar label for this tab (see `BottomBar.tsx`). */
  public var title: String {
    switch self {
    case .home: "Home"
    case .search: "Search"
    case .messages: "Chat"
    case .notifications: "Notifications"
    case .profile: "Profile"
    }
  }

  /** The RN navigator route name. Differs from `title` only for Messages. */
  public var routeName: String {
    switch self {
    case .home: "Home"
    case .search: "Search"
    case .messages: "Messages"
    case .notifications: "Notifications"
    case .profile: "Profile"
    }
  }

  /** The RN `testID` of the corresponding bottom-bar button. */
  public var accessibilityIdentifier: String {
    switch self {
    case .home: "bottomBarHomeBtn"
    case .search: "bottomBarSearchBtn"
    case .messages: "bottomBarMessagesBtn"
    case .notifications: "bottomBarNotificationsBtn"
    case .profile: "bottomBarProfileBtn"
    }
  }

  /** SF Symbol standing in for the RN icon until UIComponents lands. */
  public var systemImage: String {
    switch self {
    case .home: "house"
    case .search: "magnifyingglass"
    case .messages: "bubble.left.and.bubble.right"
    case .notifications: "bell"
    case .profile: "person"
    }
  }

  /** One-line description of what the screen will eventually show. */
  public var placeholderDetail: String {
    switch self {
    case .home: "Following feed, Discover, and pinned feeds."
    case .search: "Search posts, users, and feeds."
    case .messages: "Direct-message conversations."
    case .notifications: "Replies, mentions, follows, and likes."
    case .profile: "Your profile, posts, and saved content."
    }
  }

  /** The launch-argument index (`-uiTestInitialTab N`) for this tab. */
  public var index: Int {
    Self.allCases.firstIndex(of: self) ?? 0
  }
}
