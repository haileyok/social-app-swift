import Foundation
import Lexicons
import QueryStore

/// Typed fetchers for the search-family endpoints.
///
/// Each method encodes the exact parameter set the RN hook sends and goes
/// through ``SearchXRPCCalling``, so the whole feature is drivable by a fake
/// client in tests. Empty/`nil` params are omitted from the wire, matching the
/// RN client's parameter serialization.
///
/// One deliberate divergence from the RN call sites: those merge the returned
/// `recIdStr` into the payload as `recId` via a `select`. This package returns
/// the lexicon output unchanged and exposes the recommendation id through
/// ``ExploreRecommendation/recId`` at the assembly layer, so the raw response
/// stays `Codable`-round-trippable for persistence.
public struct SearchFetchers: Sendable {
  private let client: any SearchXRPCCalling

  public init(client: any SearchXRPCCalling) {
    self.client = client
  }

  // MARK: - Actor search

  /// `app.bsky.actor.searchActors`.
  ///
  /// RN: `client.call(searchActors, {q, limit, cursor: pageParam})`.
  public func searchActors(
    query: String, limit: Int = 25, cursor: String? = nil
  ) async throws -> App.Bsky.ActorSearchActors_Output {
    try await client.get(
      SearchEndpoints.actorSearch.nsid,
      params: [("q", query), ("limit", String(limit)), ("cursor", cursor)]
    )
  }

  /// `app.bsky.actor.searchActorsTypeahead`.
  ///
  /// RN: `client.call(searchActorsTypeahead, {q: prefix, limit})`. The RN hook
  /// short-circuits an empty prefix to an empty actor list rather than calling
  /// the network; ``ActorAutocomplete`` reproduces that before reaching here.
  public func searchActorsTypeahead(
    prefix: String, limit: Int = 8
  ) async throws -> App.Bsky.ActorSearchActorsTypeahead_Output {
    try await client.get(
      SearchEndpoints.actorTypeahead.nsid,
      params: [("q", prefix), ("limit", String(limit))]
    )
  }

  // MARK: - Post search

  /// `app.bsky.feed.searchPostsV2`.
  ///
  /// RN: merges the built v2 filters with `query`, `limit: 25`, `sort` (with
  /// `latest -> recent`) and `allTime: true`, plus `cursor: pageParam`.
  public func searchPostsV2(
    query: String,
    sort: SearchQueryKeys.SearchPostsSort? = nil,
    filters: SearchFilters? = nil,
    limit: Int = 25,
    cursor: String? = nil
  ) async throws -> App.Bsky.FeedSearchPostsV2_Output {
    let extracted = SearchQueryParams.extract(query)
    let built = SearchPostsV2Filters.build(embedded: extracted, filters: filters)
    let finalQuery = SearchQueryParams.appendFromMe(extracted.q, fromMe: filters?.from == "me")
    return try await client.get(
      SearchEndpoints.searchPostsV2.nsid,
      params: Self.encodeV2(built, query: finalQuery, sort: sort, limit: limit, cursor: cursor)
    )
  }

  /// Builds the ordered param list for `searchPostsV2`.
  ///
  /// Extracted for testability: the param table tests assert this encoding
  /// directly, without going through the client. Every filter field is emitted
  /// exactly once, in ``SearchPostsV2FilterField/allCases`` order, followed by
  /// the caller-owned `query`/`limit`/`sort`/`cursor`.
  public static func encodeV2(
    _ filters: SearchPostsV2Filters,
    query: String,
    sort: SearchQueryKeys.SearchPostsSort?,
    limit: Int,
    cursor: String?
  ) -> [(String, String?)] {
    var params: [(String, String?)] = [("allTime", "true")]
    for field in filters.fields {
      guard let value = filters[field] else { continue }
      switch value {
      case .list(let values):
        // The RN client sends array params as repeated query items; a
        // comma-joined value is the equivalent single-item encoding.
        params.append((field.rawValue, values.joined(separator: ",")))
      case .flag(let flag):
        params.append((field.rawValue, flag ? "true" : "false"))
      case .scalar(let scalar):
        params.append((field.rawValue, scalar))
      }
    }
    params.append(("limit", String(limit)))
    params.append(("query", query))
    params.append(("sort", sort?.wireValue))
    params.append(("cursor", cursor))
    return params
  }

  // MARK: - Starter packs

  /// `app.bsky.graph.searchStarterPacksV2`.
  ///
  /// RN: `client.call(searchStarterPacksV2, {q, limit, cursor: pageParam})`.
  public func searchStarterPacks(
    query: String, limit: Int = 25, cursor: String? = nil
  ) async throws -> App.Bsky.GraphSearchStarterPacksV2_Output {
    try await client.get(
      SearchEndpoints.starterPackSearch.nsid,
      params: [("q", query), ("limit", String(limit)), ("cursor", cursor)]
    )
  }

  // MARK: - Trending

  /// `app.bsky.unspecced.getTrends`.
  ///
  /// RN sends the fetch limit (default 20) plus the topics header.
  public func getTrends(
    fetchLimit: Int? = SearchEndpoints.trends.defaultLimit,
    headers: SearchRequestHeaders = SearchRequestHeaders()
  ) async throws -> App.Bsky.UnspeccedGetTrends_Output {
    try await client.get(
      SearchEndpoints.trends.nsid,
      params: [("limit", fetchLimit.map(String.init))],
      headers: headers.dictionary
    )
  }

  /// `app.bsky.unspecced.getTrendingTopics`.
  public func getTrendingTopics(
    limit: Int = SearchEndpoints.trendingTopics.defaultLimit ?? 5,
    viewer: String? = nil
  ) async throws -> App.Bsky.UnspeccedGetTrendingTopics_Output {
    try await client.get(
      SearchEndpoints.trendingTopics.nsid,
      params: [("limit", String(limit)), ("viewer", viewer)]
    )
  }

  // MARK: - Explore: popular / suggested

  /// `app.bsky.unspecced.getPopularFeedGenerators`.
  public func getPopularFeedGenerators(
    limit: Int = SearchEndpoints.popularFeedGenerators.defaultLimit ?? 10,
    cursor: String? = nil
  ) async throws -> App.Bsky.UnspeccedGetPopularFeedGenerators_Output {
    try await client.get(
      SearchEndpoints.popularFeedGenerators.nsid,
      params: [("limit", String(limit)), ("cursor", cursor)]
    )
  }

  /// `app.bsky.unspecced.getSuggestedUsersForExplore`.
  public func getSuggestedUsersForExplore(
    category: String? = nil,
    limit: Int = SearchEndpoints.suggestedUsersForExplore.defaultLimit ?? 10,
    headers: SearchRequestHeaders = SearchRequestHeaders()
  ) async throws -> App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output {
    try await client.get(
      SearchEndpoints.suggestedUsersForExplore.nsid,
      params: [("category", category), ("limit", String(limit))],
      headers: headers.dictionary
    )
  }

  /// `app.bsky.unspecced.getSuggestedFeeds`.
  public func getSuggestedFeeds(
    limit: Int = SearchEndpoints.suggestedFeeds.defaultLimit ?? 15,
    headers: SearchRequestHeaders = SearchRequestHeaders()
  ) async throws -> App.Bsky.UnspeccedGetSuggestedFeeds_Output {
    try await client.get(
      SearchEndpoints.suggestedFeeds.nsid,
      params: [("limit", String(limit))],
      headers: headers.dictionary
    )
  }

  /// `app.bsky.unspecced.getSuggestedStarterPacks`.
  ///
  /// RN sends no params - only the topics header drives the response.
  public func getSuggestedStarterPacks(
    headers: SearchRequestHeaders = SearchRequestHeaders()
  ) async throws -> App.Bsky.UnspeccedGetSuggestedStarterPacks_Output {
    try await client.get(
      SearchEndpoints.suggestedStarterPacks.nsid,
      params: [],
      headers: headers.dictionary
    )
  }
}
