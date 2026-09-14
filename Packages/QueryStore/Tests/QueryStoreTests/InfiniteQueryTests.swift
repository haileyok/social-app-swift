import Foundation
import Testing

@testable import QueryStore

/// Covers infinite queries: the ordered page list plus cursor, `loadMore`
/// appending pages, the dedupe-on-merge hook, and the flattened items accessor.
/// The RN shape being matched is `useInfiniteQuery` with
/// `getNextPageParam: lastPage => lastPage.cursor` (see
/// `src/state/queries/feed.ts`).
@Suite("Infinite queries")
struct InfiniteQueryTests {
  /// A feed that serves a scripted list of pages, keyed by request cursor.
  private func makeFeedQuery(
    store: QueryStore,
    key: QueryKey,
    pages: [[String]],
    cursors: [String?]
  ) -> InfiniteQuery<String> {
    InfiniteQuery<String>(store: store, key: key, identity: { $0 }, page: { cursor in
      // `cursors[n]` is the cursor that *requests* page `n`; page `n` reports
      // `cursors[n + 1]` as its next cursor, and `nil` once the list ends.
      let index = cursors.firstIndex { $0 == cursor } ?? 0
      guard index < pages.count else { return QueryPage(items: [], cursor: nil) }
      let next = index + 1 < cursors.count ? cursors[index + 1] : nil
      return QueryPage(items: pages[index], cursor: next, requestCursor: cursor)
    })
  }

  @Test("loadFirstPage stores the first page and its cursor")
  func loadFirstPage() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeFeedQuery(store: store, key: key, pages: [["a", "b"], ["c"]], cursors: [nil, "c1"])

    let data = try await query.loadFirstPage()

    #expect(data.items == ["a", "b"])
    #expect(data.nextCursor == "c1")
    #expect(data.hasNextPage)

    let state = await query.paginationState()
    #expect(state.pageCount == 1)
    #expect(state.itemCount == 2)
    #expect(state.nextCursor == "c1")
  }

  @Test("loadMore appends the next page and keeps order")
  func loadMoreAppendsInOrder() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeFeedQuery(
      store: store, key: key, pages: [["a", "b"], ["c", "d"], ["e"]], cursors: [nil, "c1", "c2"])

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()

    #expect(await query.items() == ["a", "b", "c", "d"], "pages concatenate in request order")
    let state = await query.paginationState()
    #expect(state.pageCount == 2)
    #expect(state.nextCursor == "c2")
  }

  @Test("loadMore at the end of the list returns the current items without throwing")
  func loadMoreOnExhaustedList() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeFeedQuery(store: store, key: key, pages: [["a"]], cursors: [nil])

    _ = try await query.loadFirstPage()
    let exhausted = try await query.loadMore()

    #expect(exhausted.items == ["a"])
    #expect(await query.hasNextPage() == false)
    #expect(await query.paginationState().pageCount == 1, "no page is appended past the end")
  }

  @Test("loadMore requests the cursor the last page reported")
  func loadMoreUsesReportedCursor() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<InfiniteQueryData<String>>([
      .value(InfiniteQueryData(pages: [QueryPage(items: ["a"], cursor: "cursor-1")])),
      .value(InfiniteQueryData(pages: [QueryPage(items: ["b"], cursor: nil)])),
    ])
    let query = InfiniteQuery<String>(store: store, key: key, identity: { $0 }, fetchPage: { request in
      try await fetcher.call(request)
    })

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()

    #expect(fetcher.cursors.count == 2)
    #expect(fetcher.cursors[0] == nil)
    #expect(fetcher.cursors[1] == "cursor-1", "the second request walks the reported cursor")
  }

  @Test("duplicate items across pages collapse to one on merge")
  func dedupeOnMerge() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    // The second page repeats "b" and "c", which is what a feed does when posts
    // move between requests.
    let query = makeFeedQuery(
      store: store, key: key, pages: [["a", "b"], ["b", "c", "d"]], cursors: [nil, "c1"])

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()

    #expect(await query.items() == ["a", "b", "c", "d"], "the earlier copy of a duplicate wins")
    #expect(await query.paginationState().itemCount == 4)
  }

  @Test("a page whose items are all duplicates still advances the cursor")
  func fullyDuplicatePageAdvancesCursor() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeFeedQuery(
      store: store, key: key, pages: [["a", "b"], ["a", "b"], ["c"]], cursors: [nil, "c1", "c2"])

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()

    #expect(await query.items() == ["a", "b"])
    #expect(await query.paginationState().nextCursor == "c2", "the walk must not stall on overlap")
  }

  @Test("a page merge can be refused by the reducer")
  func refusedPageDoesNotCorruptPagination() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    // The reducer refuses any page whose cursor chain runs backwards.
    let query = InfiniteQuery<String>(
      store: store,
      key: key,
      identity: { $0 },
      fetchPage: { request in
        if request.cursor == "stale-cursor" {
          return InfiniteQueryData(pages: [QueryPage(items: ["x"], cursor: "old", requestCursor: request.cursor)])
        }
        return InfiniteQueryData(pages: [QueryPage(items: ["a"], cursor: "stale-cursor", requestCursor: request.cursor)])
      }
    )

    _ = try await query.loadFirstPage()
    #expect(await query.paginationState().nextCursor == "stale-cursor")

    // A merge policy that always refuses, to prove the descriptor is dropped too.
    let refusing = InfiniteQuery<String>(
      store: store,
      key: key,
      identity: { _ in "always-refuse" }, fetchPage: { request in
      InfiniteQueryData(pages: [QueryPage(items: [], cursor: "never", requestCursor: request.cursor)])
    })
    _ = try? await refusing.fetchPage(at: "stale-cursor")
    #expect(await query.items() == ["a"])
  }

  @Test("refresh truncates to one page and reloads the head")
  func refreshTruncatesAndReloads() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let pages = [["a", "b"], ["c", "d"]]
    let cursors: [String?] = [nil, "c1"]
    let query = InfiniteQuery<String>(store: store, key: key, identity: { $0 }, page: { cursor in
      let index = cursors.firstIndex { $0 == cursor } ?? 0
      guard index < pages.count else { return QueryPage(items: [], cursor: nil) }
      let next = index + 1 < cursors.count ? cursors[index + 1] : nil
      return QueryPage(items: pages[index], cursor: next, requestCursor: cursor)
    })

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    #expect(await query.paginationState().pageCount == 2)

    _ = try await query.refresh()

    #expect(await query.items() == ["a", "b"], "a refresh restarts from a single fresh head")
    #expect(await query.paginationState().pageCount == 1)
  }

  @Test("items are readable through the flattened accessor after a restore-shaped write")
  func flattenedItemsAccessor() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = InfiniteQuery<String>(store: store, key: key, identity: { $0 }, page: { _ in
      QueryPage(items: [], cursor: nil)
    })

    await query.setData(
      InfiniteQueryData(pages: [
        QueryPage(items: ["a", "b"], cursor: "c1", requestCursor: nil),
        QueryPage(items: ["c"], cursor: nil, requestCursor: "c1"),
      ]))

    #expect(await query.items() == ["a", "b", "c"])
    #expect(await query.paginationState().pageCount == 2)
    #expect(await query.hasNextPage() == false)
  }

  @Test("updateItems rewrites the flattened list optimistically")
  func updateItems() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeFeedQuery(store: store, key: key, pages: [["a", "b"]], cursors: [nil])

    _ = try await query.loadFirstPage()
    await query.updateItems { items in items.map { $0 + "!" } }

    #expect(await query.items() == ["a!", "b!"])
  }

  @Test("subscribers receive flattened items and each appended page")
  func subscribeItems() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeFeedQuery(store: store, key: key, pages: [["a", "b"], ["c"]], cursors: [nil, "c1"])

    _ = try await query.loadFirstPage()
    let seen = Recorder<[String]>()
    let subscription = await query.subscribeItems { seen.record($0) }
    #expect(seen.values == [["a", "b"]])

    _ = try await query.loadMore()
    #expect(seen.values.last == ["a", "b", "c"])

    await subscription.cancel()
  }

  @Test("an infinite query key is distinct from a single-shot key with the same root")
  func infiniteAndSingleShotKeysAreSeparate() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    let key = feedKey(limit: 30)
    let query = makeFeedQuery(store: store, key: key, pages: [["a"]], cursors: [nil])

    _ = try await query.loadFirstPage()
    let entry = await store.snapshot(for: key)

    #expect(entry?.isInfinite == true)
    #expect(await store.paginationState(for: QueryKey(TestRoot.profile, FeedArgs(limit: 30))) == .none)
  }

  @Test("InfiniteQueryData computes cursor bookkeeping")
  func infiniteDataHelpers() {
    let data = InfiniteQueryData(pages: [
      QueryPage(items: ["a"], cursor: "c1", requestCursor: nil),
      QueryPage(items: ["b", "c"], cursor: "c2", requestCursor: "c1"),
    ])

    #expect(data.items == ["a", "b", "c"])
    #expect(data.itemCount == 3)
    #expect(data.nextCursor == "c2")
    #expect(data.hasNextPage)
    #expect(data.lastRequestCursor == "c1")
    #expect(data.repeatsCursor("c2") == false)
    #expect(data.repeatsCursor(nil) == false)
    // A cursor that requested a page other than the last one has already been
    // walked, which is the loop the RN hook guards against.
    let looping: InfiniteQueryData<String> = InfiniteQueryData(pages: [
      QueryPage(items: [String](), cursor: "c1", requestCursor: nil),
      QueryPage(items: [String](), cursor: "c2", requestCursor: "c1"),
      QueryPage(items: [String](), cursor: "c3", requestCursor: "c1"),
    ])
    #expect(looping.repeatsCursor("c1"))

    var truncated = data
    truncated.truncate(to: 1)
    #expect(truncated.pages.count == 1)
    #expect(truncated.nextCursor == "c1")
  }
}
