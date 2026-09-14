import ATProtoClient
import Foundation
import Lexicons
import QueryStore

/// The params RN sends to `app.bsky.feed.getPostThread`.
public struct PostThreadParams: QueryArgs {
  /// How deep below the anchor to hydrate replies. Ported from the RN tree
  /// implementation's `REPLY_TREE_DEPTH = 10` (`state/queries/post-thread.ts`),
  /// which was the value the legacy screen always sent.
  public static let replyTreeDepth = 10

  /// How far above the anchor to walk. RN leaves this unset, which lets the
  /// appview apply its own default; it is a parameter here because the newer
  /// `getPostThreadV2` path and the "read more up" affordance both need to
  /// bound the parent chain.
  public static let defaultParentHeight: Int? = nil

  public var uri: String
  public var depth: Int
  public var parentHeight: Int?

  public init(
    uri: String,
    depth: Int = PostThreadParams.replyTreeDepth,
    parentHeight: Int? = PostThreadParams.defaultParentHeight
  ) {
    self.uri = uri
    self.depth = depth
    self.parentHeight = parentHeight
  }
}

/// The root of every post-thread query key.
///
/// RN's roots are `post-thread` (the removed tree query) and `post-thread-v2`
/// (the current flat query). This package keys its thread read on the former and
/// its derived-list reads on their own roots, matching the RN list queries
/// (`liked-by`, `reposted-by`, `post-quotes`).
public enum PostThreadQueryKey {
  public static let threadRoot = "post-thread"

  /// The thread read for one anchor.
  public static func thread(_ params: PostThreadParams) -> QueryKey {
    QueryKey(threadRoot, params)
  }
}

/// Reads one thread via `app.bsky.feed.getPostThread`.
public struct PostThreadFetcher: Sendable {
  public typealias Fetch = @Sendable (PostThreadParams) async throws
    -> App.Bsky.FeedGetPostThread_Output

  let fetch: Fetch

  public init(fetch: @escaping Fetch) {
    self.fetch = fetch
  }

  /// Builds a fetcher over a routed appview client.
  public init(client: XrpcClient) {
    self.init { params in
      try await client.get(
        App.Bsky.FeedGetPostThread.id,
        params: [
          ("uri", params.uri),
          ("depth", String(params.depth)),
          ("parentHeight", params.parentHeight.map(String.init)),
        ]
      )
    }
  }

  /// Runs the request.
  public func callAsFunction(
    _ params: PostThreadParams
  ) async throws -> App.Bsky.FeedGetPostThread_Output {
    try await fetch(params)
  }
}
