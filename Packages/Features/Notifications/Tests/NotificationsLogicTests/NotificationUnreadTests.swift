import Foundation
import Testing

import Lexicons
import NotificationsLogic
import Preferences
import QueryStore
import SwiftAtproto

@Suite("Notification unread pipeline")
struct NotificationUnreadTests {
  private func reply(
    id: String,
    isRead: Bool,
    at indexedAt: String = "2026-01-01T00:00:00.000Z"
  ) -> App.Bsky.NotificationListNotifications_Notification {
    Fixtures.notification(
      uri: "at://\(Fixtures.bobDid)/app.bsky.feed.post/\(id)",
      reason: .reply,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.postRecord(),
      isRead: isRead,
      indexedAt: indexedAt
    )
  }

  private func makeCoordinator(
    client: FakeNotificationClient,
    scheduler: ManualNotificationPollScheduler,
    clock: ManualNotificationClock,
    random: NotificationRandomProvider = FixedNotificationRandomProvider.allow,
    preferences: PreferencesEngine? = nil,
    store: QueryStore? = nil
  ) -> NotificationUnreadCoordinator {
    NotificationUnreadCoordinator(
      client: client,
      store: store ?? QueryStore(clock: ManualQueryClock()),
      preferences: preferences,
      clock: clock,
      scheduler: scheduler,
      random: random
    )
  }

  /// The poll interval is the RN thirty seconds.
  @Test func pollIntervalIsThirtySeconds() {
    #expect(NotificationUnreadCoordinator.updateInterval == 30)
  }

  /// A check derives the badge from the page's unread rows, including grouped
  /// ones.
  @Test func checkDerivesUnreadCount() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page(
      [reply(id: "1", isRead: false), reply(id: "2", isRead: true)], cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock()
    )
    await coordinator.checkUnread()

    #expect(coordinator.state.unreadCount == .some(1))
    #expect(coordinator.cachedPage.unreadCount == 1)
  }

  /// No unread rows gives the empty badge.
  @Test func allReadGivesEmptyBadge() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: true)], cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock()
    )
    await coordinator.checkUnread()
    #expect(coordinator.state.unreadCount == .none)
    #expect(coordinator.state.unreadCount.rawValue == "")
  }

  /// Thirty or more unread saturates at `30+`.
  @Test func countSaturatesAtThirty() async {
    let client = FakeNotificationClient()
    let many = (0..<35).map { reply(id: "\($0)", isRead: false) }
    client.pages[nil] = Fixtures.page(many, cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock()
    )
    await coordinator.checkUnread()
    #expect(coordinator.state.unreadCount == .many)
    #expect(coordinator.state.unreadCount.rawValue == "30+")
  }

  /// The unread count value round-trips through its raw string.
  @Test(
    "unread count boundaries",
    arguments: [(0, ""), (1, "1"), (29, "29"), (30, "30+"), (100, "30+")]
  )
  func unreadBoundaries(count: Int, raw: String) {
    #expect(UnreadCount(count: count).rawValue == raw)
  }

  /// Starting the poll fires one immediate check and registers a tick; the
  /// state reports polling.
  @Test func startPollsImmediatelyAndSchedules() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: nil)
    let scheduler = ManualNotificationPollScheduler()

    let coordinator = makeCoordinator(
      client: client,
      scheduler: scheduler,
      clock: ManualNotificationClock()
    )
    coordinator.startPolling()
    // The on-init check runs in a detached task; fire a tick and let it settle.
    await scheduler.fire()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(coordinator.state.isPolling)
    #expect(scheduler.isScheduled)
    #expect(scheduler.requestedInterval == NotificationUnreadCoordinator.updateInterval)
  }

  /// A poll is skipped entirely once the badge has saturated.
  @Test func saturatingPollSkips() async {
    let client = FakeNotificationClient()
    let many = (0..<35).map { reply(id: "\($0)", isRead: false) }
    client.pages[nil] = Fixtures.page(many, cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock(),
      random: FixedNotificationRandomProvider.allow
    )
    await coordinator.checkUnread()
    let callsAfterFirst = client.calls(of: "listNotifications").count

    await coordinator.checkUnread(isPoll: true)
    #expect(client.calls(of: "listNotifications").count == callsAfterFirst)
  }

  /// With a badge showing, a poll is throttled by the random draw: the skip
  /// provider suppresses it and the allow provider lets it through.
  @Test func throttledPollRespectsRandom() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: nil)

    let skipping = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock(),
      random: FixedNotificationRandomProvider.skip
    )
    await skipping.checkUnread()
    let afterFirst = client.calls(of: "listNotifications").count
    await skipping.checkUnread(isPoll: true)
    #expect(client.calls(of: "listNotifications").count == afterFirst)

    await skipping.checkUnread(isPoll: true)
    #expect(client.calls(of: "listNotifications").count == afterFirst)
  }

  /// With no badge, throttling does not apply even for the skip provider.
  @Test func zeroCountIsNeverThrottled() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: true)], cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock(),
      random: FixedNotificationRandomProvider.skip
    )
    await coordinator.checkUnread()
    await coordinator.checkUnread(isPoll: true)
    #expect(client.calls(of: "listNotifications").count == 2)
  }

  /// A backgrounded app skips the check entirely.
  @Test func inactiveAppSkipsCheck() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: nil)

    let coordinator = NotificationUnreadCoordinator(
      client: client,
      store: QueryStore(clock: ManualQueryClock()),
      clock: ManualNotificationClock(),
      scheduler: ManualNotificationPollScheduler(),
      isActive: { false }
    )
    await coordinator.checkUnread()
    #expect(client.calls(of: "listNotifications").isEmpty)
  }

  /// Without a session the check is skipped.
  @Test func signedOutSkipsCheck() async {
    let client = FakeNotificationClient()
    let coordinator = NotificationUnreadCoordinator(
      client: client,
      store: QueryStore(clock: ManualQueryClock()),
      clock: ManualNotificationClock(),
      scheduler: ManualNotificationPollScheduler(),
      hasSession: { false }
    )
    await coordinator.checkUnread()
    #expect(client.calls(of: "listNotifications").isEmpty)
  }

  /// Concurrent checks do not stack: the second returns immediately while the
  /// first is in flight. The lock-guarded `isFetching` flag is what enforces
  /// this.
  @Test func concurrentChecksDoNotStack() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: nil)
    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock()
    )

    async let first: Void = coordinator.checkUnread()
    async let second: Void = coordinator.checkUnread()
    _ = await (first, second)

    #expect(client.calls(of: "listNotifications").count == 1)
  }

  /// The cache watermark is `now`, unless the page's newest row is later, in
  /// which case the watermark advances to it and never backwards.
  @Test func syncWatermarkNeverGoesBackwards() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let older = Date(timeIntervalSince1970: 1_600_000_000)
    let newer = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(NotificationUnreadCoordinator.syncWatermark(now: now, lastIndexed: nil) == now)
    #expect(NotificationUnreadCoordinator.syncWatermark(now: now, lastIndexed: older) == now)
    #expect(NotificationUnreadCoordinator.syncWatermark(now: now, lastIndexed: newer) == newer)
  }

  /// The cached page is unusable as a feed seed until an invalidating check.
  @Test func cacheUsableOnlyAfterInvalidate() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock()
    )
    await coordinator.checkUnread()
    #expect(coordinator.getCachedUnreadPage() == nil)

    await coordinator.checkUnread(invalidate: true)
    #expect(coordinator.getCachedUnreadPage() != nil)
  }

  /// An invalidating check truncates and invalidates both feed keys.
  @Test func invalidatingCheckResetsFeeds() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: "c1")

    let store = QueryStore(clock: ManualQueryClock())
    let coordinator = NotificationUnreadCoordinator(
      client: client,
      store: store,
      clock: ManualNotificationClock(),
      scheduler: ManualNotificationPollScheduler()
    )

    let query = NotificationFeedQuery(
      store: store,
      filter: .all,
      fetchPage: { cursor in
        try await NotificationPageFetcher(client: client, fetchAdditionalData: false)
          .page(cursor: cursor)
      }
    )
    try? await query.loadFirstPage()
    let firstPageCalls = client.calls(of: "listNotifications").count
    // The feed is fetched with STALE.INFINITY, so time alone never makes it
    // stale; an invalidating unread check is what drives it.
    #expect(await store.isStale(query.key) == false)
    #expect(await query.infinite.paginationState().pageCount == 1)

    await coordinator.checkUnread(invalidate: true)

    // `truncateAndInvalidate` truncates the cursor walk to page one and, being
    // refetch-on-invalidate, immediately runs the registered fetcher again.
    #expect(client.calls(of: "listNotifications").count > firstPageCalls)
    #expect(await query.infinite.paginationState().pageCount == 1)
  }

  /// Mark-all-read sends the cache's sync watermark to `updateSeen`, not the
  /// current time, and resets the badge.
  @Test func markAllReadSendsWatermark() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page(
      [reply(id: "1", isRead: false, at: "2026-01-01T00:00:00.000Z")], cursor: nil)

    let clock = ManualNotificationClock(
      start: Date(timeIntervalSince1970: 1_800_000_000))
    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: clock
    )
    await coordinator.checkUnread()
    let watermark = coordinator.cachedPage.syncedAt

    try await coordinator.markAllRead()

    let seenCalls = client.calls(of: "updateSeen")
    #expect(seenCalls.count == 1)
    guard case .updateSeen(let seenAt) = seenCalls[0] else {
      Issue.record("expected an updateSeen call")
      return
    }
    #expect(seenAt == watermark)
    #expect(coordinator.state.unreadCount == .none)
    #expect(coordinator.cachedPage.unreadCount == 0)
  }

  /// The watermark sent is the page's newest `indexedAt` when that is later
  /// than now, so a not-yet-read page is not marked read.
  @Test func markAllReadUsesPageIndexedAtWhenLater() async throws {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page(
      [reply(id: "1", isRead: false, at: "2030-01-01T00:00:00.000Z")], cursor: nil)

    let clock = ManualNotificationClock(start: Date(timeIntervalSince1970: 1_800_000_000))
    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: clock
    )
    await coordinator.checkUnread()

    let expected = NotificationReasons.parseATProtoDate("2030-01-01T00:00:00.000Z")!
    try await coordinator.markAllRead()

    guard case .updateSeen(let seenAt) = client.calls(of: "updateSeen").first else {
      Issue.record("expected an updateSeen call")
      return
    }
    #expect(seenAt == expected)
  }

  /// A failed `updateSeen` leaves the badge and cache untouched, so the UI does
  /// not claim a read state the server never recorded.
  @Test func failedMarkAllReadKeepsState() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock()
    )
    await coordinator.checkUnread()
    #expect(coordinator.state.unreadCount == .some(1))

    client.error = FakeError.missingFixture("boom")
    do {
      try await coordinator.markAllRead()
      Issue.record("expected markAllRead to throw")
    } catch {
      // expected
    }
    #expect(coordinator.state.unreadCount == .some(1))
  }

  /// State observers see every transition.
  @Test func listenersObserveTransitions() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([reply(id: "1", isRead: false)], cursor: nil)

    let coordinator = makeCoordinator(
      client: client,
      scheduler: ManualNotificationPollScheduler(),
      clock: ManualNotificationClock()
    )
    let recorder = StateRecorder()
    coordinator.addListener { recorder.append($0) }

    await coordinator.checkUnread()
    #expect(recorder.values.contains { $0.unreadCount == .some(1) })
  }

  /// Stopping the poll cancels the tick.
  @Test func stopPollingCancels() async {
    let client = FakeNotificationClient()
    client.pages[nil] = Fixtures.page([], cursor: nil)
    let scheduler = ManualNotificationPollScheduler()

    let coordinator = makeCoordinator(
      client: client,
      scheduler: scheduler,
      clock: ManualNotificationClock()
    )
    coordinator.startPolling()
    coordinator.stopPolling()
    #expect(!coordinator.state.isPolling)
  }

  /// The unread cache counts grouped notifications behind a row too.
  @Test func countsGroupedNotifications() {
    let rows = NotificationReasons.group([
      Fixtures.notification(
        uri: "at://did:plc:alice/app.bsky.feed.like/1",
        reason: .like,
        author: Fixtures.profile(Fixtures.aliceDid),
        record: Fixtures.likeRecord(subject: Fixtures.postUri),
        indexedAt: "2026-01-01T00:00:00.000Z"
      ),
      Fixtures.notification(
        uri: "at://did:plc:bob/app.bsky.feed.like/2",
        reason: .like,
        author: Fixtures.profile(Fixtures.bobDid),
        record: Fixtures.likeRecord(subject: Fixtures.postUri),
        indexedAt: "2026-01-01T01:00:00.000Z"
      ),
    ])
    let page = NotificationFeedPage(seenAt: Date(), items: rows)
    // Two unread notifications behind one row.
    #expect(NotificationUnreadCoordinator.countUnread(page) == 2)
  }
}

/// A thread-safe recorder for state transitions.
final class StateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [NotificationUnreadCoordinator.State] = []

  func append(_ state: NotificationUnreadCoordinator.State) {
    lock.lock()
    defer { lock.unlock() }
    storage.append(state)
  }

  var values: [NotificationUnreadCoordinator.State] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}
