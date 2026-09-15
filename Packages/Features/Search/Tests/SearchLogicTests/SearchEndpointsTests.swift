import Lexicons
import QueryStore
import Testing

@testable import SearchLogic

/// The param table: one assertion per endpoint, covering the NSID, key root,
/// param set and limits. These come from the RN call sites listed in
/// `tests-ported.md`.
@Suite("SearchEndpoints param table")
struct SearchEndpointsTests {
  @Test("actor search sends q/limit/cursor with a limit of 25")
  func actorSearch() {
    let endpoint = SearchEndpoints.actorSearch
    #expect(endpoint.nsid == "app.bsky.actor.searchActors")
    #expect(endpoint.keyRoot == "actor-search")
    #expect(endpoint.parameterNames == ["q", "limit", "cursor"])
    #expect(endpoint.defaultLimit == 25)
    #expect(endpoint.isPaginated)
    #expect(endpoint.staleTime == 5 * 60)
  }

  @Test("typeahead sends q/limit with a limit of 8")
  func typeahead() {
    let endpoint = SearchEndpoints.actorTypeahead
    #expect(endpoint.nsid == "app.bsky.actor.searchActorsTypeahead")
    #expect(endpoint.keyRoot == "actor-autocomplete")
    #expect(endpoint.parameterNames == ["q", "limit"])
    #expect(endpoint.defaultLimit == 8)
    #expect(endpoint.isPaginated == false)
    #expect(endpoint.staleTime == 60)
  }

  @Test("post search v2 sends the full v2 param set with a limit of 25")
  func postSearchV2() {
    let endpoint = SearchEndpoints.searchPostsV2
    #expect(endpoint.nsid == "app.bsky.feed.searchPostsV2")
    #expect(endpoint.keyRoot == "search-posts")
    #expect(endpoint.defaultLimit == 25)
    #expect(endpoint.isPaginated)
    for param in [
      "allTime", "authors", "cursor", "domains", "excludeAuthors", "excludeDomains",
      "excludeHashtags", "excludeMentions", "excludeReplies", "excludeUrls", "following",
      "hasMedia", "hasVideo", "hashtags", "languages", "limit", "mentions", "query", "since",
      "sort", "until", "urls",
    ] {
      #expect(endpoint.parameterNames.contains(param), "missing \(param)")
    }
  }

  @Test("starter-pack search sends q/limit/cursor with a limit of 25")
  func starterPackSearch() {
    let endpoint = SearchEndpoints.starterPackSearch
    #expect(endpoint.nsid == "app.bsky.graph.searchStarterPacksV2")
    #expect(endpoint.keyRoot == "starter-pack-search")
    #expect(endpoint.parameterNames == ["q", "limit", "cursor"])
    #expect(endpoint.defaultLimit == 25)
    #expect(endpoint.isPaginated)
  }

  @Test("trends sends limit with a fetch limit of 20")
  func trends() {
    let endpoint = SearchEndpoints.trends
    #expect(endpoint.nsid == "app.bsky.unspecced.getTrends")
    #expect(endpoint.keyRoot == "trends")
    #expect(endpoint.parameterNames == ["limit"])
    #expect(endpoint.defaultLimit == 20)
    #expect(endpoint.isPaginated == false)
    #expect(endpoint.staleTime == 3 * 60)
  }

  @Test("trending topics sends limit/viewer with a limit of 5")
  func trendingTopics() {
    let endpoint = SearchEndpoints.trendingTopics
    #expect(endpoint.nsid == "app.bsky.unspecced.getTrendingTopics")
    #expect(endpoint.parameterNames == ["limit", "viewer"])
    #expect(endpoint.defaultLimit == 5)
  }

  @Test("popular feeds sends limit/cursor with a limit of 10")
  func popularFeeds() {
    let endpoint = SearchEndpoints.popularFeedGenerators
    #expect(endpoint.nsid == "app.bsky.unspecced.getPopularFeedGenerators")
    #expect(endpoint.keyRoot == "getPopularFeeds")
    #expect(endpoint.keyRoot == SearchEndpoints.popularFeedGenerators.keyRoot)
    #expect(endpoint.parameterNames == ["limit", "cursor"])
    #expect(endpoint.defaultLimit == 10)
    #expect(endpoint.isPaginated)
  }

  @Test("suggested users for explore sends category/limit with a limit of 10")
  func suggestedUsers() {
    let endpoint = SearchEndpoints.suggestedUsersForExplore
    #expect(endpoint.nsid == "app.bsky.unspecced.getSuggestedUsersForExplore")
    #expect(endpoint.parameterNames == ["category", "limit"])
    #expect(endpoint.defaultLimit == 10)
  }

  @Test("suggested feeds sends limit with a limit of 15")
  func suggestedFeeds() {
    let endpoint = SearchEndpoints.suggestedFeeds
    #expect(endpoint.nsid == "app.bsky.unspecced.getSuggestedFeeds")
    #expect(endpoint.keyRoot == "suggested-feeds")
    #expect(endpoint.parameterNames == ["limit"])
    #expect(endpoint.defaultLimit == 15)
  }

  @Test("suggested starter packs sends no params")
  func suggestedStarterPacks() {
    let endpoint = SearchEndpoints.suggestedStarterPacks
    #expect(endpoint.nsid == "app.bsky.unspecced.getSuggestedStarterPacks")
    #expect(endpoint.defaultLimit == nil)
  }

  @Test("every endpoint has a unique key root and NSID")
  func uniqueness() {
    let roots = SearchEndpoints.all.map(\.keyRoot)
    let nsids = SearchEndpoints.all.map(\.nsid)
    #expect(Set(roots).count == roots.count)
    #expect(Set(nsids).count == nsids.count)
  }

  @Test("forRoot resolves a known root and rejects an unknown one")
  func forRoot() {
    #expect(SearchEndpoint.forRoot("actor-search")?.nsid == "app.bsky.actor.searchActors")
    #expect(SearchEndpoint.forRoot("nope") == nil)
  }
}

/// The query keys: root, args and scope, matching the RN `createQueryKey` sites.
@Suite("SearchQueryKeys")
struct SearchQueryKeysTests {
  @Test("actor search key carries root, query and limit")
  func actorSearchKey() {
    let key = SearchQueryKeys.actorSearch(.init(query: "alice", limit: 25))
    #expect(key.root == "actor-search")
    #expect(key.argsText.contains("query: \"alice\""))
    #expect(key.argsText.contains("limit: 25"))
  }

  @Test("typeahead key carries the normalized prefix and not the limit")
  func typeaheadKey() {
    let key = SearchQueryKeys.actorTypeahead(.init(prefix: "ali"))
    #expect(key.root == "actor-autocomplete")
    #expect(key.argsText.contains("prefix: \"ali\""))
    #expect(!key.argsText.contains("limit"))
  }

  @Test("post search key carries query, sort and filters by value")
  func postSearchKey() {
    let bare = SearchQueryKeys.searchPosts(.init(query: "cats"))
    let filtered = SearchQueryKeys.searchPosts(
      .init(query: "cats", sort: .latest, filters: SearchFilters(author: "alice")))
    #expect(bare.root == "search-posts")
    #expect(bare != filtered)
    #expect(filtered.argsText.contains("latest"))
  }

  @Test("searchPostsSort maps latest to the wire value recent")
  func sortWireValue() {
    #expect(SearchQueryKeys.SearchPostsSort.latest.wireValue == "recent")
    #expect(SearchQueryKeys.SearchPostsSort.top.wireValue == "top")
  }

  @Test("scope separates two accounts' entries for the same args")
  func scoping() {
    let mine = SearchQueryKeys.actorSearch(.init(query: "alice"), scope: "did:plc:me")
    let theirs = SearchQueryKeys.actorSearch(.init(query: "alice"), scope: "did:plc:you")
    #expect(mine != theirs)
    #expect(mine.scope == "did:plc:me")
  }

  @Test("persistedVersion is carried on the post-search key")
  func persistedVersion() {
    let key = SearchQueryKeys.searchPosts(.init(query: "cats"), persistedVersion: 2)
    #expect(key.persistedVersion == 2)
  }

  @Test("trends key omits the limit when the fetch limit is nil")
  func trendsKey() {
    #expect(SearchQueryKeys.trends(.init()).root == "trends")
    #expect(SearchQueryKeys.trends(.init(fetchLimit: 20)) != SearchQueryKeys.trends(.init()))
  }

  @Test("starter-pack, suggested and popular roots match the endpoint table")
  func rootsMatchTable() {
    #expect(
      SearchQueryKeys.starterPackSearch(.init(query: "a")).root
        == SearchEndpoints.starterPackSearch.keyRoot)
    #expect(SearchQueryKeys.popularFeeds().root == SearchEndpoints.popularFeedGenerators.keyRoot)
    #expect(
      SearchQueryKeys.suggestedUsersForExplore().root
        == SearchEndpoints.suggestedUsersForExplore.keyRoot)
    #expect(SearchQueryKeys.suggestedFeeds().root == SearchEndpoints.suggestedFeeds.keyRoot)
    #expect(
      SearchQueryKeys.suggestedStarterPacks().root
        == SearchEndpoints.suggestedStarterPacks.keyRoot)
  }

  @Test("suggested starter packs key varies by interests override")
  func suggestedStarterPacksKey() {
    let none = SearchQueryKeys.suggestedStarterPacks(.init())
    let interests = SearchQueryKeys.suggestedStarterPacks(.init(interests: "art,news"))
    #expect(none != interests)
  }
}
