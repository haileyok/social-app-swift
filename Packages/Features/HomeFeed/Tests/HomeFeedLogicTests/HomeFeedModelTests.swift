import ATProtoClient
import Domain
import Foundation
import Lexicons
import QueryStore
import Testing

@testable import HomeFeedLogic

/// Feed-switch state, presentation branching and page-state derivation.
@Suite("Home feed model")
struct HomeFeedModelTests {
  let feedURI = "at://did:plc:feeds/app.bsky.feed.generator/cool"

  func makeModel(
    store: QueryStore, xrpc: RecordingFeedXrpc, pinned: [PinnedFeed]
  ) -> HomeFeedModel {
    var fetchers: [String: any FeedPageFetcher] = [:]
    for feed in pinned {
      switch feed.descriptor {
      case .following:
        fetchers["following"] = FollowingFeedFetcher(xrpc: xrpc)
      case .feedgen(let uri):
        fetchers["feedgen|\(uri)"] = CustomFeedFetcher(xrpc: xrpc, feedURI: uri)
      case .list(let uri):
        fetchers["list|\(uri)"] = ListFeedFetcher(xrpc: xrpc, listURI: uri)
      }
    }
    return HomeFeedModel(
      store: store,
      pinnedFeeds: pinned,
      fetchersByDescriptor: fetchers,
      tunerOptionsByDescriptor: [:])
  }

  @Test("the first pinned feed is selected by default")
  func defaultSelection() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let model = makeModel(store: store, xrpc: xrpc, pinned: [
      PinnedFeed.timeline(Fixtures.timelineEntry()),
      PinnedFeed(
        config: Fixtures.feedEntry(feedURI), displayName: "Cool"),
    ])
    #expect(model.selectedDescriptor == .following)
    #expect(model.allDescriptors == [.following, .feedgen(uri: feedURI)])
  }

  @Test("selecting another pinned feed switches the active query")
  func selectionSwitch() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    var model = makeModel(store: store, xrpc: xrpc, pinned: [
      PinnedFeed.timeline(Fixtures.timelineEntry()),
      PinnedFeed(config: Fixtures.feedEntry(feedURI), displayName: "Cool"),
    ])

    model.select(.feedgen(uri: feedURI))
    #expect(model.selectedDescriptor == .feedgen(uri: feedURI))
    #expect(model.selectedQuery?.descriptor == .feedgen(uri: feedURI))
  }

  @Test("selecting an unknown descriptor leaves the selection alone")
  func unknownSelectionIgnored() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    var model = makeModel(store: store, xrpc: xrpc, pinned: [
      PinnedFeed.timeline(Fixtures.timelineEntry())
    ])

    model.select(.feedgen(uri: "at://unknown"))
    #expect(model.selectedDescriptor == .following)
  }

  @Test("each pinned feed gets its own query key, so feeds never share a cache entry")
  func perFeedQueries() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let model = makeModel(store: store, xrpc: xrpc, pinned: [
      PinnedFeed.timeline(Fixtures.timelineEntry()),
      PinnedFeed(config: Fixtures.feedEntry(feedURI), displayName: "Cool"),
    ])
    let following = try #require(model.queries["following"])
    let feed = try #require(model.queries["feedgen|\(feedURI)"])
    #expect(following.key != feed.key)
  }

  @Test("a feed with no resolvable fetcher is omitted rather than crashing")
  func missingFetcherOmitted() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let model = HomeFeedModel(
      store: store,
      pinnedFeeds: [PinnedFeed.timeline(Fixtures.timelineEntry())],
      fetchersByDescriptor: [:],
      tunerOptionsByDescriptor: [:])
    #expect(model.queries.isEmpty)
    #expect(model.selectedQuery == nil)
  }

  // MARK: - Presentation

  @Test("no session renders the logged-out presentation")
  func loggedOut() {
    let presentation = HomeFeedModel.presentation(
      hasSession: false, isLoadingPreferences: false, pinnedFeeds: [])
    #expect(presentation == .loggedOut)
    #expect(!presentation.showsAddFeeds)
  }

  @Test("a session with unpinned feeds renders the add-feeds state")
  func noFeedsPinned() {
    let presentation = HomeFeedModel.presentation(
      hasSession: true, isLoadingPreferences: false, pinnedFeeds: [])
    #expect(presentation == .noFeedsPinned)
    #expect(presentation.showsAddFeeds)
  }

  @Test("still loading preferences renders the loading state, not add-feeds")
  func loadingPreferences() {
    let presentation = HomeFeedModel.presentation(
      hasSession: true, isLoadingPreferences: true, pinnedFeeds: [])
    #expect(presentation == .loading)
    #expect(!presentation.showsAddFeeds)
  }

  @Test("a session with pinned feeds renders the feeds")
  func feedsPresentation() {
    let presentation = HomeFeedModel.presentation(
      hasSession: true, isLoadingPreferences: false,
      pinnedFeeds: [PinnedFeed.timeline(Fixtures.timelineEntry())])
    #expect(presentation == .feeds)
  }

  // MARK: - Page state

  @Test("a feed with data shows content")
  func pageStateContent() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [Fixtures.item("a")])])
    let store = QueryStore()
    let model = makeModel(store: store, xrpc: xrpc, pinned: [
      PinnedFeed.timeline(Fixtures.timelineEntry())
    ])
    _ = try await model.selectedQuery?.loadFirstPage()
    #expect(await model.pageState() == .content)
  }

  @Test("a completed load with no slices shows the empty state")
  func pageStateEmpty() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setTimelinePages([FeedTimelinePage(cursor: nil, feed: [])])
    let store = QueryStore()
    let model = makeModel(store: store, xrpc: xrpc, pinned: [
      PinnedFeed.timeline(Fixtures.timelineEntry())
    ])
    _ = try await model.selectedQuery?.loadFirstPage()
    #expect(await model.pageState() == .empty)
  }

  @Test("a failure with no data shows the error state")
  func pageStateError() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.fail("timeline")
    let store = QueryStore()
    let model = makeModel(store: store, xrpc: xrpc, pinned: [
      PinnedFeed.timeline(Fixtures.timelineEntry())
    ])
    _ = try? await model.selectedQuery?.loadFirstPage()
    guard case .error = await model.pageState() else {
      Issue.record("expected an error page state")
      return
    }
  }

  @Test("the page-state derivation follows RN's branch order")
  func pageStateDerivation() {
    // Error with no data wins over loading.
    #expect(
      FeedPageState.derive(hasData: false, isFetching: true, isEmpty: true, error: .network)
        == .error(.network))
    // Loading when there is no data yet.
    #expect(
      FeedPageState.derive(hasData: false, isFetching: true, isEmpty: false, error: nil)
        == .loading)
    // Empty after a completed load.
    #expect(
      FeedPageState.derive(hasData: false, isFetching: false, isEmpty: true, error: nil)
        == .empty)
    // Content when data arrived.
    #expect(
      FeedPageState.derive(hasData: true, isFetching: false, isEmpty: false, error: nil)
        == .content)
    // A stale payload still renders as content even while refreshing.
    #expect(
      FeedPageState.derive(hasData: true, isFetching: true, isEmpty: false, error: .network)
        == .content)
  }

  @Test("a network failure classifies as network")
  func networkClassification() {
    // The Domain classifier matches on the stringified error containing a known
    // network marker, so the test uses the same shape a fetch failure produces.
    let error = XrpcError(
      rawCode: nil, message: "Network request failed", status: -1)
    #expect(HomeFeedError.classify(error) == .network)
  }

  @Test("an XRPC failure classifies as a service failure with its message")
  func serviceClassification() {
    let error = XrpcError(
      rawCode: "InvalidRequest", message: "feed offline", status: 400)
    #expect(HomeFeedError.classify(error) == .service(message: "feed offline"))
  }
}

/// A cross-check that the package's model round-trips through the store as the
/// persisted `feed-info` payload.
@Suite("Resolved feed info persistence")
struct ResolvedFeedInfoTests {
  @Test("a resolved pinned list round-trips through its persisted form")
  func roundTrip() throws {
    let pinned = [
      PinnedFeed.timeline(Fixtures.timelineEntry()),
      PinnedFeed(
        config: Fixtures.feedEntry("at://f"), displayName: "Cool", creatorHandle: "maker.test"),
    ]
    let resolved = ResolvedFeedInfo(from: pinned)
    #expect(resolved.count == 2)

    let data = try resolved.encodePersisted()
    let restored = try ResolvedFeedInfo.decodePersisted(data)
    #expect(restored.count == 2)
    #expect(restored.feeds.map(\.displayName) == ["Following", "Cool"])
    #expect(restored.feeds[1].pinnedFeed.descriptor == .feedgen(uri: "at://f"))
  }
}
