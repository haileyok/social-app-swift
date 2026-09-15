import Foundation
import Lexicons
import QueryStore

/// The store-facing query handles for the search surface.
///
/// Thin by design: each method pairs a key from ``SearchQueryKeys`` with the
/// matching call on ``SearchFetchers`` and the stale time from
/// ``SearchEndpoints``. The cursor walk, de-dupe-on-merge policy and bookkeeping
/// live in ``InfiniteQuery``/``QueryStore``, so nothing about pagination is
/// re-implemented here - the same split the RN hooks have with TanStack Query.
public struct SearchQueries: Sendable {
  /// The cache the queries read and write.
  public let store: QueryStore
  /// The fetchers issuing the XRPC calls.
  public let fetchers: SearchFetchers

  public init(store: QueryStore, fetchers: SearchFetchers) {
    self.store = store
    self.fetchers = fetchers
  }

  /// Convenience: a store and a fetcher over one client.
  public init(client: any SearchXRPCCalling, store: QueryStore = QueryStore()) {
    self.store = store
    self.fetchers = SearchFetchers(client: client)
  }

  // MARK: - Actor search

  /// The cursor-paginated actor search for `query`.
  ///
  /// Identity is the actor DID, matching the RN `select` which filters
  /// duplicate DIDs across pages.
  public func actorSearch(
    query: String, limit: Int = 25, scope: String? = nil
  ) -> InfiniteQuery<App.Bsky.ActorDefs_ProfileView> {
    InfiniteQuery(
      store: store,
      key: SearchQueryKeys.actorSearch(.init(query: query, limit: limit), scope: scope),
      identity: { $0.did.rawValue },
      page: { [fetchers] cursor in
        let page = try await fetchers.searchActors(query: query, limit: limit, cursor: cursor)
        return QueryPage(items: page.actors, cursor: page.cursor)
      }
    )
  }

  /// Runs the actor search to completion for `query` (first page only unless
  /// `loadAllPages` is set).
  @discardableResult
  public func loadActorSearch(
    query: String, limit: Int = 25, scope: String? = nil, force: Bool = false
  ) async throws -> [App.Bsky.ActorDefs_ProfileView] {
    let query = actorSearch(query: query, limit: limit, scope: scope)
    try await query.loadFirstPage(staleTime: SearchEndpoints.actorSearch.staleTime, force: force)
    return await query.items()
  }

  // MARK: - Typeahead

  /// The typeahead query for a normalized prefix.
  ///
  /// Not paginated, and the RN hook returns an empty list for an empty prefix
  /// without a network round-trip; that guard lives in ``ActorAutocomplete``.
  public func actorTypeahead(
    prefix: String, limit: Int = 8, scope: String? = nil
  ) async throws -> [App.Bsky.ActorDefs_ProfileViewBasic] {
    let key = SearchQueryKeys.actorTypeahead(.init(prefix: prefix), scope: scope)
    return try await store.fetch(
      key, staleTime: SearchEndpoints.actorTypeahead.staleTime
    ) { [fetchers] in
      try await fetchers.searchActorsTypeahead(prefix: prefix, limit: limit).actors
    }
  }

  // MARK: - Post search

  /// The cursor-paginated post search.
  ///
  /// Identity is the post URI, matching the RN select's de-dupe across pages.
  public func searchPosts(
    query: String,
    sort: SearchQueryKeys.SearchPostsSort? = nil,
    filters: SearchFilters? = nil,
    limit: Int = 25,
    scope: String? = nil
  ) -> InfiniteQuery<App.Bsky.FeedDefs_PostView> {
    InfiniteQuery(
      store: store,
      key: SearchQueryKeys.searchPosts(
        .init(query: query, sort: sort, filters: filters, limit: limit), scope: scope),
      identity: { $0.uri.rawValue },
      page: { [fetchers] cursor in
        let page = try await fetchers.searchPostsV2(
          query: query, sort: sort, filters: filters, limit: limit, cursor: cursor)
        return QueryPage(items: page.posts, cursor: page.cursor)
      }
    )
  }

  /// Loads the first page of post search results.
  @discardableResult
  public func loadSearchPosts(
    query: String,
    sort: SearchQueryKeys.SearchPostsSort? = nil,
    filters: SearchFilters? = nil,
    limit: Int = 25,
    scope: String? = nil,
    force: Bool = false
  ) async throws -> [App.Bsky.FeedDefs_PostView] {
    let query = searchPosts(
      query: query, sort: sort, filters: filters, limit: limit, scope: scope)
    try await query.loadFirstPage(staleTime: SearchEndpoints.searchPostsV2.staleTime, force: force)
    return await query.items()
  }

  // MARK: - Starter packs

  /// The cursor-paginated starter-pack search. Identity is the pack URI.
  public func starterPackSearch(
    query: String, limit: Int = 25, scope: String? = nil
  ) -> InfiniteQuery<App.Bsky.GraphDefs_StarterPackView> {
    InfiniteQuery(
      store: store,
      key: SearchQueryKeys.starterPackSearch(.init(query: query, limit: limit), scope: scope),
      identity: { $0.uri.rawValue },
      page: { [fetchers] cursor in
        let page = try await fetchers.searchStarterPacks(query: query, limit: limit, cursor: cursor)
        return QueryPage(items: page.starterPacks, cursor: page.cursor)
      }
    )
  }

  /// Loads the first page of starter-pack results.
  @discardableResult
  public func loadStarterPackSearch(
    query: String, limit: Int = 25, scope: String? = nil, force: Bool = false
  ) async throws -> [App.Bsky.GraphDefs_StarterPackView] {
    let query = starterPackSearch(query: query, limit: limit, scope: scope)
    try await query.loadFirstPage(
      staleTime: SearchEndpoints.starterPackSearch.staleTime, force: force)
    return await query.items()
  }

  // MARK: - Trending

  /// `getTrends`, returning the raw output.
  ///
  /// The muted-word filter and display-limit slice that RN applies in `select`
  /// live in ``Trending/applyMutedWordFilter(_:mutedWords:limit:)`` so they are
  /// testable without the store.
  public func getTrends(
    fetchLimit: Int? = SearchEndpoints.trends.defaultLimit,
    headers: SearchRequestHeaders = SearchRequestHeaders()
  ) async throws -> App.Bsky.UnspeccedGetTrends_Output {
    let key = SearchQueryKeys.trends(.init(fetchLimit: fetchLimit))
    return try await store.fetch(key, staleTime: SearchEndpoints.trends.staleTime) { [fetchers] in
      try await fetchers.getTrends(fetchLimit: fetchLimit, headers: headers)
    }
  }

  /// `getTrendingTopics`, returning the raw output.
  public func getTrendingTopics(
    limit: Int = SearchEndpoints.trendingTopics.defaultLimit ?? 5,
    viewer: String? = nil,
    scope: String? = nil
  ) async throws -> App.Bsky.UnspeccedGetTrendingTopics_Output {
    let key = SearchQueryKeys.trendingTopics(.init(limit: limit, viewer: viewer), scope: scope)
    return try await store.fetch(
      key, staleTime: SearchEndpoints.trendingTopics.staleTime,
      fetcher: { [fetchers] in
        try await fetchers.getTrendingTopics(limit: limit, viewer: viewer)
      }
    )
  }

  // MARK: - Explore: popular / suggested

  /// The cursor-paginated popular-feed list. Identity is the feed URI.
  public func popularFeeds(
    limit: Int = SearchEndpoints.popularFeedGenerators.defaultLimit ?? 10,
    scope: String? = nil
  ) -> InfiniteQuery<App.Bsky.FeedDefs_GeneratorView> {
    InfiniteQuery(
      store: store,
      key: SearchQueryKeys.popularFeeds(.init(limit: limit), scope: scope),
      identity: { $0.uri.rawValue },
      page: { [fetchers] cursor in
        let page = try await fetchers.getPopularFeedGenerators(limit: limit, cursor: cursor)
        return QueryPage(items: page.feeds, cursor: page.cursor)
      }
    )
  }

  /// `getSuggestedUsersForExplore`.
  public func suggestedUsersForExplore(
    category: String? = nil,
    limit: Int = SearchEndpoints.suggestedUsersForExplore.defaultLimit ?? 10,
    headers: SearchRequestHeaders = SearchRequestHeaders(),
    scope: String? = nil
  ) async throws -> App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output {
    let key = SearchQueryKeys.suggestedUsersForExplore(
      .init(category: category, limit: limit), scope: scope)
    return try await store.fetch(
      key, staleTime: SearchEndpoints.suggestedUsersForExplore.staleTime
    ) { [fetchers] in
      try await fetchers.getSuggestedUsersForExplore(
        category: category, limit: limit, headers: headers)
    }
  }

  /// `getSuggestedFeeds`.
  public func suggestedFeeds(
    limit: Int = SearchEndpoints.suggestedFeeds.defaultLimit ?? 15,
    headers: SearchRequestHeaders = SearchRequestHeaders(),
    scope: String? = nil
  ) async throws -> App.Bsky.UnspeccedGetSuggestedFeeds_Output {
    let key = SearchQueryKeys.suggestedFeeds(.init(), scope: scope)
    return try await store.fetch(
      key, staleTime: SearchEndpoints.suggestedFeeds.staleTime,
      fetcher: { [fetchers] in
        try await fetchers.getSuggestedFeeds(limit: limit, headers: headers)
      }
    )
  }

  /// `getSuggestedStarterPacks`.
  public func suggestedStarterPacks(
    interests: String? = nil,
    headers: SearchRequestHeaders = SearchRequestHeaders(),
    scope: String? = nil
  ) async throws -> App.Bsky.UnspeccedGetSuggestedStarterPacks_Output {
    let key = SearchQueryKeys.suggestedStarterPacks(.init(interests: interests), scope: scope)
    return try await store.fetch(
      key, staleTime: SearchEndpoints.suggestedStarterPacks.staleTime
    ) { [fetchers] in
      try await fetchers.getSuggestedStarterPacks(headers: headers)
    }
  }
}
