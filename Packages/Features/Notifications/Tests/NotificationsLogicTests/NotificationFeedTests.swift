import Foundation
import Testing

import Lexicons
import NotificationsLogic
import QueryStore
import SwiftAtproto

@Suite("Notification feed")
struct NotificationFeedTests {
  private func makeStore() -> QueryStore {
    QueryStore(clock: ManualQueryClock())
  }

  private func reply(
    id: String,
    author did: String = Fixtures.bobDid,
    at indexedAt: String = "2026-01-01T00:00:00.000Z"
  ) -> App.Bsky.NotificationListNotifications_Notification {
    Fixtures.notification(
      uri: "at://\(did)/app.bsky.feed.post/\(id)",
      reason: .reply,
      author: Fixtures.profile(did),
      record: Fixtures.postRecord(),
      indexedAt: indexedAt
    )
  }

  /// Page one loads and holds its rows and cursor.
  @Test func loadsFirstPage() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1"), reply(id: "2")], cursor: "c1")

    let query = NotificationFeedQuery(
      store: makeStore(),
      filter: .all,
      fetchPage: { cursor in
        try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
          .page(cursor: cursor)
      }
    )

    let data = try await query.loadFirstPage()
    #expect(data.items.count == 1)
    #expect(data.items[0].items.count == 2)
    #expect(data.nextCursor == "c1")
  }

  /// Loading more appends, and de-duplication on merge collapses a row the
  /// server repeats across pages.
  @Test func appendsPagesAndDedupes() async throws {
    let client = FakeNotificationClient()
    let repeated = reply(id: "2")
    client.pages[nil] = Fixtures.page([reply(id: "1"), repeated], cursor: "c1")
    client.pages["c1"] = Fixtures.page([repeated, reply(id: "3")], cursor: nil)

    let query = NotificationFeedQuery(
      store: makeStore(),
      filter: .all,
      fetchPage: { cursor in
        try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
          .page(cursor: cursor)
      }
    )

    try await query.loadFirstPage()
    try await query.loadMore()

    // Read back through the select pass: the store de-duplicates pages, not the
    // rows inside them, so row identity is reconciled here.
    let rows = await query.items()
    // The row carried on both pages appears once, in the earlier page.
    #expect(rows.count == 3)
    #expect(rows.map(\.reactKey).count == Set(rows.map(\.reactKey)).count)
    #expect(rows.map(\.identity) == [
      "notif-at://\(Fixtures.bobDid)/app.bsky.feed.post/1-reply",
      "notif-at://\(Fixtures.bobDid)/app.bsky.feed.post/2-reply",
      "notif-at://\(Fixtures.bobDid)/app.bsky.feed.post/3-reply",
    ])
    #expect(await query.infinite.paginationState().pageCount == 2)
    #expect(await query.infinite.paginationState().nextCursor == nil)
  }

  /// The `mentions` filter sends the post reasons, ported from the RN queryFn.
  @Test func mentionsFilterSendsReasons() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1")], cursor: nil)

    let query = NotificationFeedQuery(
      store: makeStore(),
      filter: .mentions,
      fetchPage: { cursor in
        try await NotificationPageFetcher(
          client: client,
          fetchAdditionalData: false,
          reasons: NotificationFeedFilter.mentions.reasons
        ).page(cursor: cursor)
      }
    )
    try await query.loadFirstPage()

    guard case .listNotifications(_, let limit, _, let reasons) = client.calls.first else {
      Issue.record("expected a listNotifications call")
      return
    }
    #expect(limit == NotificationFeeds.pageSize)
    #expect(reasons == ["mention", "reply", "quote"])
  }

  /// The feed is fetched with `STALE.INFINITY`, so a second read does not
  /// refetch on its own.
  @Test func feedIsNeverStaleByTime() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1")], cursor: nil)

    let store = makeStore()
    let query = NotificationFeedQuery(
      store: store,
      filter: .all,
      fetchPage: { cursor in
        try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
          .page(cursor: cursor)
      }
    )

    try await query.loadFirstPage()
    try await query.loadFirstPage()

    #expect(await store.staleTime(for: query.key) == STALE.INFINITY)
  }

  /// The head page's `seenAt` overrides every row's `isRead`, so a notification
  /// indexed before the watermark reads as read even when the server said
  /// otherwise.
  @Test func headSeenAtOverridesIsRead() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page(
      [reply(id: "1", at: "2026-01-01T00:00:00.000Z")],
      cursor: nil,
      seenAt: "2026-02-01T00:00:00.000Z"
    )

    let query = NotificationFeedQuery(
      store: makeStore(),
      filter: .all,
      fetchPage: { cursor in
        try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
          .page(cursor: cursor)
      }
    )
    try await query.loadFirstPage()

    let rows = await query.items()
    #expect(rows.count == 1)
    #expect(rows[0].notification.isRead)
  }

  /// A notification indexed after the watermark reads as unread.
  @Test func newerThanSeenAtIsUnread() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .reply,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.postRecord(),
      indexedAt: "2026-03-01T00:00:00.000Z"
    )
    let seenAt = NotificationReasons.parseATProtoDate("2026-02-01T00:00:00.000Z")!
    #expect(!NotificationFeeds.isRead(notification: notification, seenAt: seenAt))
  }

  /// A hidden thread's reply is dropped from the selected rows.
  @Test func hiddenReplyDropped() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "hidden"), reply(id: "shown")], cursor: nil)

    let query = NotificationFeedQuery(
      store: makeStore(),
      filter: .all,
      fetchPage: { cursor in
        try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
          .page(cursor: cursor)
      }
    )
    try await query.loadFirstPage()

    let hiddenUri = "at://\(Fixtures.bobDid)/app.bsky.feed.post/hidden"
    let rows = await query.items(hiddenReplyUris: [hiddenUri])
    #expect(rows.count == 1)
    #expect(rows[0].reactKey.contains("shown"))
  }

  /// The priority view keeps only rows from a page the appview flagged.
  @Test func priorityOnlyKeepsFlaggedPages() {
    let flagged = Fixtures.page(
      [reply(id: "p")], cursor: nil, priority: true)
    let unflagged = Fixtures.page([reply(id: "n")], cursor: nil, priority: false)
    let pageA = NotificationFeedPage(
      cursor: flagged.cursor,
      seenAt: Date(),
      items: NotificationReasons.group(flagged.notifications),
      priority: true
    )
    let pageB = NotificationFeedPage(
      cursor: unflagged.cursor,
      seenAt: Date(),
      items: NotificationReasons.group(unflagged.notifications),
      priority: false
    )

    #expect(NotificationFeeds.renderPriority([pageA, pageB], priorityOnly: true).count == 1)
    #expect(NotificationFeeds.renderPriority([pageA, pageB], priorityOnly: false).count == 2)
  }

  /// The priority view is a distinct cache entry from the standard feed.
  @Test func priorityViewHasItsOwnKey() {
    let standard = NotificationQueryKey.feed(.all)
    let priority = NotificationQueryKey.feed(.all, priorityOnly: true)
    #expect(standard != priority)
    #expect(standard.keyRoot == "notification-feed")
    #expect(NotificationQueryKey.feed(.all, scope: "did:plc:me").scope == "did:plc:me")
  }

  /// Subjects are resolved in bulk when requested, and attached to rows.
  @Test func resolvesSubjects() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1")], cursor: nil)
    client.posts["at://\(Fixtures.bobDid)/app.bsky.feed.post/1"] = Fixtures.postView(
      uri: "at://\(Fixtures.bobDid)/app.bsky.feed.post/1")

    let result = try await NotificationPageFetcher(client: client, fetchAdditionalData: true)
      .result(cursor: nil)

    let row = try #require(result.page.items.first)
    guard case .post(let post) = row.subject else {
      Issue.record("expected a resolved post subject")
      return
    }
    #expect(post.uri.rawValue == "at://\(Fixtures.bobDid)/app.bsky.feed.post/1")
    #expect(client.calls(of: "getPosts").count == 1)
  }

  /// Subjects are not fetched when the caller will not use the page, matching
  /// the `fetchAdditionalData: !!invalidate` guard in the RN poller.
  @Test func skipsSubjectFetchWhenNotNeeded() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1")], cursor: nil)

    _ = try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
      .result(cursor: nil)

    #expect(client.calls(of: "getPosts").isEmpty)
  }

  /// The `indexedAt` of the first notification is reported for the unread
  /// poller's watermark.
  @Test func reportsIndexedAt() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page(
      [reply(id: "1", at: "2026-01-01T00:00:00.000Z")], cursor: nil)

    let result = try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
      .result(cursor: nil)
    #expect(result.indexedAt == "2026-01-01T00:00:00.000Z")
  }
}
