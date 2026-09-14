import Foundation
import Lexicons
import SwiftAtproto

/// Fetches one raw page of a video feed, mirroring the ``HomeFeedLogic/FeedPageFetcher``
/// protocol over this package's own XRPC surface.
///
/// Two fetchers exist, one per ``VideoFeedSource`` case: RN's immersive screen
/// picks `CustomFeedAPI` for `feedgen|…` and `AuthorFeedAPI` for
/// `author|…|…`.
public protocol VideoPageFetcher: Sendable {
  /// Fetch one page at `cursor`.
  func fetch(cursor: String?, limit: Int) async throws -> VideoFeedPageOutput
}

/// The generator branch. Port of `CustomFeedAPI` in
/// `src/lib/api/feed/custom.ts`.
///
/// The appview serves the hydrated feed, and the client adds `Accept-Language`
/// plus `X-Bsky-Topics` for Bluesky-owned feeds - which both video feed URIs are.
/// The page is truncated to `limit` because some generators ignore the pagination
/// limit.
public struct VideoGeneratorFetcher: VideoPageFetcher {
  public let xrpc: any VideoFeedXrpc
  public let feedURI: String
  /// `getContentLanguages().join(',')`.
  public let contentLanguages: [String]
  /// `aggregateUserInterests(preferences)`.
  public let userInterests: String
  /// Whether a session is active. The logged-out branch is a separate path in
  /// RN; callers pass a public client for it.
  public let isAuthenticated: Bool

  public init(
    xrpc: any VideoFeedXrpc,
    feedURI: String,
    contentLanguages: [String] = [],
    userInterests: String = "",
    isAuthenticated: Bool = true
  ) {
    self.xrpc = xrpc
    self.feedURI = feedURI
    self.contentLanguages = contentLanguages
    self.userInterests = userInterests
    self.isAuthenticated = isAuthenticated
  }

  /// The per-request headers, exactly as `custom.ts` builds them.
  ///
  /// RN sets `Accept-Language` from the joined content languages and only sends
  /// `X-Bsky-Topics` for Bluesky-owned feeds. An empty value produces no header
  /// at all rather than an empty one, which is what the header builder's `if let`
  /// expresses.
  public var requestHeaders: VideoFeedRequestHeaders {
    let topics =
      isAuthenticated && VideoFeedOwners.owns(feedURI: feedURI) ? userInterests : nil
    let languages = contentLanguages.isEmpty
      ? nil : contentLanguages.joined(separator: ",")
    return VideoFeedRequestHeaders(
      acceptLanguage: languages,
      bskyTopics: topics?.isEmpty == true ? nil : topics)
  }

  public func fetch(cursor: String?, limit: Int) async throws -> VideoFeedPageOutput {
    let page = try await xrpc.getFeed(
      feed: feedURI, cursor: cursor, limit: limit, headers: requestHeaders)
    let feed = page.feed.count > limit ? Array(page.feed.prefix(limit)) : page.feed
    return VideoFeedPageOutput(cursor: page.cursor, feed: feed)
  }
}

/// The author branch. Port of `AuthorFeedAPI` in `src/lib/api/feed/author.ts`.
///
/// The `filter` is passed through to `getAuthorFeed`; RN additionally sets
/// `includePins` for `posts_and_author_threads`, and applies a client-side reply
/// filter for that same filter - the video feed only ever asks for
/// `posts_with_video`, so neither applies, but the filter is modelled so the
/// wrapper is faithful.
public struct VideoAuthorFetcher: VideoPageFetcher {
  public let xrpc: any VideoFeedXrpc
  public let actor: String
  public let filter: VideoAuthorFilter

  public init(xrpc: any VideoFeedXrpc, actor: String, filter: VideoAuthorFilter) {
    self.xrpc = xrpc
    self.actor = actor
    self.filter = filter
  }

  /// RN: `includePins = filter === 'posts_and_author_threads'`.
  public var includePins: Bool { filter == .postsAndAuthorThreads }

  public func fetch(cursor: String?, limit: Int) async throws -> VideoFeedPageOutput {
    try await xrpc.getAuthorFeed(
      actor: actor, filter: filter.rawValue, cursor: cursor, limit: limit)
  }
}

/// Builds the fetcher for a source.
public enum VideoFetcherFactory {
  /// The fetcher for `source`.
  ///
  /// - Parameters:
  ///   - source: the resolved video-feed source.
  ///   - xrpc: the recording or live XRPC surface.
  ///   - contentLanguages: the viewer's content languages, for the header.
  ///   - userInterests: the aggregated interests, for the header.
  ///   - isAuthenticated: whether a session is active.
  public static func makeFetcher(
    for source: VideoFeedSource,
    xrpc: any VideoFeedXrpc,
    contentLanguages: [String] = [],
    userInterests: String = "",
    isAuthenticated: Bool = true
  ) -> any VideoPageFetcher {
    switch source {
    case .feedgen(let uri):
      return VideoGeneratorFetcher(
        xrpc: xrpc,
        feedURI: uri,
        contentLanguages: contentLanguages,
        userInterests: userInterests,
        isAuthenticated: isAuthenticated)
    case .author(let did, let filter):
      return VideoAuthorFetcher(xrpc: xrpc, actor: did, filter: filter)
    }
  }
}
