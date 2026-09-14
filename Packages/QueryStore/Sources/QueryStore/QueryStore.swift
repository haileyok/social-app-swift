import Foundation

/// The cache.
///
/// `QueryStore` is the Swift counterpart of the app's single per-account TanStack
/// `QueryClient`. It holds entries, de-duplicates concurrent fetches for the same
/// key, and notifies closure subscribers when entries change.
///
/// ## Concurrency
///
/// The store is an actor, so every mutation is serialized. Network work never
/// runs inside the actor: each fetch runs in its own `Task`, and only the
/// completion hop re-enters the actor to publish. That is what lets a slow
/// request sit in flight while other keys keep being read and written, and it is
/// what makes de-duplication possible - there is exactly one task per key.
///
/// ## Subscribers
///
/// No Observation, no SwiftUI. ``subscribe(_:as:onChange:)`` registers a closure
/// invoked with the typed payload for one key; ``onEvent(_:)`` registers a
/// closure that sees every transition. Both return a ``QuerySubscription`` that
/// detaches them. The observable wrapper a SwiftUI layer needs belongs in a
/// `Views` target, not here.
///
/// ```swift
/// let store = QueryStore()
/// let key = QueryKey("feed", FeedArgs(feed: "discover", limit: 30))
/// let feed = try await store.fetch(key) {
///   try await client.discoverFeed(limit: 30)
/// }
/// ```
public actor QueryStore {
  /// Default staleness budget for keys with no override.
  public let defaultStaleTime: TimeInterval

  let clock: any QueryClock
  let persistSink: (any QueryPersistSink)?
  let versionBuster: String

  /// Entries, keyed by key. Payloads are erased: the store never decodes one.
  var entries: [QueryKey: QueryEntry<StoredPayload>] = [:]
  /// The typed logic and fetcher for keys that have been touched.
  var runtimes: [QueryKey: KeyRuntime] = [:]
  /// The cursor chain for infinite queries, including ones written without a fetch.
  var pageChains: [QueryKey: PageChain] = [:]
  /// The single in-flight task per key. This dictionary is the de-duplication.
  var inFlight: [QueryKey: Task<any Sendable, any Error>] = [:]
  var keySubscribers: [QueryKey: [UUID: @Sendable (any Sendable) -> Void]] = [:]
  var eventObservers: [UUID: @Sendable (QueryEvent) -> Void] = [:]
  /// Background auto-pagination runs, one per key.
  var autoPaginationTasks: [QueryKey: Task<Void, Never>] = [:]
  var persistTask: Task<Void, Never>?

  /// Creates a store.
  ///
  /// - Parameters:
  ///   - clock: time source for staleness. Injectable so tests are
  ///     deterministic.
  ///   - persistSink: destination for persisted snapshots, or `nil` to disable
  ///     persistence entirely.
  ///   - versionBuster: app-version string. A snapshot written under a different
  ///     buster is discarded wholesale, matching the TanStack `buster` option the
  ///     RN app sets to `env.APP_VERSION`.
  ///   - defaultStaleTime: staleness budget applied to keys with no override.
  public init(
    clock: any QueryClock = SystemQueryClock(),
    persistSink: (any QueryPersistSink)? = nil,
    versionBuster: String = "",
    defaultStaleTime: TimeInterval = STALE.MINUTES.ONE
  ) {
    self.clock = clock
    self.persistSink = persistSink
    self.versionBuster = versionBuster
    self.defaultStaleTime = defaultStaleTime
  }

  // MARK: - Reading

  /// The current time according to the injected clock.
  public var now: Int64 { clock.nowMicroseconds() }

  /// A type-erased read of the entry for `key`.
  public func snapshot(for key: QueryKey) -> QueryEntrySnapshot? {
    entries[key]?.snapshot
  }

  /// The typed entry for `key`, or an empty entry when it has never been touched.
  ///
  /// An entry restored from a persisted snapshot is decoded here, which is what
  /// turns lazily-restored bytes back into a typed payload.
  public func entry<Data: Sendable>(_ key: QueryKey, as type: Data.Type) -> QueryEntry<Data> {
    guard let stored = entries[key] else {
      return QueryEntry<Data>.empty(staleTime: defaultStaleTime)
    }
    return QueryEntry<Data>(
      status: stored.status,
      data: stored.data?.decode(as: Data.self),
      error: stored.error,
      fetchedAt: stored.fetchedAt,
      fetchStartedAt: stored.fetchStartedAt,
      staleTime: stored.staleTime,
      isFetching: stored.isFetching,
      isInvalidated: stored.isInvalidated,
      isInfinite: stored.isInfinite,
      failureCount: stored.failureCount
    )
  }

  /// The payload for `key`, or `nil` when there is none or it is another type.
  ///
  /// - Throws: ``QueryTypeMismatchError`` when the entry holds a live payload of
  ///   a different type, which means one key was reused with two payload types.
  public func payload<Data: Sendable>(_ key: QueryKey, as type: Data.Type) throws -> Data? {
    guard let stored = entries[key], let payload = stored.data else { return nil }
    if let typed = payload.decode(as: Data.self) { return typed }
    if payload.erasedValue == nil { return nil }
    throw QueryTypeMismatchError(key: key, expected: String(describing: Data.self))
  }

  /// True when a fetch is in flight for `key`.
  public func isFetching(_ key: QueryKey) -> Bool { inFlight[key] != nil }

  /// True when `key` has no entry, or its data is older than its stale time.
  public func isStale(_ key: QueryKey) -> Bool {
    guard let entry = entries[key] else { return true }
    return entry.isStale(now: clock.nowMicroseconds())
  }

  /// True when a fetch would actually start for `key`.
  public func shouldFetch(_ key: QueryKey, force: Bool = false) -> Bool {
    guard let entry = entries[key] else { return true }
    return entry.needsFetch(now: clock.nowMicroseconds(), force: force, appendingPage: false)
  }

  /// Number of entries currently held.
  public var entryCount: Int { entries.count }

  /// Every key currently held, ordered by description for stable output.
  public var keys: [QueryKey] { entries.keys.sorted { $0.description < $1.description } }

  /// Keys whose root matches, for bulk invalidation and eviction.
  public func keys(root: String) -> [QueryKey] {
    keys.filter { $0.keyRoot == root }
  }

  /// True when the newest page was requested with a cursor that an earlier page
  /// already used, which means the walk is looping.
  func hasRepeatedCursor(_ key: QueryKey) -> Bool {
    pageChains[key]?.hasRepeatedCursor ?? false
  }

  /// The staleness budget in effect for `key`.
  public func staleTime(for key: QueryKey) -> TimeInterval {
    entries[key]?.staleTime ?? defaultStaleTime
  }

  /// Pagination state for `key`, or ``PaginationState/none`` when it is not an
  /// infinite query.
  public func paginationState(for key: QueryKey) -> PaginationState {
    guard let chain = pageChains[key] else { return .none }
    return chain.state
  }

  // MARK: - Fetching

  /// Fetches `key`, starting a request only when the entry is missing or stale.
  ///
  /// Concurrent calls for the same key share one in-flight request: every caller
  /// awaits the same task and receives the same payload, which is the
  /// de-duplication TanStack performs by attaching to an existing fetch.
  ///
  /// - Parameters:
  ///   - key: entry to fetch.
  ///   - staleTime: per-key override of the store default.
  ///   - force: fetch even when the entry is fresh.
  ///   - persist: offer the successful payload to the persistence sink.
  ///   - fetcher: performs the request. Called at most once per in-flight window.
  /// - Returns: the payload held after the fetch.
  @discardableResult
  public func fetch<Data: Sendable>(
    _ key: QueryKey,
    staleTime: TimeInterval? = nil,
    force: Bool = false,
    persist: Bool = false,
    fetcher: @escaping @Sendable () async throws -> Data
  ) async throws -> Data {
    let plan = FetchPlan(staleTime: staleTime, force: force, persist: persist, resetsPages: true)
    return try await fetch(key, plan: plan, request: QueryFetchRequest()) { _ in
      try await fetcher()
    }
  }

  /// The plan-driven fetch used by ``InfiniteQuery`` and by the simple overloads.
  ///
  /// `plan.describe` decides whether this is a page append. The store applies
  /// that decision to both the payload merge and the descriptor list, so an
  /// "append" send that a reducer rejected does not corrupt pagination state.
  @discardableResult
  func fetch<Data: Sendable>(
    _ key: QueryKey,
    plan: FetchPlan,
    request: QueryFetchRequest,
    fetcher: @escaping @Sendable (QueryFetchRequest) async throws -> Data
  ) async throws -> Data {
    register(key, plan: plan, fetcher: fetcher)

    if let existing = inFlight[key] {
      return try Self.cast(try await existing.value, key: key, as: Data.self)
    }
    if !shouldStartFetch(key: key, plan: plan, request: request) {
      if let current = try payload(key, as: Data.self) { return current }
    }
    let payload = try await startFetch(
      key: key,
      plan: plan,
      request: request,
      reason: resolveReason(key: key, plan: plan, request: request)
    )
    return try Self.cast(payload, key: key, as: Data.self)
  }

  /// Fetches `key` and returns the whole typed entry.
  @discardableResult
  public func fetchEntry<Data: Sendable>(
    _ key: QueryKey,
    staleTime: TimeInterval? = nil,
    force: Bool = false,
    persist: Bool = false,
    fetcher: @escaping @Sendable () async throws -> Data
  ) async throws -> QueryEntry<Data> {
    _ = try await fetch(key, staleTime: staleTime, force: force, persist: persist, fetcher: fetcher)
    return entry(key, as: Data.self)
  }

  /// Registers a fetcher for `key` without running a request, so later
  /// invalidation and auto-pagination can run it.
  public func registerFetcher<Data: Sendable>(
    _ key: QueryKey,
    staleTime: TimeInterval? = nil,
    persist: Bool = false,
    fetcher: @escaping @Sendable () async throws -> Data
  ) {
    register(
      key,
      plan: FetchPlan(staleTime: staleTime, persist: persist, resetsPages: true),
      fetcher: { _ in try await fetcher() }
    )
  }

  /// Runs the registered fetcher for `key`, optionally requesting `cursor`.
  ///
  /// `invalidate` and auto-pagination use this so callers do not need to hold a
  /// reference to the fetcher.
  @discardableResult
  func refetch(_ key: QueryKey, cursor: String? = nil, reason: QueryFetchReason) async throws -> (any Sendable)? {
    guard let runtime = runtimes[key] else { return entries[key]?.data?.erasedValue }
    var plan = runtime.plan
    plan.reason = reason
    plan.force = cursor == nil
    if cursor != nil { plan = plan.markingAppend(cursor: cursor) }
    if let existing = inFlight[key] { return try await existing.value }
    let request = QueryFetchRequest(
      cursor: cursor,
      isAppending: cursor != nil,
      pageIndex: pageChains[key]?.pageCount ?? 0
    )
    return try await startFetch(key: key, plan: plan, request: request, reason: reason)
  }

}

extension QueryStore {
  // MARK: - Writing

  /// Replaces the payload for `key`. This is the optimistic-update primitive.
  ///
  /// The entry is stamped fresh at the current time, so an optimistic write
  /// counts as fresh until it is invalidated or a rollback restores the previous
  /// value.
  public func setQueryData<Data: Sendable>(
    _ data: Data,
    for key: QueryKey,
    persist: Bool = false
  ) {
    setQueryData(data, for: key, persist: persist, descriptors: nil)
  }

  /// Replaces the payload for `key` and, for infinite payloads, its cursor chain.
  ///
  /// - Parameter descriptors: page metadata for an infinite payload. Supplied by
  ///   ``InfiniteQuery``, the only caller that can derive it.
  func setQueryData<Data: Sendable>(
    _ data: Data,
    for key: QueryKey,
    persist: Bool = false,
    descriptors: [PageDescriptor]?
  ) {
    var entry = entries[key] ?? QueryEntry<StoredPayload>.empty(staleTime: defaultStaleTime)
    entry.status = .success
    entry.data = .decoded(data)
    entry.error = nil
    entry.fetchedAt = clock.nowMicroseconds()
    entry.isInvalidated = false
    entry.failureCount = 0
    entries[key] = entry
    if let descriptors {
      pageChains[key] = PageChain(pages: descriptors)
    }
    notify(event: .dataSet(key: key, payload: data))
    notifySubscribers(key: key, payload: data)
    if persist { schedulePersist() }
  }

  /// Updates the payload for `key` in place, given the current payload.
  ///
  /// The closure receives the current payload and returns its replacement, or
  /// `nil` to clear the entry. Nothing happens when the key has no payload of
  /// type `Data`.
  public func updateQueryData<Data: Sendable>(
    _ key: QueryKey,
    as type: Data.Type,
    persist: Bool = false,
    _ transform: @Sendable (Data) -> Data?
  ) {
    guard let current = try? payload(key, as: Data.self) else { return }
    if let updated = transform(current) {
      setQueryData(updated, for: key, persist: persist)
    } else {
      clearQueryData(key)
    }
  }

  /// Clears the payload for `key`, leaving the entry in place.
  public func clearQueryData(_ key: QueryKey) {
    guard var entry = entries[key] else { return }
    entry.data = nil
    entry.fetchedAt = nil
    entry.status = .idle
    entries[key] = entry
    notify(event: .dataSet(key: key, payload: nil))
    schedulePersist()
  }

  /// Removes the entry for `key` entirely.
  public func remove(_ key: QueryKey) {
    inFlight[key]?.cancel()
    inFlight[key] = nil
    autoPaginationTasks[key]?.cancel()
    autoPaginationTasks[key] = nil
    runtimes[key] = nil
    pageChains[key] = nil
    entries[key] = nil
    notify(event: .removed(key: key))
    schedulePersist()
  }

  /// Removes entries whose root matches.
  public func remove(root: String) {
    for key in keys(root: root) { remove(key) }
  }

  /// Removes every entry. The RN app does this by re-keying the provider on
  /// `currentDid`; a single shared store does it explicitly on account change.
  public func removeAll() {
    for task in inFlight.values { task.cancel() }
    inFlight.removeAll()
    for task in autoPaginationTasks.values { task.cancel() }
    autoPaginationTasks.removeAll()
    runtimes.removeAll()
    pageChains.removeAll()
    entries.removeAll()
    notify(event: .removedAll)
    schedulePersist()
  }

  // MARK: - Invalidation

  /// Marks `key` stale and, by default, refetches it.
  ///
  /// Invalidation preserves the payload: the entry keeps showing its old data
  /// while the refetch is in flight. This is what makes a failed refresh keep
  /// rendering stale content instead of an empty state, and it matches
  /// TanStack's `invalidateQueries`.
  ///
  /// - Returns: the payload held after the attempt, or `nil` when there is none.
  @discardableResult
  public func invalidate(_ key: QueryKey, refetch shouldRefetch: Bool = true) async -> (any Sendable)? {
    if var entry = entries[key] {
      entry.isInvalidated = true
      entries[key] = entry
    }
    guard shouldRefetch, runtimes[key] != nil else { return entries[key]?.data?.erasedValue }
    do {
      return try await refetch(key, cursor: nil, reason: .invalidated)
    } catch {
      return entries[key]?.data?.erasedValue
    }
  }

  /// Marks keys whose root matches as stale and refetches them.
  public func invalidate(root: String, refetch: Bool = true) async {
    for key in keys(root: root) {
      await invalidate(key, refetch: refetch)
    }
  }

  /// Marks every entry stale without refetching.
  public func invalidateAll() {
    for (key, var entry) in entries {
      entry.isInvalidated = true
      entries[key] = entry
    }
  }

  /// Keeps only the first page of the infinite data at `key`, then invalidates.
  ///
  /// The Swift port of `truncateAndInvalidate` in `src/state/queries/util.ts`,
  /// which is how the RN app force-refreshes a feed: drop back to one page so
  /// the next render starts from a fresh head, then refetch.
  @discardableResult
  public func truncateAndInvalidate(_ key: QueryKey) async -> (any Sendable)? {
    if var chain = pageChains[key], !chain.pages.isEmpty {
      chain.pages = Array(chain.pages.prefix(1))
      pageChains[key] = chain
    }
    return await invalidate(key)
  }

}

extension QueryStore {
  // MARK: - Persistence

  /// Writes successful, persisted-versioned entries to the sink and awaits the
  /// write. Call it on background, on a debounce, or on sign-out.
  public func persist() async {
    guard persistSink != nil else { return }
    if let pending = persistTask {
      await pending.value
      return
    }
    await startPersist()?.value
  }

  /// Restores entries from the sink.
  ///
  /// A snapshot whose buster differs from the store's is discarded, and so is an
  /// entry whose `persistedVersion` differs from the live key's. Payload bytes
  /// are held encoded until the first typed read, so restoring does not require
  /// knowing payload types up front.
  ///
  /// - Parameter scopes: account scopes to read. Pass the signed-in DID (and
  ///   `nil` for the signed-out cache) rather than relying on discovery: a store
  ///   that has not restored anything yet has no way to guess which accounts have
  ///   snapshots on disk. Defaults to scopes already held plus
  ///   ``QueryStore/loggedOutScope``.
  /// - Returns: the number of entries restored.
  @discardableResult
  public func restorePersisted(scopes: [String]? = nil) async -> Int {
    guard let persistSink else { return 0 }
    var restored = 0
    for scope in scopes ?? knownScopes() {
      guard let snapshot = try? await persistSink.load(scope: scope) else { continue }
      restored += restore(snapshot)
    }
    return restored
  }

  /// The scope name the RN app uses for a signed-out cache:
  /// `createPersistedQueryStorage(currentDid ?? 'logged-out')`.
  public static let loggedOutScope = "logged-out"

  /// Clears the cache and removes persisted state. Call on sign-out.
  ///
  /// - Parameter scopes: account scopes whose snapshots should be deleted.
  ///   Defaults to the scopes the cache knew about before it was cleared.
  public func signOut(scopes: [String]? = nil) async {
    let scopesToClear = scopes ?? knownScopes()
    removeAll()
    await persistTask?.value
    persistTask = nil
    guard let persistSink else { return }
    for scope in scopesToClear {
      try? await persistSink.remove(scope: scope)
    }
  }
}

extension QueryStore {
  // MARK: - Observation

  /// Registers a closure invoked with the typed payload whenever `key` changes.
  ///
  /// The closure is called once immediately with the current payload, when there
  /// is one, so a subscriber can render without a separate read.
  ///
  /// - Returns: a handle that detaches the subscription.
  @discardableResult
  public func subscribe<Data: Sendable>(
    _ key: QueryKey,
    as type: Data.Type,
    onChange: @escaping @Sendable (Data) -> Void
  ) -> QuerySubscription {
    let id = UUID()
    keySubscribers[key, default: [:]][id] = { payload in
      if let typed = payload as? Data { onChange(typed) }
    }
    if let current = try? payload(key, as: Data.self) {
      onChange(current)
    }
    return QuerySubscription { [weak self] in
      await self?.removeSubscriber(key: key, id: id)
    }
  }

  /// Registers a closure invoked with every transition in the store.
  ///
  /// - Returns: a handle that detaches the observer.
  @discardableResult
  public func onEvent(_ observer: @escaping @Sendable (QueryEvent) -> Void) -> QuerySubscription {
    let id = UUID()
    eventObservers[id] = observer
    return QuerySubscription { [weak self] in
      await self?.removeObserver(id: id)
    }
  }

  /// Number of subscribers currently attached to `key`. Used by tests.
  public func subscriberCount(for key: QueryKey) -> Int {
    keySubscribers[key]?.count ?? 0
  }

  /// Number of store-wide observers currently attached. Used by tests.
  public var observerCount: Int { eventObservers.count }

}
