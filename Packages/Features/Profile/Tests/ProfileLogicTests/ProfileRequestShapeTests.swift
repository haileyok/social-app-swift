import Foundation
import Lexicons
import Testing

@testable import ProfileLogic

/// Pins the exact XRPC request each profile read issues.
///
/// This is the "exact params per tab" requirement: every test asserts the path,
/// the query parameters, and the omission of parameters that must not be sent.
@Suite("Profile request shapes") struct ProfileRequestShapeTests {

  // MARK: - Tab parameter sets

  /// The parameter set for each tab, cross-checked against the RN descriptors
  /// `author|<did>|<filter>` and `likes|<did>`.
  @Test func tabParametersMatchTheRnDescriptors() {
    let cases: [(tab: ProfileTab, filter: String?, includePins: String, endpoint: String)] = [
      (.posts, "posts_and_author_threads", "true", "app.bsky.feed.getAuthorFeed"),
      (.replies, "posts_with_replies", "false", "app.bsky.feed.getAuthorFeed"),
      (.media, "posts_with_media", "false", "app.bsky.feed.getAuthorFeed"),
      (.videos, "posts_with_video", "false", "app.bsky.feed.getAuthorFeed"),
      (.likes, nil, "false", "app.bsky.feed.getActorLikes"),
    ]
    for (tab, filter, includePins, endpoint) in cases {
      let request = ProfileFeedRequest(actor: "did:plc:alice", tab: tab)
      #expect(request.endpoint == endpoint, "endpoint for \(tab.rawValue)")
      #expect(request.filter?.rawValue == filter, "filter for \(tab.rawValue)")
      #expect(request.includePins == (includePins == "true"), "includePins for \(tab.rawValue)")
    }
  }

  /// The posts tab is `posts_and_author_threads`, not `posts_no_replies` - the
  /// distinction the RN profile screen makes.
  @Test func postsTabUsesAuthorThreadsNotNoReplies() {
    #expect(ProfileTab.posts.authorFeedFilter == .postsAndAuthorThreads)
    #expect(ProfileTab.posts.authorFeedFilter != .postsNoReplies)
  }

  /// `includePins` is derived from the filter, so only posts asks for pins.
  @Test func includePinsFollowsTheFilter() {
    for tab in ProfileTab.allCases {
      #expect(tab.includePins == (tab.authorFeedFilter == .postsAndAuthorThreads))
    }
  }

  /// The likes tab always goes to `getActorLikes`, which takes no filter.
  @Test func likesTabUsesGetActorLikes() {
    #expect(!ProfileTab.likes.usesAuthorFeed)
    let query = ProfileFeedRequest(actor: "did:plc:alice", tab: .likes)
      .parameters(cursor: "c1", limit: 30)
    #expect(!query.contains { $0.0 == "filter" })
    #expect(!query.contains { $0.0 == "includePins" })
  }

  /// Every tab requests a page of 30, matching `MIN_POSTS` in `post-feed.ts`.
  @Test func everyTabRequestsThirtyItems() {
    for tab in ProfileTab.allCases {
      #expect(tab.pageSize == 30, "page size for \(tab.rawValue)")
    }
  }

  // MARK: - Live requests

  /// The posts tab issues a `getAuthorFeed` with the author-threads filter.
  @Test func postsPageSendsTheAuthorThreadsRequest() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(["feed": []])])
    let client = makeClient(transport)
    _ = try await client.getAuthorFeedPage(
      actor: "did:plc:alice", tab: ProfileTab.posts, cursor: nil, limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.method == "GET")
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.feed.getAuthorFeed")
    #expect(request.query["actor"] == "did:plc:alice")
    #expect(request.query["filter"] == "posts_and_author_threads")
    #expect(request.query["includePins"] == "true")
    #expect(request.query["limit"] == "30")
    #expect(request.query["cursor"] == nil, "a first page sends no cursor")
  }

  /// The replies tab differs only in filter and pins.
  @Test func repliesPageSendsTheRepliesRequest() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(["feed": []])])
    let client = makeClient(transport)
    _ = try await client.getAuthorFeedPage(
      actor: "did:plc:alice", tab: ProfileTab.replies, cursor: "next", limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.query["filter"] == "posts_with_replies")
    #expect(request.query["includePins"] == "false")
    #expect(request.query["cursor"] == "next")
  }

  /// The media tab.
  @Test func mediaPageSendsTheMediaRequest() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(["feed": []])])
    let client = makeClient(transport)
    _ = try await client.getAuthorFeedPage(
      actor: "did:plc:alice", tab: ProfileTab.media, cursor: nil, limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.query["filter"] == "posts_with_media")
  }

  /// The videos tab.
  @Test func videosPageSendsTheVideoRequest() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(["feed": []])])
    let client = makeClient(transport)
    _ = try await client.getAuthorFeedPage(
      actor: "did:plc:alice", tab: ProfileTab.videos, cursor: nil, limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.query["filter"] == "posts_with_video")
  }

  /// The likes tab targets `getActorLikes` and sends neither filter nor pins.
  @Test func likesPageSendsTheActorLikesRequest() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(["feed": []])])
    let client = makeClient(transport)
    _ = try await client.getAuthorFeedPage(
      actor: "did:plc:alice", tab: ProfileTab.likes, cursor: nil, limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.feed.getActorLikes")
    #expect(request.query["actor"] == "did:plc:alice")
    #expect(request.query["filter"] == nil)
    #expect(request.query["includePins"] == nil)
  }

  /// `getProfile` sends only the actor.
  @Test func getProfileSendsOnlyTheActor() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(profileJSON())])
    let client = makeClient(transport)
    let profile = try await client.getProfile(actor: "did:plc:alice")

    #expect(profile.handle.rawValue == "alice.example.com")
    let request = try #require(transport.lastRequest)
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.actor.getProfile")
    #expect(request.query == ["actor": "did:plc:alice"])
  }

  /// `getProfiles` sends a comma-joined actor list.
  @Test func getProfilesJoinsActorsWithCommas() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(["profiles": []])])
    let client = makeClient(transport)
    _ = try await client.getProfiles(actors: ["did:plc:a", "did:plc:b"])

    let request = try #require(transport.lastRequest)
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.actor.getProfiles")
    #expect(request.query["actors"] == "did:plc:a,did:plc:b")
  }

  /// A follows page sends actor, limit and (when set) sort.
  @Test func followsPageSendsActorLimitAndSort() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(GraphJSON.follows())])
    let client = makeClient(transport)
    _ = try await client.getFollowsPage(
      actor: "did:plc:alice", sort: ActorListSort.latest, cursor: nil, limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.graph.getFollows")
    #expect(request.query["actor"] == "did:plc:alice")
    #expect(request.query["limit"] == "30")
    #expect(request.query["sort"] == "latest")
  }

  /// The sort parameter is omitted entirely when the feature flag is off, which
  /// is what the RN conditional spread achieves.
  @Test func followsPageOmitsSortWhenUnset() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(GraphJSON.follows())])
    let client = makeClient(transport)
    _ = try await client.getFollowsPage(
      actor: "did:plc:alice", sort: nil, cursor: nil, limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.query["sort"] == nil)
  }

  /// A followers page defaults to a 30-item page.
  @Test func followersPageSendsActorAndLimit() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(GraphJSON.followers())])
    let client = makeClient(transport)
    _ = try await client.getFollowersPage(
      actor: "did:plc:alice", sort: nil, cursor: "c", limit: 30)

    let request = try #require(transport.lastRequest)
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.graph.getFollowers")
    #expect(request.query["cursor"] == "c")
  }

  /// A known-followers page requests 50 items, matching the RN `PAGE_SIZE`.
  @Test func knownFollowersPageRequestsFifty() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(GraphJSON.followers())])
    let client = makeClient(transport)
    _ = try await client.getKnownFollowersPage(
      actor: "did:plc:alice", cursor: nil, limit: ProfileFetchers.knownFollowersPageSize)

    let request = try #require(transport.lastRequest)
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.graph.getKnownFollowers")
    #expect(request.query["limit"] == "50")
  }

  /// The single-labeler query asks for a detailed view.
  @Test func labelerServiceQueryAsksForDetail() async throws {
    let transport = ScriptedTransport(script: [ScriptedTransport.json(["views": []])])
    let client = makeClient(transport)
    _ = try await client.getLabelerService(did: "did:plc:labeler")

    let request = try #require(transport.lastRequest)
    #expect(request.path == "https://api.example.com/xrpc/app.bsky.labeler.getServices")
    #expect(request.query["dids"] == "did:plc:labeler")
    #expect(request.query["detailed"] == "true")
  }
}
