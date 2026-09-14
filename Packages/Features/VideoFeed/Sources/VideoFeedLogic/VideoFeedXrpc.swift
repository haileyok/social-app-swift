import Foundation
import Lexicons
import SwiftAtproto

/// The XRPC surface the immersive video feed needs, behind a protocol so tests
/// can record and script exact calls.
///
/// This mirrors ``HomeFeedLogic/FeedXrpc`` but is declared locally: feature Logic
/// packages in this repo never depend on one another (the boundary is
/// `Packages/<Name>`, and a feature-to-feature edge would drag one product's
/// surface into another's). The two reads the video feed adds over the home feed
/// are `getAuthorFeed` (the `author|…|posts_with_video` source) and the media
/// reads that gate playback.
///
/// Source: `src/lib/api/feed/custom.ts` (`CustomFeedAPI`),
/// `src/lib/api/feed/author.ts` (`AuthorFeedAPI`) and the generator read in
/// `src/state/queries/feed.ts`.
public protocol VideoFeedXrpc: Sendable {
  /// `app.bsky.feed.getFeed`, the hydrated generator read. Port of
  /// `CustomFeedAPI.fetch`.
  func getFeed(
    feed: String, cursor: String?, limit: Int, headers: VideoFeedRequestHeaders
  ) async throws -> VideoFeedPageOutput

  /// `app.bsky.feed.getAuthorFeed`. Port of `AuthorFeedAPI.fetch`.
  func getAuthorFeed(
    actor: String, filter: String, cursor: String?, limit: Int
  ) async throws -> VideoFeedPageOutput

  /// `app.bsky.feed.getFeedGenerator`. Port of `useFeedInfo`.
  func getFeedGenerator(feed: String) async throws -> App.Bsky.FeedDefs_GeneratorView
}

/// The per-request headers a video-feed read carries.
///
/// RN builds these in `src/lib/api/feed/custom.ts`: `Accept-Language` from the
/// content-language prefs, and `X-Bsky-Topics` but only for Bluesky-owned feeds
/// (``VideoFeedConstants/videoFeedURIs`` are Bluesky-owned).
public struct VideoFeedRequestHeaders: Sendable, Equatable {
  /// `Accept-Language`, e.g. `en,de`.
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

/// A page of hydrated feed posts.
public struct VideoFeedPageOutput: Sendable {
  public var cursor: String?
  public var feed: [App.Bsky.FeedDefs_FeedViewPost]

  public init(cursor: String? = nil, feed: [App.Bsky.FeedDefs_FeedViewPost] = []) {
    self.cursor = cursor
    self.feed = feed
  }
}

/// The DIDs whose feeds are "Bluesky-owned", from `BSKY_FEED_OWNER_DIDS`.
///
/// Only these receive the `X-Bsky-Topics` header.
public enum VideoFeedOwners {
  public static let dids: Set<String> = [
    "did:plc:z72i7hdynmk6r22z27h6tvur",
    "did:web:api.bsky.app",
    "did:web:bsky.app",
    "did:plc:yofh3kx63drvfljkibw5zuxo",
  ]

  /// True when `feedURI`'s authority is a Bluesky-owned account.
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
