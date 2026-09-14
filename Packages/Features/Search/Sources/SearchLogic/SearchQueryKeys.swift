import Foundation
import QueryStore

/// Argument payloads and key builders for every search query.
///
/// Ported from the RN `RQKEY`/`createQueryKey` call sites. Two details matter:
/// the argument payloads are `Hashable` structs (so `QueryKey` identity is
/// description-based and survives a restart), and the roots match the RN
/// `RQKEY_ROOT` constants so a persisted entry keeps its name across the port.
public enum SearchQueryKeys {
  // MARK: - Actor search

  /// Args for `app.bsky.actor.searchActors`. RN: `RQKEY(query, limit)`.
  public struct ActorSearchArgs: QueryArgs {
    public let query: String
    public let limit: Int
    public init(query: String, limit: Int = 25) {
      self.query = query
      self.limit = limit
    }
  }

  /// `actor-search(query:limit:)`.
  public static func actorSearch(_ args: ActorSearchArgs, scope: String? = nil) -> QueryKey {
    QueryKey(SearchEndpoints.actorSearch.keyRoot, args, options: QueryOptions(scope: scope))
  }

  /// Args for the typeahead. RN: `RQKEY(prefix)` - limit is not part of the key.
  public struct ActorTypeaheadArgs: QueryArgs {
    public let prefix: String
    public init(prefix: String) { self.prefix = prefix }
  }

  /// `actor-autocomplete(prefix:)`.
  ///
  /// The RN key holds the normalized prefix, which is what makes the "keep
  /// previous data" behaviour cache a hit while the user types through a
  /// handle. Normalization happens in ``ActorAutocomplete/normalizePrefix(_:)``
  /// before the key is built.
  public static func actorTypeahead(_ args: ActorTypeaheadArgs, scope: String? = nil) -> QueryKey {
    QueryKey(SearchEndpoints.actorTypeahead.keyRoot, args, options: QueryOptions(scope: scope))
  }

  // MARK: - Post search

  /// Args for `app.bsky.feed.searchPostsV2`.
  ///
  /// RN keys on `[root, query, sort, filters]`; `filters` participates by value
  /// so changing a filter yields a distinct cache entry. The embedded-operator
  /// extraction is applied at fetch time, not in the key, matching RN (the key
  /// holds the raw query string the user typed).
  public struct SearchPostsArgs: QueryArgs {
    public let query: String
    public let sort: SearchPostsSort?
    public let filters: SearchFilters?
    public let limit: Int

    public init(
      query: String,
      sort: SearchPostsSort? = nil,
      filters: SearchFilters? = nil,
      limit: Int = 25
    ) {
      self.query = query
      self.sort = sort
      self.filters = filters
      self.limit = limit
    }
  }

  /// The post-search sort order.
  ///
  /// v2 calls the recency sort `recent`; the rest of the app (and the v1
  /// endpoint) still uses the `latest` label, so ``wireValue`` translates.
  public enum SearchPostsSort: String, Hashable, Sendable, CaseIterable {
    case top
    case latest

    /// The value sent to `searchPostsV2`.
    public var wireValue: String {
      self == .latest ? "recent" : rawValue
    }
  }

  /// `search-posts(query:sort:filters:limit:)`.
  public static func searchPosts(
    _ args: SearchPostsArgs, scope: String? = nil, persistedVersion: Int? = nil
  ) -> QueryKey {
    QueryKey(
      SearchEndpoints.searchPostsV2.keyRoot, args,
      options: QueryOptions(scope: scope, persistedVersion: persistedVersion))
  }

  // MARK: - Starter-pack search

  /// Args for `app.bsky.graph.searchStarterPacksV2`. RN: `RQKEY(query, limit)`.
  public struct StarterPackSearchArgs: QueryArgs {
    public let query: String
    public let limit: Int
    public init(query: String, limit: Int = 25) {
      self.query = query
      self.limit = limit
    }
  }

  /// `starter-pack-search(query:limit:)`.
  public static func starterPackSearch(
    _ args: StarterPackSearchArgs, scope: String? = nil
  ) -> QueryKey {
    QueryKey(SearchEndpoints.starterPackSearch.keyRoot, args, options: QueryOptions(scope: scope))
  }

  // MARK: - Trends

  /// Args for `app.bsky.unspecced.getTrends`. RN:
  /// `createGetTrendsQueryKey(fetchLimit)` - `['trends']` when undefined.
  public struct TrendsArgs: QueryArgs {
    /// The fetch limit, not the display limit. `nil` reproduces RN's bare
    /// `['trends']` key.
    public let fetchLimit: Int?
    public init(fetchLimit: Int? = nil) { self.fetchLimit = fetchLimit }
  }

  /// `trends(fetchLimit:)`.
  public static func trends(_ args: TrendsArgs = .init()) -> QueryKey {
    QueryKey(SearchEndpoints.trends.keyRoot, args)
  }

  /// Args for `app.bsky.unspecced.getTrendingTopics`.
  public struct TrendingTopicsArgs: QueryArgs {
    public let limit: Int
    /// The viewer DID; `nil` for the signed-out variant.
    public let viewer: String?
    public init(limit: Int = 5, viewer: String? = nil) {
      self.limit = limit
      self.viewer = viewer
    }
  }

  /// `trending-topics(limit:viewer:)`.
  public static func trendingTopics(
    _ args: TrendingTopicsArgs = .init(), scope: String? = nil
  ) -> QueryKey {
    QueryKey(SearchEndpoints.trendingTopics.keyRoot, args, options: QueryOptions(scope: scope))
  }

  // MARK: - Explore: popular / suggested

  /// Args for `app.bsky.unspecced.getPopularFeedGenerators`.
  /// RN: `createGetPopularFeedsQueryKey(options)` -> `['getPopularFeeds', limit]`.
  public struct PopularFeedsArgs: QueryArgs {
    public let limit: Int
    public init(limit: Int = 10) { self.limit = limit }
  }

  /// `getPopularFeeds(limit:)`.
  public static func popularFeeds(
    _ args: PopularFeedsArgs = .init(), scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      SearchEndpoints.popularFeedGenerators.keyRoot, args, options: QueryOptions(scope: scope))
  }

  /// Args for `app.bsky.unspecced.getSuggestedUsersForExplore`.
  public struct SuggestedUsersForExploreArgs: QueryArgs {
    public let category: String?
    public let limit: Int
    public init(category: String? = nil, limit: Int = 10) {
      self.category = category
      self.limit = limit
    }
  }

  /// `unspecced-suggested-users-for-explore(category:limit:)`.
  public static func suggestedUsersForExplore(
    _ args: SuggestedUsersForExploreArgs = .init(), scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      SearchEndpoints.suggestedUsersForExplore.keyRoot, args,
      options: QueryOptions(scope: scope))
  }

  /// Args for `app.bsky.unspecced.getSuggestedFeeds`. RN key is the bare
  /// `['suggested-feeds']` - the limit is fixed at the hook's default.
  public struct SuggestedFeedsArgs: QueryArgs {
    public init() {}
  }

  /// `suggested-feeds`.
  public static func suggestedFeeds(
    _ args: SuggestedFeedsArgs = .init(), scope: String? = nil
  ) -> QueryKey {
    QueryKey(SearchEndpoints.suggestedFeeds.keyRoot, args, options: QueryOptions(scope: scope))
  }

  /// Args for `app.bsky.unspecced.getSuggestedStarterPacks`.
  ///
  /// RN keys on the interests override (`interests?.join(',')`), because the
  /// topics header changes the response.
  public struct SuggestedStarterPacksArgs: QueryArgs {
    public let interests: String?
    public init(interests: String? = nil) { self.interests = interests }
  }

  /// `suggested-starter-packs(interests:)`.
  public static func suggestedStarterPacks(
    _ args: SuggestedStarterPacksArgs = .init(), scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      SearchEndpoints.suggestedStarterPacks.keyRoot, args, options: QueryOptions(scope: scope))
  }
}
