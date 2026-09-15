import Foundation

import Lexicons
import NotificationsLogic
import UIComponentsCore

/// The filter the notifications list is showing.
///
/// The RN screen (`~/bluesky/social-app/src/view/screens/Notifications.tsx`)
/// has two pager tabs, All and Mentions, and asks the appview for a
/// `priority: true` page for the priority view. The port exposes the priority
/// view as a third tab because the appview's priority flag is a page-level
/// property the logic package already derives (`NotificationFeeds.renderPriority`),
/// and a tab is how the viewer reaches it.
public enum NotificationsFilterTab: String, Sendable, CaseIterable, Identifiable {
  /// Every notification, the RN `filter: 'all'`.
  case all
  /// Replies, mentions and quotes, the RN `filter: 'mentions'`.
  case mentions
  /// The appview's high-priority page.
  case priority

  public var id: String { rawValue }

  /// The tab label.
  public var title: String {
    switch self {
    case .all: "All"
    case .mentions: "Mentions"
    case .priority: "Priority"
    }
  }

  /// The server-side filter this tab requests.
  public var feedFilter: NotificationFeedFilter {
    switch self {
    case .all, .priority: .all
    case .mentions: .mentions
    }
  }

  /// True for the priority view, which keeps only appview-flagged pages.
  public var priorityOnly: Bool { self == .priority }

  /// The RN pager index, for UI tests that address a tab positionally.
  public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// The rows the list renders, plus the state the empty/loading branches need.
///
/// Pure: it takes the pages the query produced and returns values. Row
/// construction reuses ``NotificationsLogic/NotificationReasons`` for the
/// grouping rule and the subject URI, so no decision is re-derived here.
public struct NotificationsListModel: Sendable {
  /// The state of the surface, resolved with the same helper the other lists use.
  public let state: ListState
  /// The rows to draw, in feed order.
  public let rows: [FeedNotification]
  /// How many rows are unread, which drives the badge.
  public let unread: UnreadCount

  /// Builds a model from a page list.
  ///
  /// - Parameters:
  ///   - pages: the pages the feed query returned, newest first. The head page's
  ///     `seenAt` watermark marks rows read, exactly as the RN `select` does.
  ///   - priorityOnly: true for the priority tab.
  ///   - isInitialLoading: true while the first page is still in flight.
  ///   - error: the failure to surface, when the last load failed.
  public init(
    pages: [NotificationFeedPage],
    priorityOnly: Bool = false,
    isInitialLoading: Bool = false,
    error: ListState.ListErrorState? = nil
  ) {
    // `select` applies the read watermark, drops hidden replies and drops
    // subjects the moderation engine filters, so the view does not repeat any
    // of it. Moderation options are nil here: the screen has no session yet.
    let rows = NotificationFeedQuery.select(pages, priorityOnly: priorityOnly)
    self.rows = rows
    self.unread = UnreadCount(
      count: NotificationFeedQuery.select(pages, priorityOnly: priorityOnly)
        .filter { !$0.notification.isRead }
        .count)
    self.state = ListState.resolve(
      itemCount: rows.count, isInitialLoading: isInitialLoading, error: error)
  }

  /// An explicit model, for previews and fixtures.
  public init(rows: [FeedNotification], state: ListState = .content) {
    self.rows = rows
    self.state = state
    self.unread = UnreadCount(count: rows.filter { !$0.notification.isRead }.count)
  }

  /// True when the model draws a row list rather than a full-surface state.
  public var showsRows: Bool {
    switch state {
    case .content, .loadingMore: true
    case .loading, .empty, .error: false
    }
  }
}

extension NotificationsListModel {
  /// The list copy this surface uses: the shared notifications strings.
  public static let strings = ListStrings.notifications

  /**
   The rows a reason renders as.

   Replies, mentions and quotes render the subject post; the rest render an icon
   and a sentence. A reply-shaped row whose subject never resolved is dropped by
   the RN item (`if (!item.subject) return null`), which this mirrors, and the
   same applies to a row with a reason this build does not render at all.
   */
  public var drawableRows: [FeedNotification] {
    rows.filter { row in
      // Sentence rows always have something to draw.
      guard !NotificationsCopy.rendersAsSentence(row.type) else { return true }
      // A post-shaped row (reply, mention, quote) draws the subject post, so it
      // is only drawable once that subject resolved. The RN item returns null
      // for the same case; an unknown reason has no subject either, so it drops
      // here too rather than rendering an untranslated sentence.
      return row.subjectPost != nil
    }
  }
}

extension FeedNotification {
  /// True when the row should be highlighted as unread.
  public var isUnread: Bool { !notification.isRead }

  /// The subject post, when the row resolved to one.
  public var subjectPost: App.Bsky.FeedDefs_PostView? {
    guard case .post(let post) = subject else { return nil }
    return post
  }
}
