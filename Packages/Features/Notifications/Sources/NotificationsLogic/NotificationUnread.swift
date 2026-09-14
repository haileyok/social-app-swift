import Foundation

import Lexicons
import Moderation
import Preferences
import QueryStore

public protocol NotificationRandomProvider: Sendable {
  /// A value in `0..<1`.
  func next() -> Double
}

/// The real random source.
public struct SystemNotificationRandomProvider: NotificationRandomProvider {
  public init() {}

  public func next() -> Double { Double.random(in: 0..<1) }
}

/// A provider that always returns the same value.
public struct FixedNotificationRandomProvider: NotificationRandomProvider {
  private let value: Double

  public init(_ value: Double) {
    self.value = value
  }

  /// A provider that always lets a throttled poll through.
  public static let allow = FixedNotificationRandomProvider(0)
  /// A provider that always skips a throttled poll.
  public static let skip = FixedNotificationRandomProvider(1)

  public func next() -> Double { value }
}

/// The unread-count pipeline.
///
/// The port of `src/state/queries/notifications/unread.tsx`. It owns the
/// periodic poll, the cached first page the feed reuses, the mark-all-read
/// flow, and the badge state. It is deliberately not a React context: state is
/// a value guarded by a lock, and ``addListener(_:)`` observes it.
///
/// ## Interaction with the feed
///
/// As in RN, the feed query never drives freshness here. Call
/// ``checkUnread(invalidate:)`` to fetch latest in the background, or
/// ``checkUnread(invalidate: true)`` to make latest sync into the feed's
/// results immediately (which truncates and invalidates both feed keys).
public final class NotificationUnreadCoordinator: @unchecked Sendable {
  /// Poll cadence in seconds: the RN `UPDATE_INTERVAL` of thirty seconds.
  public static let updateInterval: TimeInterval = 30

  /// A state observer.
  public typealias Listener = @Sendable (NotificationUnreadState) -> Void

  /// The cached first page and its freshness, the RN `cacheRef`.
  public struct CachedPage: Sendable {
    /// True when the head page may be used as the feed's first page.
    public var usableInFeed: Bool
    /// When the cache was last synced. This is the watermark mark-all-read
    /// sends to the server.
    public var syncedAt: Date
    /// The cached page, when one has been fetched.
    public var data: NotificationFeedPage?
    /// The unread count the cache holds, as a plain number.
    public var unreadCount: Int

    public init(
      usableInFeed: Bool = false,
      syncedAt: Date = Date(),
      data: NotificationFeedPage? = nil,
      unreadCount: Int = 0
    ) {
      self.usableInFeed = usableInFeed
      self.syncedAt = syncedAt
      self.data = data
      self.unreadCount = unreadCount
    }
  }

  /// The observable state.
  public struct State: Sendable, Equatable {
    /// The badge value.
    public var unreadCount: UnreadCount
    /// True while a check is in flight.
    public var isFetching: Bool
    /// True when a poll is registered.
    public var isPolling: Bool

    public init(
      unreadCount: UnreadCount = .none,
      isFetching: Bool = false,
      isPolling: Bool = false
    ) {
      self.unreadCount = unreadCount
      self.isFetching = isFetching
      self.isPolling = isPolling
    }
  }

  private let client: NotificationClient
  private let store: QueryStore
  private let preferences: PreferencesEngine?
  private let clock: NotificationClock
  private let scheduler: NotificationPollScheduler
  private let random: NotificationRandomProvider
  private let scope: String?
  private let isActive: @Sendable () -> Bool
  private let hasSession: @Sendable () -> Bool
  private let moderationOpts: @Sendable () -> ModerationOpts?

  private let lock = NSLock()
  private var listeners: [Listener] = []
  private var currentState = State()
  private var cache = CachedPage()
  private var isFetching = false
  private var pollToken: NotificationPollToken?

  /// Creates the coordinator.
  ///
  /// - Parameters:
  ///   - client: the notifications client.
  ///   - store: the query store, for the feed invalidation on an invalidating
  ///     check.
  ///   - preferences: the preferences engine, used to send `updateSeen`. When
  ///     `nil`, mark-all-read still resets local state but sends nothing.
  ///   - clock: the date source.
  ///   - scheduler: the poll scheduler.
  ///   - random: the throttle draw source.
  ///   - scope: account scope, for the feed keys this invalidates.
  ///   - isActive: whether the app is foregrounded. Polls are skipped when it
  ///     is not, matching the RN `AppState.currentState !== 'active'` guard.
  ///   - hasSession: whether a session exists.
  ///   - moderationOpts: options for the poll's moderation pass.
  public init(
    client: NotificationClient,
    store: QueryStore,
    preferences: PreferencesEngine? = nil,
    clock: NotificationClock = SystemNotificationClock(),
    scheduler: NotificationPollScheduler = SystemNotificationPollScheduler(),
    random: NotificationRandomProvider = SystemNotificationRandomProvider(),
    scope: String? = nil,
    isActive: @escaping @Sendable () -> Bool = { true },
    hasSession: @escaping @Sendable () -> Bool = { true },
    moderationOpts: @escaping @Sendable () -> ModerationOpts? = { nil }
  ) {
    self.client = client
    self.store = store
    self.preferences = preferences
    self.clock = clock
    self.scheduler = scheduler
    self.random = random
    self.scope = scope
    self.isActive = isActive
    self.hasSession = hasSession
    self.moderationOpts = moderationOpts
  }

  // MARK: - Observation

  /// Runs `body` in a synchronous critical section.
  ///
  /// `NSLock.lock()` is annotated `noasync`, so it cannot be called directly
  /// from an async context; funnelling every use through this helper keeps the
  /// async methods async-safe and the locking correct.
  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// The current state.
  public var state: State {
    withLock { currentState }
  }

  /// The current cache, for assertion and for the feed's first-page reuse.
  public var cachedPage: CachedPage {
    withLock { cache }
  }

  /// Registers a state observer. The listener is not called immediately; read
  /// ``state`` for the current value.
  public func addListener(_ listener: @escaping Listener) {
    withLock { listeners.append(listener) }
  }

  private func mutateState(_ transform: (inout State) -> Void) {
    let (next, observers) = withLock { () -> (State, [Listener]) in
      transform(&currentState)
      return (currentState, listeners)
    }
    for observer in observers { observer(next) }
  }

  // MARK: - Polling

  /// Starts the periodic sync: one check immediately, then a tick every
  /// ``updateInterval`` seconds. Idempotent.
  public func startPolling() {
    let alreadyPolling = withLock { pollToken != nil }
    guard !alreadyPolling else { return }

    // The on-init fetch, mirroring `checkUnreadRef.current()` in the RN effect.
    Task { [weak self] in
      await self?.checkUnread()
    }

    let token = scheduler.schedule(every: Self.updateInterval) { [weak self] _ in
      await self?.checkUnread(isPoll: true)
    }
    withLock { pollToken = token }
    mutateState { $0.isPolling = true }
  }

  /// Stops the periodic sync. Call on sign-out.
  public func stopPolling() {
    let token = withLock { () -> NotificationPollToken? in
      let current = pollToken
      pollToken = nil
      return current
    }
    token?.cancel()
    mutateState { $0.isPolling = false }
  }

  // MARK: - Checking

  /// Runs one unread check.
  ///
  /// - Parameters:
  ///   - invalidate: when true, the fetched page is marked usable in the feed
  ///     and both feed keys are truncated and invalidated, so the feed picks
  ///     the fresh head up immediately. Subjects are fetched only in this case.
  ///   - isPoll: true for a scheduled tick, which is subject to the throttle.
  public func checkUnread(invalidate: Bool = false, isPoll: Bool = false) async {
    guard hasSession() else { return }
    guard isActive() else { return }

    let cached = cachedPage
    if isPoll, cached.unreadCount != 0 {
      // With a badge showing, polls back off: none at all once the count has
      // saturated, and otherwise a fair coin.
      if cached.unreadCount >= 30 { return }
      if random.next() >= 0.5 { return }
    }

    let alreadyFetching = withLock { () -> Bool in
      if isFetching { return true }
      isFetching = true
      return false
    }
    if alreadyFetching { return }
    mutateState { $0.isFetching = true }
    defer {
      withLock { isFetching = false }
      mutateState { $0.isFetching = false }
    }

    do {
      let fetcher = NotificationPageFetcher(
        client: client,
        moderationOpts: moderationOpts(),
        fetchAdditionalData: invalidate,
        limit: NotificationFeeds.unreadPageSize,
        reasons: []
      )
      let result = try await fetcher.result(cursor: nil)
      let unreadCount = Self.countUnread(result.page)
      let now = clock.now()
      let lastIndexed = result.indexedAt.flatMap(NotificationReasons.parseATProtoDate)

      let next = CachedPage(
        usableInFeed: invalidate,
        syncedAt: Self.syncWatermark(now: now, lastIndexed: lastIndexed),
        data: result.page,
        unreadCount: unreadCount
      )
      withLock { cache = next }
      mutateState { $0.unreadCount = UnreadCount(count: unreadCount) }

      if invalidate {
        await invalidateFeed()
      }
    } catch {
      // A failed check leaves the previous state in place; the next tick
      // retries. Errors are not surfaced as state because the badge is
      // advisory.
    }
  }

  /// The cache watermark: `now`, unless the page's newest row is later.
  ///
  /// Public so a caller can predict the value ``markAllRead()`` will send.
  public static func syncWatermark(now: Date, lastIndexed: Date?) -> Date {
    guard let lastIndexed else { return now }
    return now > lastIndexed ? now : lastIndexed
  }

  /// Counts unread notifications on a page, including grouped ones.
  public static func countUnread(_ page: NotificationFeedPage) -> Int {
    var total = 0
    for item in page.items {
      if !item.notification.isRead { total += 1 }
      for additional in item.additional where !additional.isRead { total += 1 }
    }
    return total
  }

  // MARK: - Mark all read

  /// Marks everything read, up to the cache's sync watermark.
  ///
  /// The port of `markAllRead`. The watermark sent to the server is the cache's
  /// `syncedAt`, not the current time: a page fetched slightly in the past must
  /// not be marked read for notifications that arrived after it. After the
  /// write the local count is reset and the listeners fire.
  ///
  /// - Throws: whatever the `updateSeen` request throws. On failure the local
  ///   state is left untouched, so the badge does not lie about an unread
  ///   backlog the server still holds.
  public func markAllRead() async throws {
    let seenAt = cachedPage.syncedAt
    if let preferences {
      try await preferences.updateSeenNotifications(seenAt)
    } else {
      try await client.updateSeen(seenAt: seenAt)
    }
    withLock { cache.unreadCount = 0 }
    mutateState { $0.unreadCount = .none }
  }

  /// The cached first page, when it is fresh enough to seed the feed.
  public func getCachedUnreadPage() -> NotificationFeedPage? {
    let cached = cachedPage
    return cached.usableInFeed ? cached.data : nil
  }

  /// Marks the cached page unusable as a feed seed, without dropping it. The
  /// port of the `invalidate` emitter in `invalidateCachedUnreadPage()`.
  public func invalidateCachedPage() {
    withLock { cache.usableInFeed = false }
  }

  /// Truncates and invalidates both feed keys.
  private func invalidateFeed() async {
    await store.truncateAndInvalidate(NotificationQueryKey.feed(.all, scope: scope))
    await store.truncateAndInvalidate(NotificationQueryKey.feed(.mentions, scope: scope))
  }
}

/// The state the coordinator publishes, aliased for readability at call sites.
public typealias NotificationUnreadState = NotificationUnreadCoordinator.State
