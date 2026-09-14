import Foundation

/// A strongly typed handle to one infinite query in a ``QueryStore``.
///
/// `InfiniteQuery` is the Swift counterpart of a `useInfiniteQuery` call: it owns
/// the key, the page fetcher, the cursor walk (`getNextPageParam: lastPage =>
/// lastPage.cursor`) and the de-dupe-on-merge policy, and keeps the store's
/// pagination bookkeeping in step.
///
/// The wrapper is cheap: it is a value holding a store reference and a key.
/// Create one at the point of use rather than caching it.
///
/// ```swift
/// let query = InfiniteQuery(
///   store: store,
///   key: QueryKey("feed", FeedArgs(feed: "discover")),
///   identity: { $0.uri },
///   page: { cursor in
///     let page = try await client.discoverFeed(cursor: cursor, limit: 30)
///     return QueryPage(items: page.posts, cursor: page.cursor)
///   }
/// )
/// let first = try await query.loadFirstPage()
/// let more = try await query.loadMore()
/// ```
public struct InfiniteQuery<Item: Sendable>: Sendable {
  /// The store this query lives in.
  public let store: QueryStore
  /// This query's key.
  public let key: QueryKey
  /// True when the key carries a `persistedVersion`, which makes the query
  /// eligible for persistence.
  public let isPersisted: Bool

  private let fetchPage: @Sendable (QueryFetchRequest) async throws -> InfiniteQueryData<Item>
  private let identity: @Sendable (Item) -> String

  /// Creates an infinite query over `key`.
  ///
  /// - Parameters:
  ///   - store: the store to read and write.
  ///   - key: this query's key. Set `persistedVersion` to make it persistable.
  ///   - identity: dedupe-on-merge hook. Two items sharing an identity in
  ///     different pages collapse to the earlier one.
  ///   - fetchPage: fetches one page. The request carries the cursor and whether
  ///     the page is an append.
  public init(
    store: QueryStore,
    key: QueryKey,
    identity: @escaping @Sendable (Item) -> String,
    fetchPage: @escaping @Sendable (QueryFetchRequest) async throws -> InfiniteQueryData<Item>
  ) {
    self.store = store
    self.key = key
    self.identity = identity
    self.fetchPage = fetchPage
    self.isPersisted = key.persistedVersion != nil
  }

  /// Creates an infinite query from a page-returning closure.
  ///
  /// This is the common shape: one request per page, one cursor in and one cursor
  /// out. The returned page is tagged with the cursor that requested it so the
  /// store can detect a repeated cursor.
  public init(
    store: QueryStore,
    key: QueryKey,
    identity: @escaping @Sendable (Item) -> String,
    page: @escaping @Sendable (_ cursor: String?) async throws -> QueryPage<Item>
  ) {
    self.init(store: store, key: key, identity: identity) { request in
      let page = try await page(request.cursor)
      let resolved = QueryPage(
        items: page.items,
        cursor: page.cursor,
        requestCursor: page.requestCursor ?? request.cursor
      )
      return InfiniteQueryData(pages: [resolved])
    }
  }

  // MARK: - Reading

  /// The entry as it stands, without fetching.
  public func entry() async -> QueryEntry<InfiniteQueryData<Item>> {
    await store.entry(key, as: InfiniteQueryData<Item>.self)
  }

  /// The held pages, or an empty list.
  public func data() async -> InfiniteQueryData<Item> {
    (try? await store.payload(key, as: InfiniteQueryData<Item>.self)) ?? InfiniteQueryData()
  }

  /// Every item across every page, in order. The flattened accessor a list view
  /// iterates.
  public func items() async -> [Item] {
    await data().items
  }

  /// Pagination state: page count, item count and next cursor.
  public func paginationState() async -> PaginationState {
    await store.paginationState(for: key)
  }

  /// True while another page can be requested.
  public func hasNextPage() async -> Bool {
    await paginationState().hasNextPage
  }

  // MARK: - Fetching

  /// Loads the first page, replacing any pages already held.
  @discardableResult
  public func loadFirstPage(
    staleTime: TimeInterval? = nil,
    force: Bool = false
  ) async throws -> InfiniteQueryData<Item> {
    try await store.fetch(
      key,
      plan: plan(force: force, staleTime: staleTime, resetsPages: true),
      request: QueryFetchRequest()
    ) { [fetchPage] request in try await fetchPage(request) }
  }

  /// Appends the next page, if there is one.
  ///
  /// - Returns: the whole page list after the request, or the current list when
  ///   the query is already exhausted. Reaching the end is not an error, so this
  ///   returns the list unmodified instead of throwing.
  @discardableResult
  public func loadMore() async throws -> InfiniteQueryData<Item> {
    let state = await store.paginationState(for: key)
    guard state.hasNextPage, let cursor = state.nextCursor, !state.repeatsCursor(cursor) else {
      return await data()
    }
    return try await fetchPage(at: cursor, isAppending: true)
  }

  /// Requests the page named by `cursor`, appending it.
  @discardableResult
  public func fetchPage(at cursor: String?, isAppending: Bool = true) async throws -> InfiniteQueryData<Item> {
    let pageCount = await store.paginationState(for: key).pageCount
    let request = QueryFetchRequest(cursor: cursor, isAppending: isAppending, pageIndex: pageCount)
    return try await store.fetch(
      key,
      plan: plan(force: false, staleTime: nil, resetsPages: !isAppending),
      request: request
    ) { [fetchPage] request in try await fetchPage(request) }
  }

  /// Refetches page one and drops the pages behind it.
  ///
  /// The Swift port of `truncateAndInvalidate`: the feed jumps back to a single
  /// fresh head instead of splicing new results into a stale list.
  @discardableResult
  public func refresh() async throws -> InfiniteQueryData<Item> {
    _ = await store.truncateAndInvalidate(key)
    return try await loadFirstPage(force: true)
  }

  /// Keeps requesting next pages until the rendered list reaches the threshold.
  ///
  /// - Parameters:
  ///   - itemCount: items currently rendered.
  ///   - pageSize: items one page is expected to provide.
  ///   - maxAttempts: request cap, five by default, as in the RN hook.
  /// - Returns: the number of pages requested.
  @discardableResult
  public func autoPaginate(
    itemCount: Int,
    pageSize: Int,
    maxAttempts: Int = QueryStore.autoPaginationMaxAttempts
  ) async -> Int {
    await store.autoPaginate(key, itemCount: itemCount, pageSize: pageSize, maxAttempts: maxAttempts)
  }

  // MARK: - Writing

  /// Replaces the whole page list. The optimistic-update primitive for feeds.
  ///
  /// Pagination descriptors are rebuilt from the new list, so subsequent
  /// `loadMore` calls walk the cursors of the data just written.
  public func setData(_ data: InfiniteQueryData<Item>) async {
    var running = 0
    let descriptors = data.pages.map { page -> PageDescriptor in
      running += page.items.count
      return PageDescriptor(
        requestCursor: page.requestCursor,
        cursor: page.cursor,
        totalItemCount: running
      )
    }
    await store.setQueryData(data, for: key, persist: isPersisted, descriptors: descriptors)
  }

  /// Rewrites the held items, e.g. to apply a like or repost locally.
  ///
  /// The transform works on the flattened item list, and the result is written
  /// back as a single page: once items have been edited locally, the original
  /// page boundaries no longer mean anything.
  public func updateItems(_ transform: @Sendable ([Item]) -> [Item]) async {
    guard let current = try? await store.payload(key, as: InfiniteQueryData<Item>.self) else {
      return
    }
    let updated = InfiniteQueryData(
      pages: [
        QueryPage(
          items: transform(current.items),
          cursor: current.nextCursor,
          requestCursor: current.lastRequestCursor
        )
      ]
    )
    await setData(updated)
  }

  /// Removes the query from the store.
  public func remove() async {
    await store.remove(key)
  }

  // MARK: - Observation

  /// Registers a closure invoked with the flattened items whenever the query
  /// changes. The closure is called once immediately with the current items.
  @discardableResult
  public func subscribeItems(
    onChange: @escaping @Sendable ([Item]) -> Void
  ) async -> QuerySubscription {
    await store.subscribe(key, as: InfiniteQueryData<Item>.self) { data in
      onChange(data.items)
    }
  }

  // MARK: - Internals

  private func plan(force: Bool, staleTime: TimeInterval?, resetsPages: Bool) -> FetchPlan {
    FetchPlan(
      staleTime: staleTime,
      force: force,
      isInfinite: true,
      persist: isPersisted,
      resetsPages: resetsPages,
      merge: { [identity] existing, incoming, _ in
        guard let held = existing.decode(as: InfiniteQueryData<Item>.self),
          let incomingData = incoming as? InfiniteQueryData<Item>,
          let page = incomingData.pages.first
        else { return nil }
        return .decoded(held.merging(page, policy: .deduplicate(by: identity)))
      },
      describe: { payload, request in
        // Called on the stored payload, so `itemCount` already reflects any
        // de-duplication the merge performed.
        guard let data = payload as? InfiniteQueryData<Item>, let page = data.pages.last else {
          return nil
        }
        return PageDescriptor(
          requestCursor: page.requestCursor ?? request.cursor,
          cursor: page.cursor,
          totalItemCount: data.itemCount
        )
      }
    )
  }
}

extension PaginationState {
  /// True when `cursor` already produced an earlier page, which means a request
  /// for it would loop.
  ///
  /// - Note: this variant only knows the cursor of the last page. The store's
  ///   internal check inspects every page; callers that need the full check should
  ///   rely on ``QueryStore/loadMore``'s refusal to reissue a repeated cursor.
  public func repeatsCursor(_ cursor: String?) -> Bool {
    guard let cursor else { return false }
    return nextCursor == cursor && pageCount > 1
  }
}
