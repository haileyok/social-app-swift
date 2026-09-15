import Foundation
import Lexicons
import SwiftAtproto

/// The XRPC surface the home feed needs, behind a protocol so tests can record
/// and script exact calls.
///
/// Ported from the RN `FeedAPI` implementations in `src/lib/api/feed/*.ts` plus
/// the feed-metadata reads in `src/state/queries/feed.ts`. The live
/// implementation (``LiveFeedXrpc``) runs over `ATProtoClient.XrpcClient`, so
/// proxy routing, labelers and auth headers are emitted by the client exactly as
/// they are for every other feature.
public protocol FeedXrpc: Sendable {
  /// `app.bsky.feed.getTimeline`. Port of `FollowingFeedAPI.fetch`.
  func getTimeline(cursor: String?, limit: Int) async throws -> FeedTimelinePage

  /// `app.bsky.feed.getFeed` with the custom-feed request headers.
  /// Port of `CustomFeedAPI.fetch`.
  func getFeed(
    feed: String, cursor: String?, limit: Int, headers: FeedRequestHeaders
  ) async throws -> FeedPageOutput

  /// `app.bsky.feed.getFeedSkeleton` (feed-generator service read).
  func getFeedSkeleton(
    feed: String, cursor: String?, limit: Int
  ) async throws -> FeedSkeletonOutput

  /// `app.bsky.feed.getListFeed`. Port of `ListFeedAPI.fetch`.
  func getListFeed(
    list: String, cursor: String?, limit: Int
  ) async throws -> FeedPageOutput

  /// `app.bsky.graph.getList`, used to resolve a saved list's view.
  /// Port of the per-list read in `usePinnedFeedsInfos`.
  func getList(list: String) async throws -> ListViewInfo

  /// `app.bsky.feed.getPosts`, used to hydrate a skeleton into post views.
  func getPosts(uris: [String]) async throws -> [App.Bsky.FeedDefs_PostView]

  /// `app.bsky.feed.getFeedGenerator`. Port of `useFeedInfo`.
  func getFeedGenerator(feed: String) async throws -> App.Bsky.FeedDefs_GeneratorView

  /// `app.bsky.feed.getFeedGenerators`. Port of the batch read in
  /// `usePinnedFeedsInfos` / `useSavedFeeds`.
  func getFeedGenerators(feeds: [String]) async throws -> [App.Bsky.FeedDefs_GeneratorView]

  /// `app.bsky.feed.getActorFeeds`. Port of `profile-feedgens.ts`.
  func getActorFeeds(
    actor: String, cursor: String?, limit: Int
  ) async throws -> ActorFeedsPage

  /// `app.bsky.unspecced.getConfig`, the feed gating/config read.
  func getConfig() async throws -> App.Bsky.UnspeccedGetConfig_Output
}

/// The per-request headers a feed read carries.
///
/// RN builds these in `src/lib/api/feed/custom.ts` and
/// `src/lib/api/feed/utils.ts`: `Accept-Language` from the content-language
/// prefs, and `X-Bsky-Topics` (user interests) but only for Bluesky-owned feeds.
public struct FeedRequestHeaders: Sendable, Equatable {
  /// `Accept-Language`, e.g. `en,de`. RN sends the joined content languages.
  public var acceptLanguage: String?
  /// `X-Bsky-Topics`, the aggregated user interests.
  public var bskyTopics: String?

  public init(acceptLanguage: String? = nil, bskyTopics: String? = nil) {
    self.acceptLanguage = acceptLanguage
    self.bskyTopics = bskyTopics
  }

  /// The header map to merge onto the request.
  public var asHeaders: [String: String] {
    var headers: [String: String] = [:]
    if let acceptLanguage { headers["Accept-Language"] = acceptLanguage }
    if let bskyTopics { headers["X-Bsky-Topics"] = bskyTopics }
    return headers
  }
}

/// A page of the following timeline.
public struct FeedTimelinePage: Sendable {
  public var cursor: String?
  public var feed: [App.Bsky.FeedDefs_FeedViewPost]

  public init(cursor: String? = nil, feed: [App.Bsky.FeedDefs_FeedViewPost] = []) {
    self.cursor = cursor
    self.feed = feed
  }
}

/// A page of a hydrated custom feed (`getFeed`).
public struct FeedPageOutput: Sendable {
  public var cursor: String?
  public var feed: [App.Bsky.FeedDefs_FeedViewPost]

  public init(cursor: String? = nil, feed: [App.Bsky.FeedDefs_FeedViewPost] = []) {
    self.cursor = cursor
    self.feed = feed
  }
}

/// A page of a feed skeleton (`getFeedSkeleton`).
public struct FeedSkeletonOutput: Sendable {
  public var cursor: String?
  public var feed: [App.Bsky.FeedDefs_SkeletonFeedPost]
  public var reqId: String?

  public init(
    cursor: String? = nil,
    feed: [App.Bsky.FeedDefs_SkeletonFeedPost] = [],
    reqId: String? = nil
  ) {
    self.cursor = cursor
    self.feed = feed
    self.reqId = reqId
  }
}

/// A page of a user's feed generators.
public struct ActorFeedsPage: Sendable {
  public var cursor: String?
  public var feeds: [App.Bsky.FeedDefs_GeneratorView]

  public init(cursor: String? = nil, feeds: [App.Bsky.FeedDefs_GeneratorView] = []) {
    self.cursor = cursor
    self.feeds = feeds
  }
}

/// The subset of a `graph.defs#listView` the pinned-feed model needs.
public struct ListViewInfo: Sendable {
  /// The list URI.
  public var uri: String
  /// The list's name, RN's `view.name`.
  public var name: String
  /// The creator's handle.
  public var creatorHandle: String
  /// The creator's DID.
  public var creatorDid: String

  public init(uri: String, name: String, creatorHandle: String, creatorDid: String) {
    self.uri = uri
    self.name = name
    self.creatorHandle = creatorHandle
    self.creatorDid = creatorDid
  }
}

/// Bluesky-owned feed-generator owner DIDs, from `BSKY_FEED_OWNER_DIDS`.
///
/// `isBlueskyOwnedFeed` gates the `X-Bsky-Topics` header: only feeds owned by
/// these accounts receive the user-interests header.
public enum BlueskyFeedOwners {
  public static let dids: Set<String> = [
    "did:plc:z72i7hdynmk6r22z27h6tvur",
    "did:web:api.bsky.app",
    "did:web:bsky.app",
  ]

  /// True when the feed URI's authority is a Bluesky-owned account.
  public static func owns(feedURI: String) -> Bool {
    guard let host = host(of: feedURI) else { return false }
    return dids.contains(host)
  }

  /// The authority segment of an `at://` URI.
  static func host(of uri: String) -> String? {
    guard uri.hasPrefix("at://") else { return nil }
    let rest = uri.dropFirst("at://".count)
    guard let slash = rest.firstIndex(of: "/") else { return String(rest) }
    return String(rest[rest.startIndex..<slash])
  }
}

/// Discovers the feed-generator URI for a saved feed whose descriptor is a
/// `feedgen|` value. Kept here so callers never re-parse descriptors.
public enum FeedURIs {
  /// The Discover algorithmic feed URI, from `DISCOVER_FEED_URI`.
  public static let discover =
    "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"
}
