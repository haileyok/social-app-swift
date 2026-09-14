import Domain
import Foundation
import Lexicons
import SwiftAtproto

/// Fetches one raw page of a feed, the Swift port of the RN `FeedAPI` classes
/// (`src/lib/api/feed/following.ts`, `custom.ts`, `list.ts`).
///
/// A fetcher owns the descriptor-specific request shape, so `HomeFeedQuery` can
/// treat every feed type identically.
public protocol FeedPageFetcher: Sendable {
  /// Peek at the newest item without consuming a page. Port of `peekLatest()`.
  /// Returns `nil` when the feed is empty.
  func peekLatest() async throws -> App.Bsky.FeedDefs_FeedViewPost?

  /// Fetch one page at `cursor`. Port of `fetch({cursor, limit})`.
  func fetch(cursor: String?, limit: Int) async throws -> RawFeedPage
}

/// A raw page as it comes off the wire, before tuning.
public struct RawFeedPage: Sendable {
  public var cursor: String?
  public var feed: [App.Bsky.FeedDefs_FeedViewPost]
  /// The cursor that produced this page, so the tuned page can record it.
  public var requestCursor: String?

  public init(
    cursor: String? = nil,
    feed: [App.Bsky.FeedDefs_FeedViewPost] = [],
    requestCursor: String? = nil
  ) {
    self.cursor = cursor
    self.feed = feed
    self.requestCursor = requestCursor
  }
}

/// The following timeline. Port of `FollowingFeedAPI`.
public struct FollowingFeedFetcher: FeedPageFetcher {
  public let xrpc: any FeedXrpc

  public init(xrpc: any FeedXrpc) {
    self.xrpc = xrpc
  }

  public func peekLatest() async throws -> App.Bsky.FeedDefs_FeedViewPost? {
    let page = try await xrpc.getTimeline(cursor: nil, limit: HomeFeedConstants.peekLatestLimit)
    return page.feed.first
  }

  public func fetch(cursor: String?, limit: Int) async throws -> RawFeedPage {
    let page = try await xrpc.getTimeline(cursor: cursor, limit: limit)
    return RawFeedPage(cursor: page.cursor, feed: page.feed)
  }
}

/// A feed generator read through `getFeed`.
///
/// Port of `CustomFeedAPI.fetch` in the current RN snapshot: the appview serves
/// the hydrated feed, and the client adds `Accept-Language` plus `X-Bsky-Topics`
/// for Bluesky-owned feeds. The page is truncated to `limit` because some
/// generators ignore the pagination limit (the `-prf` note in `custom.ts`).
public struct CustomFeedFetcher: FeedPageFetcher {
  public let xrpc: any FeedXrpc
  public let feedURI: String
  /// `getContentLanguages().join(',')`.
  public let contentLanguages: [String]
  /// `aggregateUserInterests(preferences)`.
  public let userInterests: String
  /// Whether a session is active. The logged-out branch is a separate path in
  /// RN; this port always uses the authenticated appview client, and callers
  /// pass the public client for the logged-out case.
  public let isAuthenticated: Bool

  public init(
    xrpc: any FeedXrpc,
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
  public var requestHeaders: FeedRequestHeaders {
    let topics =
      isAuthenticated && BlueskyFeedOwners.owns(feedURI: feedURI)
      ? userInterests : nil
    return FeedRequestHeaders(
      acceptLanguage: contentLanguages.joined(separator: ","),
      bskyTopics: topics)
  }

  public func peekLatest() async throws -> App.Bsky.FeedDefs_FeedViewPost? {
    let page = try await xrpc.getFeed(
      feed: feedURI, cursor: nil, limit: HomeFeedConstants.peekLatestLimit,
      headers: requestHeaders)
    return page.feed.first
  }

  public func fetch(cursor: String?, limit: Int) async throws -> RawFeedPage {
    let page = try await xrpc.getFeed(
      feed: feedURI, cursor: cursor, limit: limit, headers: requestHeaders)
    // Some custom feeds fail to enforce the pagination limit, so truncate.
    let feed = page.feed.count > limit ? Array(page.feed.prefix(limit)) : page.feed
    return RawFeedPage(cursor: page.cursor, feed: feed)
  }
}

/// A feed generator read through the explicit two-step
/// `getFeedSkeleton` → `getPosts` flow.
///
/// This is the classic feed-generator protocol path: the generator returns a
/// skeleton of post URIs, and the client hydrates them into post views with
/// `app.bsky.feed.getPosts`, in batches. It is provided alongside
/// ``CustomFeedFetcher`` for callers that want to talk to a generator service
/// directly rather than through appview hydration.
///
/// The skeleton's `feedContext` and `reqId` are carried over onto the hydrated
/// items, which is what makes Discover-style feedback work; posts the appview
/// cannot return are dropped from the page.
public struct SkeletonHydratingFetcher: FeedPageFetcher {
  public let xrpc: any FeedXrpc
  public let feedURI: String
  /// Maximum URIs per `getPosts` call. The appview caps `getPosts` at 25.
  public let hydrationBatchSize: Int

  public init(xrpc: any FeedXrpc, feedURI: String, hydrationBatchSize: Int = 25) {
    self.xrpc = xrpc
    self.feedURI = feedURI
    self.hydrationBatchSize = hydrationBatchSize
  }

  public func peekLatest() async throws -> App.Bsky.FeedDefs_FeedViewPost? {
    let page = try await fetch(cursor: nil, limit: 1)
    return page.feed.first
  }

  public func fetch(cursor: String?, limit: Int) async throws -> RawFeedPage {
    let skeleton = try await xrpc.getFeedSkeleton(
      feed: feedURI, cursor: cursor, limit: limit)
    let hydrated = try await hydrate(skeleton)
    return RawFeedPage(cursor: skeleton.cursor, feed: hydrated)
  }

  /// Hydrates a skeleton into feed view posts, preserving order and
  /// `feedContext` / `reqId`.
  func hydrate(_ skeleton: FeedSkeletonOutput) async throws -> [App.Bsky.FeedDefs_FeedViewPost] {
    let uris = skeleton.feed.map { $0.post.rawValue }
    var byURI: [String: App.Bsky.FeedDefs_PostView] = [:]
    for batch in Self.batches(of: uris, size: hydrationBatchSize) {
      for post in try await xrpc.getPosts(uris: batch) {
        byURI[post.uri.rawValue] = post
      }
    }

    return skeleton.feed.compactMap { item in
      guard let post = byURI[item.post.rawValue] else { return nil }
      return App.Bsky.FeedDefs_FeedViewPost(
        feedContext: item.feedContext,
        post: post,
        reason: Self.reason(from: item.reason),
        reqId: skeleton.reqId)
    }
  }

  /// The skeleton reason is translated to the hydrated `feedViewPost` reason
  /// union. The skeleton only carries the repost record URI
  /// (`skeletonReasonRepost.repost`), while `reasonRepost` needs a `by` profile
  /// and an `indexedAt`, which the skeleton does not supply - so no reason is
  /// fabricated here and hydration leaves attribution to the appview path
  /// (``CustomFeedFetcher``), which is where RN gets it too.
  static func reason(
    from skeletonReason: App.Bsky.FeedDefs_SkeletonFeedPost_Reason?
  ) -> App.Bsky.FeedDefs_FeedViewPost_Reason? {
    switch skeletonReason {
    case .feedDefsSkeletonReasonRepost, .feedDefsSkeletonReasonPin, ._other, nil:
      return nil
    }
  }

  /// Splits `values` into batches of at most `size`.
  static func batches(of values: [String], size: Int) -> [[String]] {
    guard size > 0 else { return values.isEmpty ? [] : [values] }
    var out: [[String]] = []
    var index = 0
    while index < values.count {
      let end = Swift.min(index + size, values.count)
      out.append(Array(values[index..<end]))
      index = end
    }
    return out
  }
}

/// A user list feed. Port of `ListFeedAPI`.
public struct ListFeedFetcher: FeedPageFetcher {
  public let xrpc: any FeedXrpc
  public let listURI: String

  public init(xrpc: any FeedXrpc, listURI: String) {
    self.xrpc = xrpc
    self.listURI = listURI
  }

  public func peekLatest() async throws -> App.Bsky.FeedDefs_FeedViewPost? {
    let page = try await xrpc.getListFeed(
      list: listURI, cursor: nil, limit: HomeFeedConstants.peekLatestLimit)
    return page.feed.first
  }

  public func fetch(cursor: String?, limit: Int) async throws -> RawFeedPage {
    let page = try await xrpc.getListFeed(list: listURI, cursor: cursor, limit: limit)
    return RawFeedPage(cursor: page.cursor, feed: page.feed)
  }
}
