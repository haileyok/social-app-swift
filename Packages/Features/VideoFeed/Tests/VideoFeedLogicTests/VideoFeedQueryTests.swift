import Foundation
import Lexicons
import QueryStore
import SwiftAtproto
import Testing

@testable import VideoFeedLogic

/// Query keys, sources, fetchers and the query pipeline.
///
/// Ports `RQKEY(feedDesc, params)` and the two `FeedAPI` implementations the
/// immersive screen uses (`src/lib/api/feed/custom.ts`, `author.ts`), plus the
/// `usePostFeedQuery` wiring in `src/screens/VideoFeed/index.tsx`.
@Suite("Video feed keys, sources and queries")
struct VideoFeedQueryTests {
  // MARK: - Sources

  @Test("the video source is the thevids generator")
  func videoSource() {
    #expect(VideoFeedSource.video.descriptorString == "feedgen|\(VideoFeedConstants.videoFeedURI)")
    #expect(VideoFeedConstants.videoFeedURI.hasSuffix("/thevids"))
    #expect(VideoFeedSource.video.isVideoFeedGenerator)
  }

  @Test("both the production and staging video feeds count as video feeds")
  func videoFeedURIs() {
    #expect(VideoFeedConstants.videoFeedURIs.count == 2)
    #expect(
      VideoFeedSource.feedgen(uri: VideoFeedConstants.stagingVideoFeedURI)
        .isVideoFeedGenerator)
    #expect(
      !VideoFeedSource.feedgen(uri: "at://did:plc:someone/app.bsky.feed.generator/cats")
        .isVideoFeedGenerator)
    #expect(!VideoFeedSource.author(did: "did:plc:a", filter: .postsWithVideo).isVideoFeedGenerator)
  }

  @Test("an author source is the did plus the filter")
  func authorSource() {
    let source = VideoFeedSource.author(did: "did:plc:alice", filter: .postsWithVideo)
    #expect(source.descriptorString == "author|did:plc:alice|posts_with_video")
    #expect(source.feedgenURI == nil)
    #expect(VideoFeedSource.video.feedgenURI == VideoFeedConstants.videoFeedURI)
  }

  @Test("descriptors round-trip through the parser")
  func descriptorRoundTrip() throws {
    let feedgen = VideoFeedSource.video
    #expect(VideoFeedSource(descriptor: feedgen.descriptorString) == feedgen)

    let author = VideoFeedSource.author(did: "did:plc:alice", filter: .postsWithMedia)
    #expect(VideoFeedSource(descriptor: author.descriptorString) == author)
    #expect(VideoFeedSource(descriptor: author.descriptor) == author)
  }

  @Test("an unrecognised descriptor does not parse")
  func unknownDescriptor() {
    #expect(VideoFeedSource(descriptor: "following") == nil)
    #expect(VideoFeedSource(descriptor: "list|at://x") == nil)
    #expect(VideoFeedSource(descriptor: "feedgen") == nil)
    #expect(VideoFeedSource(descriptor: "author|did:plc:a") == nil)
    #expect(VideoFeedSource(descriptor: "") == nil)
  }

  @Test("every author filter round-trips")
  func allAuthorFilters() {
    for filter in VideoAuthorFilter.allCases {
      let source = VideoFeedSource.author(did: "did:plc:a", filter: filter)
      #expect(VideoFeedSource(descriptor: source.descriptorString) == source)
    }
    #expect(VideoAuthorFilter.video == .postsWithVideo)
  }

  // MARK: - Keys

  @Test("the feed key reuses the RN post-feed root and carries the descriptor")
  func feedKeyShape() {
    let key = VideoFeedKeys.feed(.video)
    #expect(key.root == "post-feed")
    #expect(key.argsText.contains(VideoFeedConstants.videoFeedURI))
    #expect(VideoFeedKeys.feedRoot == "post-feed")
  }

  @Test("two feeds never share a key")
  func distinctFeedKeys() {
    let video = VideoFeedKeys.feed(.video)
    let author = VideoFeedKeys.feed(
      .author(did: "did:plc:a", filter: .postsWithVideo))
    #expect(video != author)
  }

  @Test("the interstitial is part of the key, matching feedCacheKey")
  func interstitialInKey() {
    let direct = VideoFeedKeys.feed(.video)
    let fromDiscover = VideoFeedKeys.feed(.video, feedCacheKey: .discover)
    let fromExplore = VideoFeedKeys.feed(.video, feedCacheKey: .explore)
    #expect(direct != fromDiscover)
    #expect(fromDiscover != fromExplore)
    // An explicit `none` is the same as the default.
    #expect(VideoFeedKeys.feed(.video, feedCacheKey: .none) == direct)
    #expect(VideoFeedInterstitial.direct == .none)
  }

  @Test("account scope separates two accounts")
  func scopeSeparatesAccounts() {
    let one = VideoFeedKeys.feed(.video, scope: "did:plc:one")
    let two = VideoFeedKeys.feed(.video, scope: "did:plc:two")
    #expect(one != two)
    #expect(one.scope == "did:plc:one")
    #expect(two.scope == "did:plc:two")
  }

  @Test("the feed-info key uses the RN feedInfo root")
  func feedInfoKey() {
    let key = VideoFeedKeys.feedInfo(uri: VideoFeedConstants.videoFeedURI)
    #expect(key.root == "feedInfo")
    #expect(key.argsText.contains(VideoFeedConstants.videoFeedURI))
  }

  @Test("the feed key is not persisted")
  func feedKeyNotPersisted() {
    // RN keeps the post-feed query in memory (STALE.INFINITY, no persistedVersion)
    // and refreshes it explicitly.
    #expect(VideoFeedKeys.feed(.video).persistedVersion == nil)
    #expect(VideoFeedStale.feedPage == .infinity)
  }

  // MARK: - Fetchers

  @Test("the generator fetcher sends the feed URI, cursor and limit")
  func generatorFetcherCall() async throws {
    let xrpc = RecordingVideoFeedXrpc()
    xrpc.setFeedPages([VideoFeedPageOutput(cursor: "next")])
    let fetcher = VideoGeneratorFetcher(xrpc: xrpc, feedURI: VideoFeedConstants.videoFeedURI)

    let page = try await fetcher.fetch(cursor: nil, limit: 30)
    #expect(page.cursor == "next")
    #expect(
      xrpc.calls == [
        .feed(
          feed: VideoFeedConstants.videoFeedURI, cursor: nil, limit: 30,
          headers: VideoFeedRequestHeaders())
      ])
  }

  @Test("the generator fetcher truncates a page that ignores the limit")
  func generatorFetcherTruncates() async throws {
    let xrpc = RecordingVideoFeedXrpc()
    xrpc.setFeedPages([
      VideoFeedPageOutput(feed: [
        Fixtures.feedViewPost(Fixtures.post("a")),
        Fixtures.feedViewPost(Fixtures.post("b")),
        Fixtures.feedViewPost(Fixtures.post("c")),
      ])
    ])
    let fetcher = VideoGeneratorFetcher(xrpc: xrpc, feedURI: VideoFeedConstants.videoFeedURI)
    let page = try await fetcher.fetch(cursor: nil, limit: 2)
    #expect(page.feed.count == 2)
  }

  @Test("a Bluesky-owned feed receives the language and interests headers")
  func generatorHeaders() {
    let fetcher = VideoGeneratorFetcher(
      xrpc: RecordingVideoFeedXrpc(),
      feedURI: VideoFeedConstants.videoFeedURI,
      contentLanguages: ["en", "de"],
      userInterests: "tech",
      isAuthenticated: true)
    let headers = fetcher.requestHeaders
    #expect(headers.acceptLanguage == "en,de")
    #expect(headers.bskyTopics == "tech")
    #expect(headers.asHeaders["Accept-Language"] == "en,de")
    #expect(headers.asHeaders["X-Bsky-Topics"] == "tech")
  }

  @Test("a logged-out read sends no interests header")
  func loggedOutHeaders() {
    let fetcher = VideoGeneratorFetcher(
      xrpc: RecordingVideoFeedXrpc(),
      feedURI: VideoFeedConstants.videoFeedURI,
      userInterests: "tech",
      isAuthenticated: false)
    #expect(fetcher.requestHeaders.bskyTopics == nil)
  }

  @Test("a non-Bluesky feed never receives the interests header")
  func nonBlueskyFeedHeaders() {
    let fetcher = VideoGeneratorFetcher(
      xrpc: RecordingVideoFeedXrpc(),
      feedURI: "at://did:plc:someone/app.bsky.feed.generator/cats",
      userInterests: "tech",
      isAuthenticated: true)
    #expect(fetcher.requestHeaders.bskyTopics == nil)
    #expect(!VideoFeedOwners.owns(feedURI: "at://did:plc:someone/app.bsky.feed.generator/cats"))
  }

  @Test("the author fetcher sends the actor and filter")
  func authorFetcherCall() async throws {
    let xrpc = RecordingVideoFeedXrpc()
    xrpc.setAuthorPages([VideoFeedPageOutput(cursor: "c1")])
    let fetcher = VideoAuthorFetcher(
      xrpc: xrpc, actor: "did:plc:alice", filter: .postsWithVideo)

    let page = try await fetcher.fetch(cursor: "c0", limit: 25)
    #expect(page.cursor == "c1")
    #expect(
      xrpc.calls == [
        .authorFeed(actor: "did:plc:alice", filter: "posts_with_video", cursor: "c0", limit: 25)
      ])
  }

  @Test("includePins follows RN's posts_and_author_threads rule")
  func includePins() {
    #expect(
      !VideoAuthorFetcher(xrpc: RecordingVideoFeedXrpc(), actor: "a", filter: .postsWithVideo)
        .includePins)
    #expect(
      VideoAuthorFetcher(
        xrpc: RecordingVideoFeedXrpc(), actor: "a", filter: .postsAndAuthorThreads
      ).includePins)
  }

  @Test("the fetcher factory picks the branch by source")
  func fetcherFactory() async throws {
    let xrpc = RecordingVideoFeedXrpc()
    xrpc.setFeedPages([VideoFeedPageOutput()])
    xrpc.setAuthorPages([VideoFeedPageOutput()])

    _ = try await VideoFetcherFactory.makeFetcher(for: .video, xrpc: xrpc)
      .fetch(cursor: nil, limit: 1)
    _ = try await VideoFetcherFactory.makeFetcher(
      for: .author(did: "did:plc:a", filter: .postsWithVideo), xrpc: xrpc
    ).fetch(cursor: nil, limit: 1)

    guard case .feed = xrpc.calls[0] else {
      Issue.record("expected the generator branch first")
      return
    }
    guard case .authorFeed = xrpc.calls[1] else {
      Issue.record("expected the author branch second")
      return
    }
  }

  @Test("a transport failure propagates out of the fetcher")
  func fetcherPropagatesError() async {
    let xrpc = RecordingVideoFeedXrpc()
    xrpc.fail("feed")
    let fetcher = VideoGeneratorFetcher(xrpc: xrpc, feedURI: VideoFeedConstants.videoFeedURI)
    await #expect(throws: VideoFeedTestError.boom) {
      try await fetcher.fetch(cursor: nil, limit: 1)
    }
  }

  // MARK: - Query pipeline

  /// A query over a scripted fetcher.
  func makeQuery(
    pages: [VideoFeedPageOutput],
    source: VideoFeedSource = .video,
    store: QueryStore = QueryStore()
  ) -> VideoFeedQuery {
    VideoFeedQuery(
      store: store,
      source: source,
      fetcher: ScriptedVideoPageFetcher(pages: pages))
  }

  @Test("loading the first page tunes and filters to playable videos")
  func loadFirstPageFilters() async throws {
    let query = makeQuery(pages: [
      VideoFeedPageOutput(feed: [
        Fixtures.feedViewPost(Fixtures.post("v1", embed: Fixtures.videoEmbed("v1"))),
        Fixtures.feedViewPost(Fixtures.post("img", embed: Fixtures.galleryEmbed())),
        Fixtures.feedViewPost(Fixtures.post("v2", embed: Fixtures.videoEmbed("v2"))),
      ])
    ])
    let items = try await query.loadFirstPage()
    #expect(items.map(\.postURI) == [Fixtures.uri("v1"), Fixtures.uri("v2")])
  }

  @Test("the tuned pages are held under the video feed's key")
  func dataIsHeldUnderKey() async throws {
    let store = QueryStore()
    let query = makeQuery(
      pages: [
        VideoFeedPageOutput(feed: [
          Fixtures.feedViewPost(Fixtures.post("v1", embed: Fixtures.videoEmbed("v1")))
        ])
      ],
      store: store)

    _ = try await query.loadFirstPage()
    let held = await store.entry(query.key, as: InfiniteQueryData<VideoFeedSlice>.self)
    #expect(held.data?.items.count == 1)
    #expect(held.data?.items[0].feedPostUri == Fixtures.uri("v1"))
  }

  @Test("an empty page yields no items")
  func emptyPage() async throws {
    let query = makeQuery(pages: [])
    let items = try await query.loadFirstPage()
    #expect(items.isEmpty)
    #expect(await query.isEmpty())
  }

  @Test("a page of only non-video posts yields no items, but is not an empty feed")
  func nonVideoPage() async throws {
    let query = makeQuery(pages: [
      VideoFeedPageOutput(feed: [
        Fixtures.feedViewPost(Fixtures.post("img", embed: Fixtures.galleryEmbed()))
      ])
    ])
    let slices = await {
      _ = try? await query.loadFirstPage()
      return await query.slices()
    }()
    // The tuned slice survives - only the derived item list is empty.
    #expect(slices.count == 1)
    #expect(await query.isEmpty())
  }

  @Test("feedContext and reqId survive tuning onto the item")
  func contextSurvivesQuery() async throws {
    let query = makeQuery(pages: [
      VideoFeedPageOutput(feed: [
        Fixtures.feedViewPost(
          Fixtures.post("v1", embed: Fixtures.videoEmbed("v1")),
          feedContext: "ctx", reqId: "req")
      ])
    ])
    let items = try await query.loadFirstPage()
    #expect(items[0].feedContext == "ctx")
    #expect(items[0].reqId == "req")
  }

  @Test("pagination appends pages and keeps the order")
  func pagination() async throws {
    let query = makeQuery(pages: [
      VideoFeedPageOutput(
        cursor: "c1",
        feed: [Fixtures.feedViewPost(Fixtures.post("v1", embed: Fixtures.videoEmbed("v1")))]),
      VideoFeedPageOutput(
        cursor: nil,
        feed: [Fixtures.feedViewPost(Fixtures.post("v2", embed: Fixtures.videoEmbed("v2")))]),
    ])
    _ = try await query.loadFirstPage()
    let all = try await query.loadMore()
    #expect(all.map(\.postURI) == [Fixtures.uri("v1"), Fixtures.uri("v2")])
    let state = await query.paginationState()
    #expect(state.hasNextPage == false)
  }

  @Test("a page identifies slices by their react key, so a repeat collapses")
  func dedupesRepeatedSlices() async throws {
    let repeated = Fixtures.feedViewPost(
      Fixtures.post("v1", embed: Fixtures.videoEmbed("v1")))
    let query = makeQuery(pages: [
      VideoFeedPageOutput(cursor: "c1", feed: [repeated]),
      VideoFeedPageOutput(cursor: nil, feed: [repeated]),
    ])
    _ = try await query.loadFirstPage()
    let items = try await query.loadMore()
    #expect(items.count == 1)
  }

  @Test("the pager items apply the initial post offset")
  func pagerItemsOffset() async throws {
    let query = makeQuery(pages: [
      VideoFeedPageOutput(feed: [
        Fixtures.feedViewPost(Fixtures.post("v1", embed: Fixtures.videoEmbed("v1"))),
        Fixtures.feedViewPost(Fixtures.post("v2", embed: Fixtures.videoEmbed("v2"))),
        Fixtures.feedViewPost(Fixtures.post("v3", embed: Fixtures.videoEmbed("v3"))),
      ])
    ])
    _ = try await query.loadFirstPage()
    let items = await query.pagerItems(initialPostURI: Fixtures.uri("v2"))
    #expect(items.map(\.postURI) == [Fixtures.uri("v2"), Fixtures.uri("v3")])
  }

  @Test("refreshing truncates to one page and refetches")
  func refreshTruncates() async throws {
    let fetcher = ScriptedVideoPageFetcher(pages: [
      VideoFeedPageOutput(
        cursor: "c1",
        feed: [Fixtures.feedViewPost(Fixtures.post("v1", embed: Fixtures.videoEmbed("v1")))]),
      VideoFeedPageOutput(
        cursor: nil,
        feed: [Fixtures.feedViewPost(Fixtures.post("v2", embed: Fixtures.videoEmbed("v2")))]),
      VideoFeedPageOutput(
        cursor: nil,
        feed: [Fixtures.feedViewPost(Fixtures.post("v3", embed: Fixtures.videoEmbed("v3")))]),
    ])
    let query = VideoFeedQuery(store: QueryStore(), source: .video, fetcher: fetcher)
    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    #expect(await query.slices().count == 2)

    let refreshed = try await query.refresh()
    #expect(refreshed.map(\.postURI) == [Fixtures.uri("v3")])
    // The refresh is a real request, not a cache read.
    #expect(fetcher.cursors.count == 3)
  }

  @Test("subscribing pushes the playable items, and re-pushes on change")
  func subscription() async throws {
    let query = makeQuery(pages: [
      VideoFeedPageOutput(
        cursor: "c1",
        feed: [Fixtures.feedViewPost(Fixtures.post("v1", embed: Fixtures.videoEmbed("v1")))]),
      VideoFeedPageOutput(
        cursor: nil,
        feed: [Fixtures.feedViewPost(Fixtures.post("v2", embed: Fixtures.videoEmbed("v2")))]),
    ])
    let box = ItemBox()
    let subscription = await query.subscribeItems { items in box.set(items.count) }
    try await waitFor { box.value == 0 }
    _ = try await query.loadFirstPage()
    try await waitFor { box.value == 1 }
    _ = try await query.loadMore()
    try await waitFor { box.value == 2 }
    await subscription.cancel()
  }

  @Test("the query key matches the store entry it writes")
  func queryKeyMatchesEntry() async throws {
    let store = QueryStore()
    let query = VideoFeedQuery(
      store: store, source: .video,
      fetcher: ScriptedVideoPageFetcher(pages: []),
      feedCacheKey: .discover,
      scope: "did:plc:me")
    #expect(query.key == VideoFeedKeys.feed(.video, feedCacheKey: .discover, scope: "did:plc:me"))
    _ = try await query.loadFirstPage()
    let entry = await store.entry(query.key, as: InfiniteQueryData<VideoFeedSlice>.self)
    #expect(entry.data != nil)
  }

  @Test("removing the query clears its cache entry")
  func removeQuery() async throws {
    let store = QueryStore()
    let query = makeQuery(pages: [], store: store)
    _ = try await query.loadFirstPage()
    await query.remove()
    let entry = await store.entry(query.key, as: InfiniteQueryData<VideoFeedSlice>.self)
    #expect(entry.data == nil)
  }

  @Test("the query's fetcher failure surfaces from loadFirstPage")
  func loadFailure() async {
    let xrpc = RecordingVideoFeedXrpc()
    xrpc.fail("feed")
    let query = VideoFeedQuery(
      store: QueryStore(), source: .video,
      fetcher: VideoGeneratorFetcher(xrpc: xrpc, feedURI: VideoFeedConstants.videoFeedURI))
    await #expect(throws: VideoFeedTestError.boom) {
      try await query.loadFirstPage()
    }
  }
}

/// A lock-boxed counter for cross-task assertions.
final class ItemBox: @unchecked Sendable {
  private let lock = NSLock()
  private var _value = 0

  var value: Int { lock.withLock { _value } }
  func set(_ newValue: Int) { lock.withLock { _value = newValue } }
}

/// Polls `condition` until it holds, or throws after a short budget.
///
/// The store's subscription callbacks run on a detached task, so a test cannot
/// assume they have landed by the time the fetch returns.
func waitFor(
  timeout: TimeInterval = 2,
  _ condition: @Sendable () -> Bool
) async throws {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return }
    try await Task.sleep(nanoseconds: 5_000_000)
  }
  Issue.record("condition not met within \(timeout)s")
}
