import Lexicons
import Testing

@testable import SearchLogic

/// Verifies each fetcher sends the exact param set its endpoint declares, by
/// driving the real fetchers against ``FakeSearchClient``.
@Suite("SearchFetchers param encoding")
struct SearchFetchersTests {
  @Test("actor search sends q, limit and cursor")
  func actorSearch() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.actorSearch.nsid,
      App.Bsky.ActorSearchActors_Output(actors: [], cursor: "next"))
    let fetchers = SearchFetchers(client: client)
    let out = try await fetchers.searchActors(query: "alice", limit: 25, cursor: "c1")
    #expect(out.cursor == "next")
    let params = await client.lastParams(for: SearchEndpoints.actorSearch.nsid)
    #expect(params["q"] == "alice")
    #expect(params["limit"] == "25")
    #expect(params["cursor"] == "c1")
  }

  @Test("actor search omits the cursor on the first page")
  func actorSearchFirstPage() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.actorSearch.nsid, App.Bsky.ActorSearchActors_Output(actors: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.searchActors(query: "alice")
    let params = await client.lastParams(for: SearchEndpoints.actorSearch.nsid)
    #expect(params["cursor"] == nil)
  }

  @Test("typeahead sends q and limit with the 8 default")
  func typeahead() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.actorTypeahead.nsid, App.Bsky.ActorSearchActorsTypeahead_Output(actors: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.searchActorsTypeahead(prefix: "ali")
    let params = await client.lastParams(for: SearchEndpoints.actorTypeahead.nsid)
    #expect(params["q"] == "ali")
    #expect(params["limit"] == "8")
  }

  @Test("post search v2 lifts operators, sets allTime and maps latest to recent")
  func postSearchV2() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.searchPostsV2.nsid, App.Bsky.FeedSearchPostsV2_Output(posts: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.searchPostsV2(
      query: "cats from:alice #tag", sort: .latest, filters: SearchFilters(author: "bob"))
    let params = await client.lastParams(for: SearchEndpoints.searchPostsV2.nsid)
    #expect(params["query"] == "cats")
    #expect(params["allTime"] == "true")
    #expect(params["sort"] == "recent")
    #expect(params["limit"] == "25")
    #expect(params["authors"] == "alice,bob")
    #expect(params["hashtags"] == "tag")
  }

  @Test("post search v2 re-appends from:me when the Me filter is active")
  func postSearchV2FromMe() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.searchPostsV2.nsid, App.Bsky.FeedSearchPostsV2_Output(posts: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.searchPostsV2(query: "cats", filters: SearchFilters(from: "me"))
    let params = await client.lastParams(for: SearchEndpoints.searchPostsV2.nsid)
    #expect(params["query"] == "cats from:me")
  }

  @Test("post search v2 omits sort when none is given")
  func postSearchV2NoSort() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.searchPostsV2.nsid, App.Bsky.FeedSearchPostsV2_Output(posts: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.searchPostsV2(query: "cats")
    let params = await client.lastParams(for: SearchEndpoints.searchPostsV2.nsid)
    #expect(params["sort"] == nil)
  }

  @Test("encodeV2 emits the since/until as ISO timestamps")
  func encodeV2Timestamps() {
    let built = SearchPostsV2Filters.build(
      embedded: .init(q: ""), filters: .init(since: "2024-01-01", until: "2024-02-01"))
    let params = SearchFetchers.encodeV2(built, query: "cats", sort: nil, limit: 25, cursor: nil)
    var dict: [String: String] = [:]
    for (name, value) in params { if let value { dict[name] = value } }
    #expect(dict["since"] == "2024-01-01T00:00:00Z")
    #expect(dict["until"] == "2024-02-01T00:00:00Z")
  }

  @Test("encodeV2 emits each param name exactly once")
  func encodeV2NoDuplicateParams() {
    let built = SearchPostsV2Filters.build(
      embedded: .init(q: "", author: "alice", since: "2024-01-01"),
      filters: .init(until: "2024-02-01", media: "true"))
    let params = SearchFetchers.encodeV2(built, query: "cats", sort: .top, limit: 25, cursor: "c")
    let names = params.map(\.0)
    #expect(Set(names).count == names.count, "duplicate param name in \(names)")
  }

  @Test("starter-pack search sends q, limit and cursor")
  func starterPackSearch() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.starterPackSearch.nsid,
      App.Bsky.GraphSearchStarterPacksV2_Output(starterPacks: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.searchStarterPacks(query: "art", cursor: "c2")
    let params = await client.lastParams(for: SearchEndpoints.starterPackSearch.nsid)
    #expect(params["q"] == "art")
    #expect(params["limit"] == "25")
    #expect(params["cursor"] == "c2")
  }

  @Test("trends sends the fetch limit and the topics header")
  func trends() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.trends.nsid, App.Bsky.UnspeccedGetTrends_Output(trends: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.getTrends(
      headers: SearchRequestHeaders(topics: "art", acceptLanguage: "en"))
    let params = await client.lastParams(for: SearchEndpoints.trends.nsid)
    #expect(params["limit"] == "20")
    let calls = await client.calls(for: SearchEndpoints.trends.nsid)
    #expect(calls.first?.headers["X-Bsky-Topics"] == "art")
    #expect(calls.first?.headers["Accept-Language"] == "en")
  }

  @Test("trending topics sends limit and viewer")
  func trendingTopics() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.trendingTopics.nsid,
      App.Bsky.UnspeccedGetTrendingTopics_Output(suggested: [], topics: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.getTrendingTopics(limit: 5, viewer: "did:plc:me")
    let params = await client.lastParams(for: SearchEndpoints.trendingTopics.nsid)
    #expect(params["limit"] == "5")
    #expect(params["viewer"] == "did:plc:me")
  }

  @Test("popular feeds sends limit and cursor")
  func popularFeeds() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.popularFeedGenerators.nsid,
      App.Bsky.UnspeccedGetPopularFeedGenerators_Output(cursor: "c3", feeds: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.getPopularFeedGenerators(cursor: "c3")
    let params = await client.lastParams(for: SearchEndpoints.popularFeedGenerators.nsid)
    #expect(params["limit"] == "10")
    #expect(params["cursor"] == "c3")
  }

  @Test("suggested users for explore sends category and limit")
  func suggestedUsers() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.suggestedUsersForExplore.nsid,
      App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(actors: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.getSuggestedUsersForExplore(category: "art", limit: 10)
    let params = await client.lastParams(for: SearchEndpoints.suggestedUsersForExplore.nsid)
    #expect(params["category"] == "art")
    #expect(params["limit"] == "10")
  }

  @Test("suggested users for explore omits category when nil")
  func suggestedUsersNoCategory() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.suggestedUsersForExplore.nsid,
      App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(actors: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.getSuggestedUsersForExplore()
    let params = await client.lastParams(for: SearchEndpoints.suggestedUsersForExplore.nsid)
    #expect(params["category"] == nil)
  }

  @Test("suggested feeds sends the 15 default limit")
  func suggestedFeeds() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.suggestedFeeds.nsid, App.Bsky.UnspeccedGetSuggestedFeeds_Output(feeds: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.getSuggestedFeeds()
    let params = await client.lastParams(for: SearchEndpoints.suggestedFeeds.nsid)
    #expect(params["limit"] == "15")
  }

  @Test("suggested starter packs sends no params")
  func suggestedStarterPacks() async throws {
    let client = FakeSearchClient()
    try await client.enqueue(
      SearchEndpoints.suggestedStarterPacks.nsid,
      App.Bsky.UnspeccedGetSuggestedStarterPacks_Output(starterPacks: []))
    let fetchers = SearchFetchers(client: client)
    _ = try await fetchers.getSuggestedStarterPacks()
    let params = await client.lastParams(for: SearchEndpoints.suggestedStarterPacks.nsid)
    #expect(params.isEmpty)
  }
}
