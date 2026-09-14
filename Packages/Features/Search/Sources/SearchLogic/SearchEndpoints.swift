import Foundation
import QueryStore

/// One search-family XRPC operation: its NSID, cache-key root, the query
/// parameter names it sends, and the pagination/staleness policy the RN hooks
/// use.
///
/// The table exists so the endpoint surface is data rather than scattered string
/// literals: a test iterates ``SearchEndpoints/all`` and asserts each operation's
/// param set and limits, and the fetchers read their limits and stale times from
/// the same rows. Every value is copied from the RN hooks listed in the manifest.
public struct SearchEndpoint: Sendable, Equatable {
  /// The XRPC NSID.
  public let nsid: String
  /// The `QueryKey` root. Matches the RN `RQKEY_ROOT` for each hook so a
  /// persisted key from the RN app maps to the same entry name.
  public let keyRoot: String
  /// Query parameter names this operation passes, in wire order.
  public let parameterNames: [String]
  /// Whether the operation is cursor-paginated (uses `useInfiniteQuery` in RN).
  public let isPaginated: Bool
  /// The default `limit` when the caller does not override it.
  public let defaultLimit: Int?
  /// The staleness budget fresh-read hooks use.
  public let staleTime: TimeInterval
}

/// The search surface's endpoint definitions, ported from the RN query hooks.
public enum SearchEndpoints {
  /// `app.bsky.actor.searchActors` - `state/queries/actor-search.ts`.
  ///
  /// Params: `q`, `limit` (default 25), `cursor`. `STALE.MINUTES.FIVE`.
  public static let actorSearch = SearchEndpoint(
    nsid: "app.bsky.actor.searchActors",
    keyRoot: "actor-search",
    parameterNames: ["q", "limit", "cursor"],
    isPaginated: true,
    defaultLimit: 25,
    staleTime: STALE.MINUTES.FIVE
  )

  /// `app.bsky.actor.searchActorsTypeahead` - `state/queries/actor-autocomplete.ts`.
  ///
  /// Params: `q`, `limit` (default 8). Not paginated. `STALE.MINUTES.ONE`.
  public static let actorTypeahead = SearchEndpoint(
    nsid: "app.bsky.actor.searchActorsTypeahead",
    keyRoot: "actor-autocomplete",
    parameterNames: ["q", "limit"],
    isPaginated: false,
    defaultLimit: 8,
    staleTime: STALE.MINUTES.ONE
  )

  /// `app.bsky.feed.searchPostsV2` - `state/queries/search-posts-v2.ts`.
  ///
  /// Params: the v2 filter set plus `query`, `limit` (25), `cursor`, `sort` and
  /// `allTime: true`. Not given a stale time in RN (defaults to the client's).
  public static let searchPostsV2 = SearchEndpoint(
    nsid: "app.bsky.feed.searchPostsV2",
    keyRoot: "search-posts",
    parameterNames: [
      "allTime", "authors", "cursor", "domains", "excludeAuthors", "excludeDomains",
      "excludeHashtags", "excludeMentions", "excludeReplies", "excludeUrls", "following",
      "hasMedia", "hasVideo", "hashtags", "languages", "limit", "mentions", "query", "since",
      "sort", "until", "urls",
    ],
    isPaginated: true,
    defaultLimit: 25,
    staleTime: STALE.MINUTES.FIVE
  )

  /// `app.bsky.feed.searchPosts` - the v1 shape, kept for the legacy param path.
  ///
  /// Params: `q`, `limit`, `cursor`, `sort`, plus v1's singular
  /// `author`/`domain`/`url`/`mentions`/`tag`/`lang`/`since`/`until`.
  public static let searchPostsV1 = SearchEndpoint(
    nsid: "app.bsky.feed.searchPosts",
    keyRoot: "search-posts-v1",
    parameterNames: [
      "author", "cursor", "domain", "lang", "limit", "mentions", "q", "since", "sort", "tag",
      "until", "url",
    ],
    isPaginated: true,
    defaultLimit: 25,
    staleTime: STALE.MINUTES.FIVE
  )

  /// `app.bsky.graph.searchStarterPacksV2` - `state/queries/starter-pack-search.ts`.
  ///
  /// Params: `q`, `limit` (default 25), `cursor`. `STALE.MINUTES.FIVE`.
  public static let starterPackSearch = SearchEndpoint(
    nsid: "app.bsky.graph.searchStarterPacksV2",
    keyRoot: "starter-pack-search",
    parameterNames: ["q", "limit", "cursor"],
    isPaginated: true,
    defaultLimit: 25,
    staleTime: STALE.MINUTES.FIVE
  )

  /// `app.bsky.unspecced.getTrends` - `state/queries/trending/useGetTrendsQuery.ts`.
  ///
  /// Params: `limit` (fetch limit default 20). `STALE.MINUTES.THREE`.
  public static let trends = SearchEndpoint(
    nsid: "app.bsky.unspecced.getTrends",
    keyRoot: "trends",
    parameterNames: ["limit"],
    isPaginated: false,
    defaultLimit: 20,
    staleTime: STALE.MINUTES.THREE
  )

  /// `app.bsky.unspecced.getTrendingTopics`.
  ///
  /// Params: `limit`, `viewer` (the signed-in DID). `STALE.MINUTES.THREE`.
  public static let trendingTopics = SearchEndpoint(
    nsid: "app.bsky.unspecced.getTrendingTopics",
    keyRoot: "trending-topics",
    parameterNames: ["limit", "viewer"],
    isPaginated: false,
    defaultLimit: 5,
    staleTime: STALE.MINUTES.THREE
  )

  /// `app.bsky.unspecced.getPopularFeedGenerators` - `state/queries/feed.ts`.
  ///
  /// Params: `limit` (default 10), `cursor`. Cursor-paginated.
  public static let popularFeedGenerators = SearchEndpoint(
    nsid: "app.bsky.unspecced.getPopularFeedGenerators",
    keyRoot: "getPopularFeeds",
    parameterNames: ["limit", "cursor"],
    isPaginated: true,
    defaultLimit: 10,
    staleTime: STALE.MINUTES.THREE
  )

  /// `app.bsky.unspecced.getSuggestedUsersForExplore`
  /// - `state/queries/trending/useGetSuggestedUsersForExploreQuery.ts`.
  ///
  /// Params: `category`, `limit` (default 10). `STALE.MINUTES.THREE`.
  public static let suggestedUsersForExplore = SearchEndpoint(
    nsid: "app.bsky.unspecced.getSuggestedUsersForExplore",
    keyRoot: "unspecced-suggested-users-for-explore",
    parameterNames: ["category", "limit"],
    isPaginated: false,
    defaultLimit: 10,
    staleTime: STALE.MINUTES.THREE
  )

  /// `app.bsky.unspecced.getSuggestedFeeds`
  /// - `state/queries/trending/useGetSuggestedFeedsQuery.ts`.
  ///
  /// Params: `limit` (default 15). `STALE.MINUTES.THREE`.
  public static let suggestedFeeds = SearchEndpoint(
    nsid: "app.bsky.unspecced.getSuggestedFeeds",
    keyRoot: "suggested-feeds",
    parameterNames: ["limit"],
    isPaginated: false,
    defaultLimit: 15,
    staleTime: STALE.MINUTES.THREE
  )

  /// `app.bsky.unspecced.getSuggestedStarterPacks`
  /// - `state/queries/useSuggestedStarterPacksQuery.ts`.
  ///
  /// Params: none sent (`limit` is available but RN sends `{}`).
  /// `STALE.MINUTES.THREE`.
  public static let suggestedStarterPacks = SearchEndpoint(
    nsid: "app.bsky.unspecced.getSuggestedStarterPacks",
    keyRoot: "suggested-starter-packs",
    parameterNames: ["limit"],
    isPaginated: false,
    defaultLimit: nil,
    staleTime: STALE.MINUTES.THREE
  )

  /// Every endpoint this feature knows about.
  public static let all: [SearchEndpoint] = [
    actorSearch,
    actorTypeahead,
    searchPostsV2,
    searchPostsV1,
    starterPackSearch,
    trends,
    trendingTopics,
    popularFeedGenerators,
    suggestedUsersForExplore,
    suggestedFeeds,
    suggestedStarterPacks,
  ]
}

extension SearchEndpoint {
  /// The endpoint whose `keyRoot` matches, or `nil`.
  public static func forRoot(_ root: String) -> SearchEndpoint? {
    SearchEndpoints.all.first { $0.keyRoot == root }
  }
}
