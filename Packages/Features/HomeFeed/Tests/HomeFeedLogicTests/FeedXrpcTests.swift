import ATProtoClient
import Foundation
import Lexicons
import Preferences
import QueryStore
import Testing

@testable import HomeFeedLogic

/// Query-key semantics: roots, args identity, scope and persisted version.
@Suite("HomeFeed query keys")
struct HomeFeedKeyTests {
  @Test("the feed key root and descriptor match RN's RQKEY shape")
  func feedKeyRoot() {
    let key = HomeFeedKeys.feed(.following)
    #expect(key.keyRoot == "post-feed")
    #expect(key.argsDebugDescription.contains("following"))
  }

  @Test("two descriptors produce two distinct keys")
  func descriptorDistinctness() {
    let following = HomeFeedKeys.feed(.following)
    let feedgen = HomeFeedKeys.feed(.feedgen(uri: "at://did:plc:x/app.bsky.feed.generator/a"))
    #expect(following != feedgen)
  }

  @Test("the merge-feed flag participates in the key, as RN's params do")
  func mergeFlagParticipates() {
    #expect(HomeFeedKeys.feed(.following, mergeFeedEnabled: false) != HomeFeedKeys.feed(.following, mergeFeedEnabled: true))
  }

  @Test("account scope separates two accounts' entries")
  func scopeSeparatesAccounts() {
    #expect(HomeFeedKeys.feed(.following, scope: "did:plc:a") != HomeFeedKeys.feed(.following, scope: "did:plc:b"))
  }

  @Test("feed-info keys carry persistedVersion 1, matching RN")
  func feedInfoPersistedVersion() {
    let key = HomeFeedKeys.feedInfo(kind: .pinned, feedUris: ["following"])
    #expect(key.persistedVersion == 1)
    #expect(key.keyRoot == "feed-info")
  }

  @Test("feed-info keys differ by kind and by the saved URI list")
  func feedInfoIdentity() {
    let pinned = HomeFeedKeys.feedInfo(kind: .pinned, feedUris: ["following"])
    let saved = HomeFeedKeys.feedInfo(kind: .saved, feedUris: ["following"])
    let other = HomeFeedKeys.feedInfo(kind: .pinned, feedUris: ["following", "at://x"])
    #expect(pinned != saved)
    #expect(pinned != other)
  }

  @Test("the key roots are the ones RN uses")
  func roots() {
    #expect(HomeFeedKeys.feedSourceInfo(uri: "at://x").keyRoot == "getFeedSourceInfo")
    #expect(HomeFeedKeys.feedGenerator(uri: "at://x").keyRoot == "feedInfo")
    #expect(HomeFeedKeys.actorFeeds(actor: "did:plc:a").keyRoot == "profile-feedgens")
  }
}

/// Descriptor round-tripping, since descriptors are the key arguments.
@Suite("FeedDescriptor")
struct FeedDescriptorTests {
  @Test("descriptors render in RN's string form")
  func rendering() {
    #expect(FeedDescriptor.following.description == "following")
    #expect(FeedDescriptor.feedgen(uri: "at://f").description == "feedgen|at://f")
    #expect(FeedDescriptor.list(uri: "at://l").description == "list|at://l")
  }

  @Test("descriptors parse back from their RN strings")
  func parsing() {
    #expect(FeedDescriptor(descriptor: "following") == .following)
    #expect(FeedDescriptor(descriptor: "feedgen|at://f") == .feedgen(uri: "at://f"))
    #expect(FeedDescriptor(descriptor: "list|at://l") == .list(uri: "at://l"))
  }

  @Test("descriptors this feature does not own do not parse")
  func foreignDescriptors() {
    #expect(FeedDescriptor(descriptor: "author|did:plc:a|posts_with_replies") == nil)
    #expect(FeedDescriptor(descriptor: "demo") == nil)
  }
}

/// The @Suite that asserts the exact XRPC surface: params, routing and headers.
@Suite("Feed XRPC calls")
struct FeedXrpcCallTests {
  /// A live client over a recording transport, pointed at a PDS base URL.
  func makeLiveClient(
    proxy: String? = "did:web:api.bsky.app#bsky_appview"
  ) -> (LiveFeedXrpc, RecordingTransport) {
    let transport = RecordingTransport()
    let client = XrpcClient(
      baseURL: "https://pds.example.com", proxyService: proxy,
      labelers: ["did:plc:labeler;redact"], extraHeaders: ["Authorization": "Bearer jwt"],
      transport: transport)
    return (LiveFeedXrpc(client: client, authorization: "jwt"), transport)
  }

  @Test("getTimeline hits app.bsky.feed.getTimeline with cursor and limit")
  func timelineParams() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getTimeline(cursor: "cur1", limit: 30)
    let request = try #require(transport.received.last)
    #expect(request.method == "GET")
    #expect(request.url.hasPrefix("https://pds.example.com/xrpc/app.bsky.feed.getTimeline?"))
    #expect(request.url.contains("cursor=cur1"))
    #expect(request.url.contains("limit=30"))
  }

  @Test("getTimeline routes through the appview proxy and carries the labelers")
  func timelineRouting() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getTimeline(cursor: nil, limit: 30)
    let request = try #require(transport.received.last)
    #expect(request.headers["atproto-proxy"] == "did:web:api.bsky.app#bsky_appview")
    #expect(request.headers["atproto-accept-labelers"] == "did:plc:labeler;redact")
    #expect(request.headers["Authorization"] == "Bearer jwt")
  }

  @Test("getFeed sends the feed URI, its cursor and limit")
  func customFeedParams() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getFeed(
      feed: "at://did:plc:f/app.bsky.feed.generator/cool", cursor: nil, limit: 30,
      headers: FeedRequestHeaders())
    let request = try #require(transport.received.last)
    #expect(request.url.hasPrefix("https://pds.example.com/xrpc/app.bsky.feed.getFeed?"))
    #expect(request.url.contains("feed=at%3A%2F%2Fdid%3Aplc%3Af%2Fapp.bsky.feed.generator%2Fcool"))
    #expect(request.url.contains("limit=30"))
    // No cursor means no cursor param at all.
    #expect(!request.url.contains("cursor="))
  }

  @Test("getFeed merges the feed headers onto the routed client")
  func customFeedHeaders() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getFeed(
      feed: "at://did:plc:f/app.bsky.feed.generator/cool", cursor: "c", limit: 30,
      headers: FeedRequestHeaders(acceptLanguage: "en,de", bskyTopics: "tech,art"))
    let request = try #require(transport.received.last)
    #expect(request.headers["Accept-Language"] == "en,de")
    #expect(request.headers["X-Bsky-Topics"] == "tech,art")
    // The proxy and auth headers must survive the per-call merge.
    #expect(request.headers["atproto-proxy"] == "did:web:api.bsky.app#bsky_appview")
    #expect(request.headers["Authorization"] == "Bearer jwt")
  }

  @Test("getFeedSkeleton hits the generator endpoint")
  func skeletonParams() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getFeedSkeleton(
      feed: "at://did:plc:f/app.bsky.feed.generator/cool", cursor: "sk", limit: 30)
    let request = try #require(transport.received.last)
    #expect(request.url.hasPrefix("https://pds.example.com/xrpc/app.bsky.feed.getFeedSkeleton?"))
    #expect(request.url.contains("cursor=sk"))
  }

  @Test("getPosts repeats the uris query parameter, one per URI")
  func postsRepeatedParam() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getPosts(uris: ["at://a", "at://b"])
    let request = try #require(transport.received.last)
    #expect(request.url.hasPrefix("https://pds.example.com/xrpc/app.bsky.feed.getPosts?"))
    #expect(request.url.contains("uris=at%3A%2F%2Fa"))
    #expect(request.url.contains("uris=at%3A%2F%2Fb"))
  }

  @Test("getFeedGenerators repeats the feeds parameter for the batch read")
  func generatorsBatchParam() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getFeedGenerators(feeds: ["at://a", "at://b"])
    let request = try #require(transport.received.last)
    #expect(request.url.hasPrefix("https://pds.example.com/xrpc/app.bsky.feed.getFeedGenerators?"))
    #expect(request.url.contains("feeds=at%3A%2F%2Fa"))
    #expect(request.url.contains("feeds=at%3A%2F%2Fb"))
  }

  @Test("getList carries limit 1, as RN's saved-list hydration does")
  func listLimit() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getList(list: "at://did:plc:a/app.bsky.graph.list/friends")
    let request = try #require(transport.received.last)
    #expect(request.url.hasPrefix("https://pds.example.com/xrpc/app.bsky.graph.getList?"))
    #expect(request.url.contains("limit=1"))
  }

  @Test("getFeedGenerator and getActorFeeds use their endpoint ids")
  func generatorAndActorFeeds() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getFeedGenerator(feed: "at://g")
    _ = try? await xrpc.getActorFeeds(actor: "did:plc:a", cursor: nil, limit: 50)
    let requests = transport.received
    #expect(requests[0].url.hasPrefix("https://pds.example.com/xrpc/app.bsky.feed.getFeedGenerator?"))
    #expect(requests[1].url.hasPrefix("https://pds.example.com/xrpc/app.bsky.feed.getActorFeeds?"))
    #expect(requests[1].url.contains("actor=did%3Aplc%3Aa"))
  }

  @Test("getConfig hits app.bsky.unspecced.getConfig")
  func configEndpoint() async throws {
    let (xrpc, transport) = makeLiveClient()
    _ = try? await xrpc.getConfig()
    let request = try #require(transport.received.last)
    #expect(request.url.hasPrefix("https://pds.example.com/xrpc/app.bsky.unspecced.getConfig"))
  }

  @Test("the logged-out public client sends no proxy header")
  func loggedOutClientHasNoProxy() async throws {
    let transport = RecordingTransport()
    let client = XrpcClient(
      baseURL: "https://public.api.bsky.app", proxyService: nil,
      labelers: nil, extraHeaders: [:], transport: transport)
    let xrpc = LiveFeedXrpc(client: client)
    _ = try? await xrpc.getFeed(
      feed: "at://f", cursor: nil, limit: 30, headers: FeedRequestHeaders())
    let request = try #require(transport.received.last)
    #expect(request.headers["atproto-proxy"] == nil)
  }
}

/// Header construction per feed type, ported from `custom.ts` and `utils.ts`.
@Suite("Feed request headers")
struct FeedRequestHeaderTests {
  @Test("a Bluesky-owned feed receives the topics header")
  func blueskyOwnedGetsTopics() {
    let fetcher = CustomFeedFetcher(
      xrpc: RecordingFeedXrpc(),
      feedURI: "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot",
      contentLanguages: ["en"],
      userInterests: "tech")
    #expect(fetcher.requestHeaders.bskyTopics == "tech")
  }

  @Test("a third-party feed does not receive the topics header")
  func thirdPartyHasNoTopics() {
    let fetcher = CustomFeedFetcher(
      xrpc: RecordingFeedXrpc(),
      feedURI: "at://did:plc:someoneelse/app.bsky.feed.generator/cool",
      contentLanguages: ["en"],
      userInterests: "tech")
    #expect(fetcher.requestHeaders.bskyTopics == nil)
  }

  @Test("a logged-out reader gets no topics header even on a Bluesky feed")
  func loggedOutHasNoTopics() {
    let fetcher = CustomFeedFetcher(
      xrpc: RecordingFeedXrpc(),
      feedURI: "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot",
      contentLanguages: ["en"],
      userInterests: "tech",
      isAuthenticated: false)
    #expect(fetcher.requestHeaders.bskyTopics == nil)
  }

  @Test("content languages join with a comma, as Accept-Language expects")
  func contentLanguagesJoin() {
    let fetcher = CustomFeedFetcher(
      xrpc: RecordingFeedXrpc(), feedURI: "at://f", contentLanguages: ["en", "de"])
    #expect(fetcher.requestHeaders.acceptLanguage == "en,de")
  }

  @Test("the feed owner list matches RN's BSKY_FEED_OWNER_DIDS")
  func ownerList() {
    #expect(
      BlueskyFeedOwners.owns(
        feedURI: "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"))
    #expect(!BlueskyFeedOwners.owns(feedURI: "at://did:plc:other/app.bsky.feed.generator/x"))
    #expect(!BlueskyFeedOwners.owns(feedURI: "not-a-uri"))
  }
}
