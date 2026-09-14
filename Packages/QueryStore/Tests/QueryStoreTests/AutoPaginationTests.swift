import Foundation
import Testing

@testable import QueryStore

/// Covers the auto-pagination semantics of `useAutoPagination` in
/// `src/state/queries/util.ts`: keep requesting the next page while the rendered
/// list is short of the threshold, and never exceed `MAX_ATTEMPTS` (5) pages.
@Suite("Auto-pagination")
struct AutoPaginationTests {
  /// A feed where every page holds `itemsPerPage` items and reports a fresh
  /// cursor, so pagination continues until a bound stops it.
  private func makeEndlessFeed(
    store: QueryStore,
    key: QueryKey,
    itemsPerPage: Int,
    cursorPrefix: String = "cursor"
  ) -> InfiniteQuery<Int> {
    InfiniteQuery<Int>(store: store, key: key, identity: { String($0) }, page: { cursor in
      let pageIndex = cursor.flatMap { Int($0.replacingOccurrences(of: cursorPrefix, with: "")) } ?? 0
      let start = pageIndex * itemsPerPage
      let items = Array(start..<(start + itemsPerPage))
      return QueryPage(
        items: items,
        cursor: "\(cursorPrefix)\(pageIndex + 1)",
        requestCursor: cursor
      )
    })
  }

  @Test("MAX_ATTEMPTS matches the RN hook")
  func maxAttemptsConstant() {
    #expect(QueryStore.autoPaginationMaxAttempts == 5)
  }

  @Test("auto-pagination stops at the attempt bound even when the list stays short")
  func stopsAtBound() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    // Each page holds one item, so a threshold of 100 items can never be met.
    let query = makeEndlessFeed(store: store, key: key, itemsPerPage: 1)

    _ = try await query.loadFirstPage()
    let requested = await query.autoPaginate(itemCount: 1, pageSize: 100, maxAttempts: 5)

    #expect(requested == 5, "the walk is capped at MAX_ATTEMPTS")
    let state = await query.paginationState()
    #expect(state.pageCount == 6, "one initial page plus five requested")
  }

  @Test("auto-pagination stops as soon as the threshold is reached")
  func stopsWhenSatisfied() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeEndlessFeed(store: store, key: key, itemsPerPage: 10)

    _ = try await query.loadFirstPage()
    // 30 items are wanted and each page adds 10, so one more page suffices.
    let requested = await query.autoPaginate(itemCount: 10, pageSize: 30)

    #expect(requested == 2, "20 items is still short of 30, 30 is not")
    #expect(await query.paginationState().itemCount == 30)
  }

  @Test("auto-pagination does nothing when the list already satisfies the threshold")
  func noOpWhenSatisfied() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeEndlessFeed(store: store, key: key, itemsPerPage: 10)

    _ = try await query.loadFirstPage()
    let requested = await query.autoPaginate(itemCount: 10, pageSize: 10)

    #expect(requested == 0)
    #expect(await query.paginationState().pageCount == 1)
  }

  @Test("auto-pagination stops at the end of a finite list without erroring")
  func stopsAtEndOfList() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = InfiniteQuery<Int>(store: store, key: key, identity: { String($0) }, page: { cursor in
      switch cursor {
      case nil: return QueryPage(items: [0, 1], cursor: "c1", requestCursor: nil)
      case "c1": return QueryPage(items: [2, 3], cursor: nil, requestCursor: "c1")
      default: return QueryPage(items: [], cursor: nil, requestCursor: cursor)
      }
    })

    _ = try await query.loadFirstPage()
    let requested = await query.autoPaginate(itemCount: 2, pageSize: 100)

    #expect(requested == 1, "the second page exhausted the list")
    #expect(await query.paginationState().hasNextPage == false)
    #expect(await query.items() == [0, 1, 2, 3])
  }

  @Test("auto-pagination refuses to reissue a cursor that already produced a page")
  func stopsOnRepeatedCursor() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    // A server that keeps returning the same cursor is the exact loop the RN
    // hook's `repeatedCursor` guard exists to break.
    let query = InfiniteQuery<Int>(store: store, key: key, identity: { String($0) }, page: { cursor in
      QueryPage(items: [0], cursor: "looping", requestCursor: cursor)
    })

    _ = try await query.loadFirstPage()
    let requested = await query.autoPaginate(itemCount: 1, pageSize: 100)

    #expect(requested == 2, "the repeat is detected once a second identical cursor lands")
    #expect(await query.paginationState().pageCount == 3, "the walk stops well short of the cap")
    #expect(requested < 5, "without the guard this would run to MAX_ATTEMPTS")
  }

  @Test("auto-pagination does nothing for a key that is not an infinite query")
  func noOpForSingleShotKey() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = QueryKey(TestRoot.profile, FeedArgs(limit: 30))
    await store.setQueryData(ProfilePayload(did: "did:plc:alice", displayName: "Alice"), for: key)

    let requested = await store.autoPaginate(key, itemCount: 0, pageSize: 100)

    #expect(requested == 0)
  }

  @Test("startAutoPagination runs the walk in the background")
  func backgroundVariation() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeEndlessFeed(store: store, key: key, itemsPerPage: 1)
    _ = try await query.loadFirstPage()

    let task = await store.startAutoPagination(key, itemCount: 1, pageSize: 100, maxAttempts: 3)
    await task.value

    #expect(await query.paginationState().pageCount == 4, "one initial page plus three")
  }

  @Test("a bounded attempt count of zero is a no-op")
  func zeroAttempts() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeEndlessFeed(store: store, key: key, itemsPerPage: 1)
    _ = try await query.loadFirstPage()

    let requested = await query.autoPaginate(itemCount: 0, pageSize: 100, maxAttempts: 0)

    #expect(requested == 0)
    #expect(await query.paginationState().pageCount == 1)
  }

  @Test("a failing page request ends the walk without throwing")
  func failingPageEndsWalk() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<InfiniteQueryData<Int>>([
      .value(InfiniteQueryData(pages: [QueryPage(items: [0], cursor: "c1", requestCursor: nil)])),
      .failure(TestError("offline")),
    ])
    let query = InfiniteQuery<Int>(store: store, key: key, identity: { String($0) }, fetchPage: { request in
      try await fetcher.call(request)
    })

    _ = try await query.loadFirstPage()
    let requested = await query.autoPaginate(itemCount: 1, pageSize: 100)

    #expect(requested == 0, "a failed request stops the walk rather than spinning")
    let entry = await store.entry(key, as: InfiniteQueryData<Int>.self)
    #expect(entry.status == .error)
    #expect(entry.data?.items == [0], "the page already fetched survives")
  }

  @Test("each auto-paginated page still de-duplicates against earlier pages")
  func dedupeStillApplies() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    // Every page repeats the previous page's last item.
    let query = InfiniteQuery<Int>(store: store, key: key, identity: { String($0) }, page: { cursor in
      let index = cursor.flatMap(Int.init) ?? 0
      return QueryPage(items: [index, index + 1], cursor: String(index + 1), requestCursor: cursor)
    })

    _ = try await query.loadFirstPage()
    _ = await query.autoPaginate(itemCount: 2, pageSize: 6)

    #expect(await query.items() == [0, 1, 2, 3, 4, 5], "overlapping items collapse")
  }
}
