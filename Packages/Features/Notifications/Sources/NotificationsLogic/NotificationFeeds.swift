import Foundation

import Lexicons
import Moderation
import QueryStore

public enum NotificationQueryKey {
  /// `notification-feed`, the infinite feed query.
  public static let feedRoot = "notification-feed"
  /// `notification-unread`, the unread-count pipeline. The RN app keeps this
  /// state in a React context rather than in the query cache, so this root is
  /// new to the Swift port.
  public static let unreadRoot = "notification-unread"
  /// `activity-subscriptions`, ported from `RQKEY_getActivitySubscriptions`.
  public static let activitySubscriptionsRoot = "activity-subscriptions"
  /// `notification-settings-app`, ported from `RQKEY_APP`.
  public static let settingsRoot = "notification-settings-app"

  /// The feed key for a filter, matching `RQKEY(filter)`.
  ///
  /// The RN key is `[root, filter]`; `priorityOnly` is an extra argument this
  /// port adds so the priority view caches separately from the standard feed.
  public static func feed(
    _ filter: NotificationFeedFilter,
    priorityOnly: Bool = false,
    scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      feedRoot,
      NotificationFeedArgs(filter: filter, priorityOnly: priorityOnly),
      options: QueryOptions(scope: scope)
    )
  }

  /// The unread-count key.
  public static func unread(scope: String? = nil) -> QueryKey {
    QueryKey(unreadRoot, options: QueryOptions(scope: scope))
  }

  /// The activity-subscriptions key, matching `RQKEY_getActivitySubscriptions`
  /// (an argument-less infinite query).
  public static func activitySubscriptions(scope: String? = nil) -> QueryKey {
    QueryKey(activitySubscriptionsRoot, options: QueryOptions(scope: scope))
  }

  /// The app notification-settings key, matching `RQKEY_APP`.
  public static func settings(scope: String? = nil) -> QueryKey {
    QueryKey(settingsRoot, options: QueryOptions(scope: scope))
  }
}

/// Arguments for the feed key, the Swift form of `[RQKEY_ROOT, filter]`.
public struct NotificationFeedArgs: QueryArgs {
  public var filter: NotificationFeedFilter
  /// True for the priority-only view.
  public var priorityOnly: Bool

  public init(filter: NotificationFeedFilter, priorityOnly: Bool = false) {
    self.filter = filter
    self.priorityOnly = priorityOnly
  }
}

/// The feed query's constants and shared derivations.
public enum NotificationFeeds {
  /// Items per page, the RN `PAGE_SIZE`.
  public static let pageSize = 30
  /// Items per page for the unread poll, the RN poll's `limit: 40`.
  public static let unreadPageSize = 40

  /// Recomputes `isRead` against a page watermark.
  ///
  /// Ported from the `select` callback: a notification counts as read when the
  /// page's `seenAt` is later than the notification's `indexedAt`. Doing this
  /// locally is what stops the mark-all-read side effect of loading page one
  /// from making later pages read prematurely.
  public static func isRead(notification: RawNotification, seenAt: Date) -> Bool {
    guard
      let indexedAt = NotificationReasons.parseATProtoDate(notification.indexedAt.rawValue)
    else {
      return notification.isRead
    }
    return seenAt > indexedAt
  }

  /// The priority-only derivation.
  ///
  /// The appview computes which notifications are high priority and answers a
  /// `priority: true` request with `priority: true` on the page. There is no
  /// per-notification priority field in the lexicon, so the priority view is
  /// derived at the page level: rows from a page the appview flagged are kept
  /// and rows from unflagged pages are dropped.
  ///
  /// The RN app requests the same flag but filters nothing in the query layer,
  /// leaving the priority decision to the UI. This derivation is documented as
  /// the Swift port's answer to that, not as a behavior copied from RN.
  public static func renderPriority(
    _ pages: [NotificationFeedPage],
    priorityOnly: Bool
  ) -> [FeedNotification] {
    var rows: [FeedNotification] = []
    for page in pages where !priorityOnly || page.priority {
      rows.append(contentsOf: page.items)
    }
    return rows
  }
}

/// The notifications feed infinite query.
///
/// The read path is the port of `useNotificationFeedQuery`: `STALE.INFINITY`
/// (the feed is refreshed by explicit invalidation from the unread pipeline,
/// not by time), no persisted version (the RN feed is not persisted), and
/// de-duplication on merge keyed by the row's `reactKey`.
///
/// The infinite query's item type is the page, not the row, because the page
/// carries the `seenAt` watermark and `priority` flag the select pass needs.
public struct NotificationFeedQuery: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// The filter this query serves.
  public let filter: NotificationFeedFilter
  /// True for the priority-only view.
  public let priorityOnly: Bool
  /// The account scope, for key identity.
  public let scope: String?
  /// Moderation options for the select pass, applied when ``items()`` runs.
  public let moderationOpts: ModerationOpts?
  private let fetchPage: @Sendable (String?) async throws -> NotificationFeedPage

  /// Creates a feed query.
  ///
  /// - Parameters:
  ///   - store: the store to read and write.
  ///   - filter: the server-side filter.
  ///   - priorityOnly: true to serve the priority view.
  ///   - scope: account scope, usually the signed-in DID.
  ///   - moderationOpts: options for the select pass; when `nil` (or when a
  ///     caller uses ``selectedItems(...)`` directly), no row is dropped by
  ///     subject moderation.
  ///   - fetchPage: fetches one page for a cursor. ``NotificationPageFetcher``
  ///     is the real one.
  public init(
    store: QueryStore,
    filter: NotificationFeedFilter,
    priorityOnly: Bool = false,
    scope: String? = nil,
    moderationOpts: ModerationOpts? = nil,
    fetchPage: @escaping @Sendable (String?) async throws -> NotificationFeedPage
  ) {
    self.store = store
    self.filter = filter
    self.priorityOnly = priorityOnly
    self.scope = scope
    self.moderationOpts = moderationOpts
    self.fetchPage = fetchPage
  }

  /// The key this query reads and writes.
  public var key: QueryKey {
    NotificationQueryKey.feed(filter, priorityOnly: priorityOnly, scope: scope)
  }

  /// The `QueryStore` handle for this query.
  public var infinite: InfiniteQuery<NotificationFeedPage> {
    InfiniteQuery(
      store: store,
      key: key,
      identity: { $0.cursor ?? "first-page" },
      page: { [fetchPage, priorityOnly, filter] cursor in
        let page = try await fetchPage(cursor)
        _ = priorityOnly
        _ = filter
        return QueryPage(items: [page], cursor: page.cursor, requestCursor: cursor)
      }
    )
  }

  /// Loads the first page, replacing what is held.
  @discardableResult
  public func loadFirstPage(
    force: Bool = false
  ) async throws -> InfiniteQueryData<NotificationFeedPage> {
    try await infinite.loadFirstPage(staleTime: STALE.INFINITY, force: force)
  }

  /// Appends the next page.
  @discardableResult
  public func loadMore() async throws -> InfiniteQueryData<NotificationFeedPage> {
    try await infinite.loadMore()
  }

  /// The held pages, in order.
  public func pages() async -> [NotificationFeedPage] {
    await infinite.items()
  }

  /// The rows the feed should show, after the select pass.
  ///
  /// The port of the RN `select`: the head page's `seenAt` overrides every
  /// row's `isRead`, hidden replies are dropped, reply/mention/quote subjects
  /// that the post moderation engine filters are dropped, and the priority
  /// view keeps only flagged pages.
  public func items(
    hiddenReplyUris: Set<String> = []
  ) async -> [FeedNotification] {
    Self.select(
      await pages(),
      moderationOpts: moderationOpts,
      hiddenReplyUris: hiddenReplyUris,
      priorityOnly: priorityOnly
    )
  }

  /// Applies the select pass to a page list.
  ///
  /// Marking read uses the head page's watermark for every page, which is what
  /// makes loading page one unable to mark later pages read on its own. Rows
  /// are de-duplicated by identity across pages, so a notification the appview
  /// returns on two pages (normal when posts move between requests) renders
  /// once, keeping the earlier copy.
  public static func select(
    _ pages: [NotificationFeedPage],
    moderationOpts: ModerationOpts? = nil,
    hiddenReplyUris: Set<String> = [],
    priorityOnly: Bool = false
  ) -> [FeedNotification] {
    let seenAt = pages.first?.seenAt ?? Date()
    var seen = Set<String>()
    var rows: [FeedNotification] = []
    for page in NotificationFeeds.renderPriority(pages, priorityOnly: priorityOnly) {
      guard seen.insert(page.reactKey).inserted else { continue }
      var row = page
      row.notification.isRead = NotificationFeeds.isRead(
        notification: row.notification, seenAt: seenAt)
      if isHiddenReply(row, hiddenReplyUris: hiddenReplyUris) { continue }
      if NotificationReasons.isFilteredBySubjectModeration(row, moderationOpts: moderationOpts) {
        continue
      }
      rows.append(row)
    }
    return rows
  }

  /// True when a row is a reply to a thread the viewer has hidden.
  static func isHiddenReply(_ row: FeedNotification, hiddenReplyUris: Set<String>) -> Bool {
    guard row.type == .reply, let uri = row.subjectUri else { return false }
    return hiddenReplyUris.contains(uri)
  }
}

extension FeedNotification {
  /// Stable identity for de-duplication: the row's `reactKey`.
  public var identity: String { reactKey }
}
