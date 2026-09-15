import Domain
import Foundation
import Lexicons
import QueryStore

/// One feed's query: an infinite query in a ``QueryStore`` whose pages are
/// tuned through a ``Domain/FeedTuner`` as they arrive.
///
/// This is the Swift counterpart of `usePostFeedQuery` in
/// `src/state/queries/post-feed.ts`. The store holds one tuned ``HomeFeedSlice``
/// per item, which is what lets the ported auto-pagination scheduler count feed
/// content.
///
/// Differences from RN, all structural:
/// - RN keeps raw pages in the cache and derives slices in TanStack's `select`
///   on every render. QueryStore has no `select`, so this type tunes each page
///   inside the page fetcher, while the tuner's cross-page de-duplication state
///   is in scope.
/// - The feed is never time-stale (`STALE.INFINITY`, as in RN); it refreshes
///   explicitly via ``refresh()``.
public struct HomeFeedQuery: Sendable {
  /// The store this feed lives in.
  public let store: QueryStore
  /// This feed's descriptor.
  public let descriptor: FeedDescriptor
  /// The page fetcher, one per feed type.
  public let fetcher: any FeedPageFetcher
  /// This feed's query key.
  public let key: QueryKey
  /// Items per request. RN: `MIN_POSTS`.
  public let limit: Int

  /// Cross-page de-duplication state. One instance belongs to this query and it
  /// must survive across pages, so it is held here rather than created per call.
  private let tuner: TunerBox
  /// The number of posts per page, aggregated for the auto-pagination
  /// threshold. RN passes post counts, not slice counts.
  private let pageItemCounts: Counter

  /// Creates a feed query.
  ///
  /// - Parameters:
  ///   - store: the store to read and write.
  ///   - descriptor: the feed identity, which forms the key.
  ///   - fetcher: the per-type page fetcher.
  ///   - tunerOptions: the preference inputs that select the tuner stack.
  ///   - scope: account scope (the signed-in DID), or `nil` for logged out.
  ///   - limit: items per request.
  public init(
    store: QueryStore,
    descriptor: FeedDescriptor,
    fetcher: any FeedPageFetcher,
    tunerOptions: FeedTunerOptions,
    scope: String? = nil,
    limit: Int = HomeFeedConstants.fetchLimit
  ) {
    self.store = store
    self.descriptor = descriptor
    self.fetcher = fetcher
    self.key = HomeFeedKeys.feed(descriptor, scope: scope)
    self.limit = limit
    self.tuner = TunerBox(FeedTunerFactory.makeTuner(for: descriptor, options: tunerOptions))
    self.pageItemCounts = Counter()
  }

  /// The infinite query over the store. Cheap to build; built on demand.
  private var query: InfiniteQuery<HomeFeedSlice> {
    let fetcher = self.fetcher
    let tuner = self.tuner
    let pageItemCounts = self.pageItemCounts
    let limit = self.limit
    return InfiniteQuery(
      store: store,
      key: key,
      // Slices are identified by their react key, RN's `_reactKey`. That is the
      // thread-level identity, so a reply and its root arriving in different
      // pages collapse rather than double-render.
      identity: { $0.reactKey },
      fetchPage: { request in
        let raw = try await fetcher.fetch(cursor: request.cursor, limit: limit)
        let slices = Self.tune(raw, tuner: tuner)
        pageItemCounts.add(slices.reduce(0) { $0 + $1.items.count })
        return InfiniteQueryData(pages: [
          QueryPage(items: slices, cursor: raw.cursor, requestCursor: request.cursor)
        ])
      })
  }

  /// Tunes a raw page into slices with the query's tuner. The port of
  /// `tuner.tune(page.feed)` in the RN `select`.
  ///
  /// The wire `feedViewPost` is wrapped into the Domain ``FeedViewPost``, which
  /// carries the AppView numbering fields and the app-internal `__source` marker
  /// the tuner reads.
  static func tune(_ raw: RawFeedPage, tuner: TunerBox) -> [HomeFeedSlice] {
    let feed = raw.feed.map(FeedViewPost.init)
    return tuner.tune(feed).map(makeHomeFeedSlice(from:))
  }

  // MARK: - Reading

  /// The held data. The store payload already is the tuned model.
  public func data() async -> HomeFeedData {
    await query.data()
  }

  /// The typed entry, for status/error rendering.
  public func entry() async -> QueryEntry<HomeFeedData> {
    await query.entry()
  }

  /// Every tuned slice across every page.
  public func slices() async -> [HomeFeedSlice] {
    await data().items
  }

  /// The held data grouped back into pages, for callers that need page
  /// boundaries (for example to peek page one).
  public func pageGroupedData() async -> [HomeFeedPage] {
    (await data()).feedPages
  }

  /// The number of posts across every page, RN's `itemCount`.
  public func itemCount() async -> Int {
    await data().items.reduce(0) { $0 + $1.items.count }
  }

  /// True when no page has produced a slice.
  public func isEmpty() async -> Bool {
    await data().isEmptyFeed
  }

  /// Pagination state for this feed.
  public func paginationState() async -> PaginationState {
    await store.paginationState(for: key)
  }

  // MARK: - Fetching

  /// Loads the first page, replacing whatever was held.
  @discardableResult
  public func loadFirstPage(force: Bool = false) async throws -> HomeFeedData {
    pageItemCounts.reset()
    _ = try await query.loadFirstPage(
      staleTime: HomeFeedStale.feedPage, force: force)
    let data = await query.data()
    pageItemCounts.set(data.items.reduce(0) { $0 + $1.items.count })
    return data
  }

  /// Appends the next page, returning the whole merged list.
  ///
  /// Re-reads the store after the request because an infinite fetch resolves to
  /// the page it just fetched, not to the accumulated list.
  @discardableResult
  public func loadMore() async throws -> HomeFeedData {
    _ = try await query.loadMore()
    return await query.data()
  }

  /// Requests `cursor` as an appended page, returning the merged list.
  @discardableResult
  public func fetchPage(at cursor: String?) async throws -> HomeFeedData {
    _ = try await query.fetchPage(at: cursor, isAppending: true)
    return await query.data()
  }

  /// Refetches page one and drops the rest - the port of `truncateAndInvalidate`
  /// in `src/state/queries/util.ts`.
  ///
  /// RN truncates the cached pages to one and invalidates, letting the active
  /// observer perform the single refetch. `QueryStore.truncateAndInvalidate`
  /// does both, so this makes exactly one request.
  @discardableResult
  public func refresh() async throws -> HomeFeedData {
    pageItemCounts.reset()
    _ = await store.truncateAndInvalidate(key)
    let data = await query.data()
    pageItemCounts.set(data.items.reduce(0) { $0 + $1.items.count })
    return data
  }

  /// Keeps fetching until the tuned list reaches the threshold or the walk ends.
  ///
  /// Port of `useAutoPagination(query, itemCount, MIN_POSTS)`. RN passes the
  /// rendered *post* count; the scheduler's own stop condition counts slices, so
  /// `itemCount` is this feed's post count aggregated across pages.
  @discardableResult
  public func autoPaginate() async -> Int {
    await store.autoPaginate(
      key, itemCount: pageItemCounts.value, pageSize: limit,
      maxAttempts: HomeFeedConstants.autoPaginationMaxAttempts)
  }

  /// Polls for a new head item. Port of `pollLatest` in `post-feed.ts`.
  ///
  /// Peeking asks the appview for a single item, then runs it through a *dry
  /// run* of the same tuner: an item the tuner would drop does not count as
  /// news. The dry run does not mutate the tuner's seen sets, so the real
  /// refresh that follows can still admit the item.
  ///
  /// - Returns: `true` when the newest item would survive tuning, i.e. the feed
  ///   has something new to show.
  public func pollLatest() async throws -> Bool {
    guard let post = try await fetcher.peekLatest() else { return false }
    let slices = tuner.tune([FeedViewPost(post)], dryRun: true)
    return !slices.isEmpty
  }

  // MARK: - Writing

  /// Replaces the whole page list. The optimistic-update primitive.
  public func setData(_ slices: [HomeFeedSlice], cursor: String? = nil) async {
    await query.setData(InfiniteQueryData(pages: [QueryPage(items: slices, cursor: cursor)]))
  }

  /// Removes this feed's entry from the store.
  public func remove() async {
    await store.remove(key)
  }

  // MARK: - Observation

  /// Registers a closure invoked with the tuned slices whenever the feed
  /// changes. Called once immediately with the current slices.
  @discardableResult
  public func subscribeSlices(
    onChange: @escaping @Sendable ([HomeFeedSlice]) -> Void
  ) async -> QuerySubscription {
    await query.subscribeItems(onChange: onChange)
  }
}

/// A reference box around a ``Domain/FeedTuner``.
///
/// `FeedTuner` is a class with mutable cross-page state, and ``HomeFeedQuery`` is
/// a `Sendable` value whose methods run concurrently, so the tuner is confined
/// behind a lock: page fetches for one feed must not interleave their tuning.
final class TunerBox: @unchecked Sendable {
  private let lock = NSLock()
  private let tuner: FeedTuner

  init(_ tuner: FeedTuner) {
    self.tuner = tuner
  }

  /// Tunes `feed`, serialized against other tuning on the same box.
  func tune(_ feed: [FeedViewPost], dryRun: Bool = false) -> [FeedViewPostsSlice] {
    lock.lock()
    defer { lock.unlock() }
    return tuner.tune(feed, dryRun: dryRun)
  }

  /// Snapshot of the de-duplication state, for tests and diagnostics.
  var seenState: (keys: Set<String>, uris: Set<String>, roots: Set<String>) {
    lock.lock()
    defer { lock.unlock() }
    return (tuner.seenKeys, tuner.seenUris, tuner.seenRootUris)
  }
}

/// A counter confined behind a lock, for the cross-page post tally.
final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func add(_ delta: Int) {
    lock.lock()
    defer { lock.unlock() }
    count += delta
  }

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    count = 0
  }

  func set(_ value: Int) {
    lock.lock()
    defer { lock.unlock() }
    count = value
  }
}
