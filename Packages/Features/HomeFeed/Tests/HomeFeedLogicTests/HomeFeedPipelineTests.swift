import Domain
import Foundation
import Lexicons
import QueryStore
import Testing

@testable import HomeFeedLogic

/// A helper to build a feed query over a recording client.
func makeFollowingQuery(
  store: QueryStore,
  xrpc: RecordingFeedXrpc,
  options: FeedTunerOptions = FeedTunerOptions(),
  scope: String? = nil
) -> HomeFeedQuery {
  HomeFeedQuery(
    store: store,
    descriptor: .following,
    fetcher: FollowingFeedFetcher(xrpc: xrpc),
    tunerOptions: options,
    scope: scope)
}

/// The fetch → tune → slice pipeline, asserted against realistic pages.
@Suite("Home feed pipeline")
struct HomeFeedPipelineTests {
  @Test("a page of plain posts becomes one slice per post")
  func plainPageSlices() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(feed: [
      Fixtures.item("a"), Fixtures.item("b"), Fixtures.item("c"),
    ])])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    let data = try await query.loadFirstPage()
    #expect(data.slices.count == 3)
    #expect(data.slices.map(\.reactKey).count == 3)
    #expect(data.slices[0].items.count == 1)
  }

  @Test("a drill-in reply slice carries root, parent and the selected post")
  func replyChainOrdering() async throws {
    let root = Fixtures.post("root")
    let parent = Fixtures.reply("parent", parent: root)
    let selected = Fixtures.reply("selected", parent: parent, root: root)
    let item = Fixtures.feedViewPost(
      selected, reply: Fixtures.replyRef(parent: parent, root: root))

    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(feed: [item])])
    let store = QueryStore()
    // The replies are authored by "alice", so alice is the signed-in reader:
    // `followedRepliesOnly` admits replies from self and followed accounts only.
    let query = makeFollowingQuery(
      store: store, xrpc: xrpc, options: FeedTunerOptions(userDid: "did:plc:alice"))

    let data = try await query.loadFirstPage()
    let slice = try #require(data.slices.first)
    // Domain's slice puts the root first, then the parent, then the post itself.
    #expect(slice.items.count == 3)
    #expect(slice.items[0].uri == Fixtures.uri("root"))
    #expect(slice.items[1].uri == Fixtures.uri("parent"))
    #expect(slice.items[2].uri == Fixtures.uri("selected"))
  }

  @Test("feedContext and reqId survive tuning onto the slice")
  func feedContextPreserved() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(feed: [
      Fixtures.item("a", feedContext: "ctx-1", reqId: "req-1"),
    ])])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    let data = try await query.loadFirstPage()
    let slice = try #require(data.slices.first)
    #expect(slice.feedContext == "ctx-1")
    #expect(slice.reqId == "req-1")
  }

  @Test("a repost reason is preserved on the slice")
  func reasonPreserved() async throws {
    let item = Fixtures.feedViewPost(
      Fixtures.post("reposted"), reason: Fixtures.repostReason())
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(feed: [item])])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    let data = try await query.loadFirstPage()
    let slice = try #require(data.slices.first)
    guard case .feedDefsReasonRepost = slice.reason else {
      Issue.record("expected a repost reason, got \(String(describing: slice.reason))")
      return
    }
  }

  @Test("the timeline tuner stack is removeOrphans then followedRepliesOnly then dedupThreads then removeMutedThreads")
  func followingTunerStack() {
    let tuners = FeedTunerFactory.tuners(for: .following, options: FeedTunerOptions())
    // removeOrphans, followedRepliesOnly, dedupThreads, removeMutedThreads.
    #expect(tuners.count == 4)
  }

  @Test("hideReposts and hideQuotePosts add their filters to the following stack")
  func followingPreferenceFilters() {
    let base = FeedTunerFactory.tuners(for: .following, options: FeedTunerOptions()).count
    let withReposts = FeedTunerFactory.tuners(
      for: .following, options: FeedTunerOptions(hideReposts: true)).count
    let withQuotes = FeedTunerFactory.tuners(
      for: .following, options: FeedTunerOptions(hideQuotePosts: true)).count
    #expect(withReposts == base + 1)
    #expect(withQuotes == base + 1)
  }

  @Test("hideReplies replaces followedRepliesOnly rather than stacking with it")
  func hideRepliesReplacesFollowedReplies() {
    // Both branches contribute exactly one reply filter, so the count is stable.
    let hiding = FeedTunerFactory.tuners(
      for: .following, options: FeedTunerOptions(hideReplies: true)).count
    let filtering = FeedTunerFactory.tuners(
      for: .following, options: FeedTunerOptions(hideReplies: false)).count
    #expect(hiding == filtering)
  }

  @Test("a feedgen uses the language filter then removeMutedThreads only")
  func feedgenTunerStack() {
    let tuners = FeedTunerFactory.tuners(
      for: .feedgen(uri: "at://f"),
      options: FeedTunerOptions(contentLanguages: ["en"]))
    #expect(tuners.count == 2)
  }

  @Test("the language filter drops a slice whose only post is in another language")
  func languageFilterDrops() async throws {
    let english = Fixtures.item("en")
    let german = Fixtures.feedViewPost(
      Fixtures.post("de", record: Fixtures.feedPostRecord(text: "de", langs: ["de"])))

    let xrpc = RecordingFeedXrpc()
    xrpc.setFeedPages([FeedPageOutput(feed: [english, german])])
    let store = QueryStore()
    let query = HomeFeedQuery(
      store: store,
      descriptor: .feedgen(uri: "at://did:plc:f/app.bsky.feed.generator/cool"),
      fetcher: CustomFeedFetcher(
        xrpc: xrpc, feedURI: "at://did:plc:f/app.bsky.feed.generator/cool"),
      tunerOptions: FeedTunerOptions(contentLanguages: ["en"]))

    let data = try await query.loadFirstPage()
    let uris = data.slices.flatMap { $0.items.map(\.uri) }
    #expect(uris.contains(Fixtures.uri("en")))
    #expect(!uris.contains(Fixtures.uri("de")))
  }

  @Test("the language filter never empties a page completely")
  func languageFilterKeepsSomething() async throws {
    let german = Fixtures.feedViewPost(
      Fixtures.post("de", record: Fixtures.feedPostRecord(text: "de", langs: ["de"])))
    let xrpc = RecordingFeedXrpc()
    xrpc.setFeedPages([FeedPageOutput(feed: [german])])
    let store = QueryStore()
    let query = HomeFeedQuery(
      store: store,
      descriptor: .feedgen(uri: "at://did:plc:f/app.bsky.feed.generator/cool"),
      fetcher: CustomFeedFetcher(
        xrpc: xrpc, feedURI: "at://did:plc:f/app.bsky.feed.generator/cool"),
      tunerOptions: FeedTunerOptions(contentLanguages: ["en"]))

    let data = try await query.loadFirstPage()
    #expect(!data.slices.isEmpty)
  }

  @Test("the tuner dedupes a post already seen in an earlier page")
  func crossPageDeduplication() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([
      FeedTimelinePage(cursor: "c1", feed: [Fixtures.item("a"), Fixtures.item("b")]),
      // The second page repeats "b" and adds "c".
      FeedTimelinePage(cursor: nil, feed: [Fixtures.item("b"), Fixtures.item("c")]),
    ])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    // The tuner's `seenUris` state is cross-page, so the repeated "b" is dropped
    // while the new "c" is admitted.
    let data = try await query.loadMore()
    let uris = data.slices.flatMap { $0.items.map(\.uri) }
    #expect(uris.contains(Fixtures.uri("a")))
    #expect(uris.contains(Fixtures.uri("b")))
    #expect(uris.contains(Fixtures.uri("c")))
    // "b" appears exactly once across the accumulated pages.
    #expect(uris.filter { $0 == Fixtures.uri("b") }.count == 1)
  }

  @Test("a feedgen is allowed to repeat a thread root across pages, following is not")
  func dedupThreadsPerDescriptor() async throws {
    // Two replies to the same root: following dedupes the second away.
    let root = Fixtures.post("root")
    let parent = Fixtures.reply("parent", parent: root)
    let first = Fixtures.feedViewPost(
      Fixtures.reply("reply1", parent: parent, root: root),
      reply: Fixtures.replyRef(parent: parent, root: root))
    let second = Fixtures.feedViewPost(
      Fixtures.reply("reply2", parent: parent, root: root),
      reply: Fixtures.replyRef(parent: parent, root: root))

    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(feed: [first, second])])
    let store = QueryStore()
    let query = makeFollowingQuery(
      store: store, xrpc: xrpc, options: FeedTunerOptions(userDid: "did:plc:alice"))

    let data = try await query.loadFirstPage()
    let selected = data.slices.compactMap { $0.items.last?.uri }
    #expect(selected.contains(Fixtures.uri("reply1")))
    #expect(!selected.contains(Fixtures.uri("reply2")))
  }

  @Test("a reply from an account the reader neither follows nor authors is dropped")
  func followedRepliesOnlyDrops() async throws {
    let root = Fixtures.post("root")
    let parent = Fixtures.reply("parent", parent: root)
    let stranger = Fixtures.feedViewPost(
      Fixtures.reply(
        "stranger-reply", parent: parent, root: root,
        author: Fixtures.profile(did: "did:plc:stranger", handle: "stranger.test")),
      reply: Fixtures.replyRef(parent: parent, root: root))

    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(feed: [stranger])])
    let store = QueryStore()
    let query = makeFollowingQuery(
      store: store, xrpc: xrpc, options: FeedTunerOptions(userDid: "did:plc:alice"))

    let data = try await query.loadFirstPage()
    #expect(data.slices.isEmpty)
  }

  @Test("a reply from a followed account is kept")
  func followedRepliesKept() async throws {
    let root = Fixtures.post("root")
    let parent = Fixtures.reply("parent", parent: root)
    let friend = Fixtures.feedViewPost(
      Fixtures.reply(
        "friend-reply", parent: parent, root: root,
        author: Fixtures.followedProfile(handle: "friend")),
      reply: Fixtures.replyRef(parent: parent, root: root))

    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(feed: [friend])])
    let store = QueryStore()
    let query = makeFollowingQuery(
      store: store, xrpc: xrpc, options: FeedTunerOptions(userDid: "did:plc:alice"))

    let data = try await query.loadFirstPage()
    #expect(!data.slices.isEmpty)
  }
}

/// Cursor pagination and de-duplication through the store's infinite query.
@Suite("Home feed pagination")
struct HomeFeedPaginationTests {
  @Test("the first page requests no cursor and the configured limit")
  func firstPageRequest() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: "next", feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    #expect(xrpc.calls == [.timeline(cursor: nil, limit: 30)])
  }

  @Test("loadMore requests the cursor the previous page returned")
  func cursorWalk() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([
      FeedTimelinePage(cursor: "c1", feed: [Fixtures.item("a")]),
      FeedTimelinePage(cursor: "c2", feed: [Fixtures.item("b")]),
    ])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    #expect(
      xrpc.calls == [
        .timeline(cursor: nil, limit: 30),
        .timeline(cursor: "c1", limit: 30),
      ])
  }

  @Test("a terminal page ends the walk and loadMore makes no request")
  func terminalPageStops() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    #expect(xrpc.calls.count == 1)
  }

  @Test("pages accumulate in order")
  func pagesAccumulate() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([
      FeedTimelinePage(cursor: "c1", feed: [Fixtures.item("a")]),
      FeedTimelinePage(cursor: nil, feed: [Fixtures.item("b")]),
    ])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    let data = try await query.loadMore()
    #expect(data.pages.count == 2)
    #expect(data.slices.map { $0.items[0].uri } == [Fixtures.uri("a"), Fixtures.uri("b")])
  }

  @Test("a repeated cursor is refused rather than looping")
  func repeatedCursorRefused() async throws {
    let xrpc = RecordingFeedXrpc()
    // Both pages report the same next cursor, so a second request would loop.
    xrpc.setTimelinePages([
      FeedTimelinePage(cursor: "same", feed: [Fixtures.item("a")]),
      FeedTimelinePage(cursor: "same", feed: [Fixtures.item("b")]),
    ])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    _ = try await query.loadMore()
    #expect(xrpc.calls.count == 2)
  }

  @Test("refresh truncates to one page and refetches with no cursor")
  func refreshTruncates() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([
      FeedTimelinePage(cursor: "c1", feed: [Fixtures.item("a")]),
      FeedTimelinePage(cursor: "c2", feed: [Fixtures.item("b")]),
      FeedTimelinePage(cursor: "c3", feed: [Fixtures.item("fresh")]),
    ])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    let refreshed = try await query.refresh()

    #expect(refreshed.pages.count == 1)
    #expect(refreshed.slices.first?.items.first?.uri == Fixtures.uri("fresh"))
    #expect(
      xrpc.calls == [
        .timeline(cursor: nil, limit: 30),
        .timeline(cursor: "c1", limit: 30),
        .timeline(cursor: nil, limit: 30),
      ])
  }

  @Test("the tuned item count drives auto-pagination, capped at five extra pages")
  func autoPagination() async throws {
    let xrpc = RecordingFeedXrpc()
    // Every page has two items, so a threshold of 30 cannot be met; the walk
    // must stop at the attempt cap rather than requesting forever.
    xrpc.setTimelinePages((0..<20).map { index in
      FeedTimelinePage(cursor: "c\(index)", feed: [Fixtures.item("a\(index)"), Fixtures.item("b\(index)")])
    })
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    _ = try await query.loadFirstPage()
    let attempts = await query.autoPaginate()
    #expect(attempts <= HomeFeedConstants.autoPaginationMaxAttempts)
    #expect(xrpc.calls.count <= HomeFeedConstants.autoPaginationMaxAttempts + 1)
  }

  @Test("auto-pagination stops early once the threshold is met")
  func autoPaginationStopsWhenFull() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([
      FeedTimelinePage(cursor: "c1", feed: (0..<30).map { Fixtures.item("p\($0)") }),
      FeedTimelinePage(cursor: "c2", feed: [Fixtures.item("extra")]),
    ])
    let store = QueryStore()
    let query = makeFollowingQuery(store: store, xrpc: xrpc)

    let data = try await query.loadFirstPage()
    #expect(data.itemCount == 30)
    let attempts = await query.autoPaginate()
    #expect(attempts == 0)
    #expect(xrpc.calls.count == 1)
  }
}

/// The custom-feed fetch paths: appview hydration and skeleton hydration.
@Suite("Custom feed fetchers")
struct CustomFeedFetcherTests {
  let feedURI = "at://did:plc:someone/app.bsky.feed.generator/cool"

  @Test("the getFeed path requests the feed with the language header")
  func getFeedPath() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setFeedPages([FeedPageOutput(cursor: "c", feed: [Fixtures.item("a")])])
    let fetcher = CustomFeedFetcher(
      xrpc: xrpc, feedURI: feedURI, contentLanguages: ["en", "de"], userInterests: "tech")

    let page = try await fetcher.fetch(cursor: nil, limit: 30)
    #expect(page.cursor == "c")
    #expect(
      xrpc.calls == [
        .feed(
          feed: feedURI, cursor: nil, limit: 30,
          headers: FeedRequestHeaders(acceptLanguage: "en,de", bskyTopics: nil))
      ])
  }

  @Test("a page longer than the limit is truncated, as custom.ts does")
  func truncatesOverlongPage() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setFeedPages([FeedPageOutput(feed: (0..<40).map { Fixtures.item("p\($0)") })])
    let fetcher = CustomFeedFetcher(xrpc: xrpc, feedURI: feedURI)

    let page = try await fetcher.fetch(cursor: nil, limit: 30)
    #expect(page.feed.count == 30)
  }

  @Test("peekLatest requests a single item with no cursor")
  func peekLatestSingle() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setFeedPages([FeedPageOutput(feed: [Fixtures.item("newest")])])
    let fetcher = CustomFeedFetcher(xrpc: xrpc, feedURI: feedURI)

    let post = try await fetcher.peekLatest()
    #expect(post?.post.uri.rawValue == Fixtures.uri("newest"))
    guard case .feed(let feed, let cursor, let limit, _) = xrpc.calls.first else {
      Issue.record("expected a getFeed call")
      return
    }
    #expect(feed == feedURI)
    #expect(cursor == nil)
    #expect(limit == 1)
  }

  @Test("the skeleton path issues getFeedSkeleton then getPosts, in that order")
  func skeletonThenHydrate() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setSkeletonPages([
      FeedSkeletonOutput(
        cursor: "sk-next",
        feed: [
          Fixtures.skeletonItem(Fixtures.uri("a"), feedContext: "ctx-a"),
          Fixtures.skeletonItem(Fixtures.uri("b")),
        ],
        reqId: "req-1")
    ])
    xrpc.setPosts([Fixtures.post("a"), Fixtures.post("b")])
    let fetcher = SkeletonHydratingFetcher(xrpc: xrpc, feedURI: feedURI)

    let page = try await fetcher.fetch(cursor: nil, limit: 30)
    #expect(
      xrpc.calls == [
        .feedSkeleton(feed: feedURI, cursor: nil, limit: 30),
        .posts(uris: [Fixtures.uri("a"), Fixtures.uri("b")]),
      ])
    #expect(page.cursor == "sk-next")
    #expect(page.feed.count == 2)
  }

  @Test("skeleton feedContext and reqId are carried onto the hydrated items")
  func skeletonContextCarried() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setSkeletonPages([
      FeedSkeletonOutput(
        feed: [Fixtures.skeletonItem(Fixtures.uri("a"), feedContext: "ctx-a")],
        reqId: "req-1")
    ])
    xrpc.setPosts([Fixtures.post("a")])
    let fetcher = SkeletonHydratingFetcher(xrpc: xrpc, feedURI: feedURI)

    let page = try await fetcher.fetch(cursor: nil, limit: 30)
    let item = try #require(page.feed.first)
    #expect(item.feedContext == "ctx-a")
    #expect(item.reqId == "req-1")
  }

  @Test("skeleton order is preserved and unresolvable posts are dropped")
  func skeletonOrderAndDrops() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setSkeletonPages([
      FeedSkeletonOutput(feed: [
        Fixtures.skeletonItem(Fixtures.uri("a")),
        Fixtures.skeletonItem(Fixtures.uri("missing")),
        Fixtures.skeletonItem(Fixtures.uri("c")),
      ])
    ])
    // Only a and c exist in the appview's answer.
    xrpc.setPosts([Fixtures.post("a"), Fixtures.post("c")])
    let fetcher = SkeletonHydratingFetcher(xrpc: xrpc, feedURI: feedURI)

    let page = try await fetcher.fetch(cursor: nil, limit: 30)
    #expect(page.feed.map(\.post.uri.rawValue) == [Fixtures.uri("a"), Fixtures.uri("c")])
  }
  @Test("hydration batches getPosts rather than sending one huge request")
  func hydrationBatching() async throws {
    let uris = (0..<60).map { Fixtures.uri("p\($0)") }
    let xrpc = RecordingFeedXrpc()
    xrpc.setSkeletonPages([
      FeedSkeletonOutput(feed: uris.map { Fixtures.skeletonItem($0) })
    ])
    xrpc.setPosts((0..<60).map { Fixtures.post("p\($0)") })
    let fetcher = SkeletonHydratingFetcher(xrpc: xrpc, feedURI: feedURI, hydrationBatchSize: 25)

    _ = try await fetcher.fetch(cursor: nil, limit: 60)
    let batches = xrpc.calls.compactMap { call -> [String]? in
      if case .posts(let uris) = call { return uris }
      return nil
    }
    #expect(batches.map(\.count) == [25, 25, 10])
  }

  @Test("the batch splitter handles empty and exact-multiple inputs")
  func batchSplitting() {
    #expect(SkeletonHydratingFetcher.batches(of: [], size: 25).isEmpty)
    #expect(SkeletonHydratingFetcher.batches(of: ["a", "b"], size: 2) == [["a", "b"]])
    #expect(SkeletonHydratingFetcher.batches(of: ["a", "b", "c"], size: 2) == [["a", "b"], ["c"]])
  }
}

/// The list feed path.
@Suite("List feed fetcher")
struct ListFeedFetcherTests {
  @Test("a list feed reads app.bsky.feed.getListFeed with the list URI")
  func listFeedParams() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setFeedPages([FeedPageOutput(cursor: "c", feed: [Fixtures.item("a")])])
    let fetcher = ListFeedFetcher(
      xrpc: xrpc, listURI: "at://did:plc:a/app.bsky.graph.list/friends")

    _ = try await fetcher.fetch(cursor: nil, limit: 30)
    #expect(
      xrpc.calls == [
        .listFeed(list: "at://did:plc:a/app.bsky.graph.list/friends", cursor: nil, limit: 30)
      ])
  }
}
