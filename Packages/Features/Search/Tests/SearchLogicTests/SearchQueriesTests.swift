import Foundation
import Lexicons
import QueryStore
import Testing

@testable import SearchLogic

/// End-to-end coverage of the query layer: the real fetchers, a real
/// `QueryStore`, and explore assembly from the fixture responses the fake
/// client replays.
@Suite("SearchQueries integration")
struct SearchQueriesIntegrationTests {
  @Test("actor search paginates and de-dupes across pages by DID")
  func actorSearchPagination() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.actorSearch.nsid,
      App.Bsky.ActorSearchActors_Output(
        actors: [
          ProfileFixtures.profile(did: "did:plc:a", handle: "alice.test"),
          ProfileFixtures.profile(did: "did:plc:b", handle: "bob.test"),
        ],
        cursor: "page2"))
    try await client.enqueue(
      SearchEndpoints.actorSearch.nsid,
      App.Bsky.ActorSearchActors_Output(
        actors: [
          // Repeats `a`, which the store's identity policy must drop on merge.
          ProfileFixtures.profile(did: "did:plc:a", handle: "alice.test"),
          ProfileFixtures.profile(did: "did:plc:c", handle: "carol.test"),
        ],
        cursor: nil))

    let queries = SearchQueries(client: client)
    let query = queries.actorSearch(query: "test")
    try await query.loadFirstPage()
    try await query.loadMore()
    let items = await query.items()
    #expect(items.map(\.did.rawValue) == ["did:plc:a", "did:plc:b", "did:plc:c"])
    #expect(await query.hasNextPage() == false)
  }

  @Test("post search paginates with the v2 param set")
  func postSearchPagination() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.searchPostsV2.nsid,
      App.Bsky.FeedSearchPostsV2_Output(cursor: nil, posts: []))
    let queries = SearchQueries(client: client)
    _ = try await queries.loadSearchPosts(query: "cats", sort: .top)
    let params = await client.lastParams(for: SearchEndpoints.searchPostsV2.nsid)
    #expect(params["query"] == "cats")
    #expect(params["sort"] == "top")
    #expect(params["allTime"] == "true")
  }

  @Test("explore assembles from the fixture responses the fake replays")
  func exploreAssemblyFromFixtures() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.trendingTopics.nsid,
      App.Bsky.UnspeccedGetTrendingTopics_Output(
        suggested: [],
        topics: [ProfileFixtures.trendingTopic(link: "/t/1", topic: "art", displayName: "Art")]))
    try await client.enqueue(
      SearchEndpoints.suggestedUsersForExplore.nsid,
      App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(
        actors: [ProfileFixtures.profile(did: "did:plc:a", handle: "alice.test")],
        recIdStr: "rec-1"))
    try await client.enqueue(
      SearchEndpoints.suggestedFeeds.nsid,
      App.Bsky.UnspeccedGetSuggestedFeeds_Output(
        feeds: [ProfileFixtures.generatorView(uri: "at://f/1", did: "did:plc:f", name: "Feed")]))
    try await client.enqueue(
      SearchEndpoints.suggestedStarterPacks.nsid,
      App.Bsky.UnspeccedGetSuggestedStarterPacks_Output(
        starterPacks: [ProfileFixtures.starterPack(uri: "at://sp/1")]))

    let queries = SearchQueries(client: client)
    let topics = try await queries.getTrendingTopics(limit: 5)
    let users = try await queries.suggestedUsersForExplore()
    let feeds = try await queries.suggestedFeeds()
    let packs = try await queries.suggestedStarterPacks()

    let page = ExploreAssembly.build(
      ExploreAssembly.Input(
        trendingTopics: topics,
        suggestedUsers: users,
        suggestedFeeds: feeds,
        suggestedStarterPacks: packs,
        useFullExperience: true))

    #expect(
      page.sections.map(\.title)
        == [.trending, .suggestedFeeds, .suggestedAccounts, .starterPacks])
    #expect(page.recId == "rec-1")
    #expect(page.section(.suggestedAccounts)?.items.count == 1)
  }

  @Test("a second read of a fresh query is served from the cache")
  func cachingDedupes() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.trendingTopics.nsid,
      App.Bsky.UnspeccedGetTrendingTopics_Output(suggested: [], topics: []))
    let queries = SearchQueries(client: client)
    _ = try await queries.getTrendingTopics(limit: 5)
    _ = try await queries.getTrendingTopics(limit: 5)
    #expect(await client.recordedCount(for: SearchEndpoints.trendingTopics.nsid) == 1)
  }

  @Test("the actor search query key is scoped per account")
  func scopingSeparatesAccounts() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.actorSearch.nsid,
      App.Bsky.ActorSearchActors_Output(actors: []))
    try await client.enqueue(
      SearchEndpoints.actorSearch.nsid,
      App.Bsky.ActorSearchActors_Output(actors: []))
    let queries = SearchQueries(client: client)
    _ = try await queries.loadActorSearch(query: "alice", scope: "did:plc:me")
    _ = try await queries.loadActorSearch(query: "alice", scope: "did:plc:you")
    #expect(await client.recordedCount(for: SearchEndpoints.actorSearch.nsid) == 2)
  }
}
