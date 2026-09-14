import ATProtoClient
import Foundation
import Lexicons
import QueryStore

/// The three derived lists a post screen shows: who liked it, who reposted it,
/// and who quoted it.
///
/// All three are cursor-paginated appview reads with the same shape, so they
/// share one page size and one construction pattern. Port of
/// `state/queries/post-liked-by.ts`, `post-reposted-by.ts` and
/// `post-quotes.ts`.
public enum PostThreadList {
  /// RN's `PAGE_SIZE` in all three list queries.
  public static let pageSize = 30

  /// The query-key roots, matching the RN ones.
  public static let likedByRoot = "liked-by"
  public static let repostedByRoot = "reposted-by"
  public static let quotesRoot = "post-quotes"

  /// One list read's key args.
  public struct ListArgs: QueryArgs {
    public var uri: String
    public var accountDid: String?

    public init(uri: String, accountDid: String? = nil) {
      self.uri = uri
      self.accountDid = accountDid
    }
  }

  /// The key for the liked-by list of a post.
  public static func likedByKey(_ args: ListArgs) -> QueryKey {
    QueryKey(likedByRoot, args, options: accountScope(args.accountDid))
  }

  /// The key for the reposted-by list of a post.
  public static func repostedByKey(_ args: ListArgs) -> QueryKey {
    QueryKey(repostedByRoot, args, options: accountScope(args.accountDid))
  }

  /// The key for the quotes list of a post.
  public static func quotesKey(_ args: ListArgs) -> QueryKey {
    QueryKey(quotesRoot, args, options: accountScope(args.accountDid))
  }

  static func accountScope(_ did: String?) -> QueryOptions {
    QueryOptions(scope: did)
  }
}

/// A liked-by page item.
public struct PostLike: Sendable, Identifiable {
  public let actor: App.Bsky.ActorDefs_ProfileView
  public let createdAt: String
  public let indexedAt: String

  public var id: String { actor.did.rawValue }

  public init(actor: App.Bsky.ActorDefs_ProfileView, createdAt: String, indexedAt: String) {
    self.actor = actor
    self.createdAt = createdAt
    self.indexedAt = indexedAt
  }
}

/// A quotes list page item: a post that quotes the anchor.
public struct PostQuote: Sendable, Identifiable {
  public let post: App.Bsky.FeedDefs_PostView

  public var id: String { post.uri.rawValue }

  public init(post: App.Bsky.FeedDefs_PostView) {
    self.post = post
  }
}

/// The liked-by list: an infinite query over `app.bsky.feed.getLikes`.
public struct LikedByQuery: Sendable {
  public let query: InfiniteQuery<PostLike>

  public init(
    store: QueryStore,
    client: XrpcClient,
    args: PostThreadList.ListArgs,
    staleTime: TimeInterval? = nil
  ) {
    let fetch: @Sendable (String?) async throws -> QueryPage<PostLike> = { cursor in
      let output: App.Bsky.FeedGetLikes_Output = try await client.get(
        App.Bsky.FeedGetLikes.id,
        params: [
          ("uri", args.uri),
          ("limit", String(PostThreadList.pageSize)),
          ("cursor", cursor),
        ]
      )
      return QueryPage(
        items: output.likes.map {
          PostLike(
            actor: $0.actor,
            createdAt: $0.createdAt.rawValue,
            indexedAt: $0.indexedAt.rawValue)
        },
        cursor: output.cursor
      )
    }
    self.query = InfiniteQuery(
      store: store,
      key: PostThreadList.likedByKey(args),
      identity: \.id,
      page: fetch)
    _ = staleTime
  }
}

/// The reposted-by list: an infinite query over `app.bsky.feed.getRepostedBy`.
public struct RepostedByQuery: Sendable {
  public let query: InfiniteQuery<App.Bsky.ActorDefs_ProfileView>

  public init(
    store: QueryStore,
    client: XrpcClient,
    args: PostThreadList.ListArgs
  ) {
    let fetch: @Sendable (String?) async throws -> QueryPage<App.Bsky.ActorDefs_ProfileView> = { cursor in
      let output: App.Bsky.FeedGetRepostedBy_Output = try await client.get(
        App.Bsky.FeedGetRepostedBy.id,
        params: [
          ("uri", args.uri),
          ("limit", String(PostThreadList.pageSize)),
          ("cursor", cursor),
        ]
      )
      return QueryPage(items: output.repostedBy, cursor: output.cursor)
    }
    self.query = InfiniteQuery(
      store: store,
      key: PostThreadList.repostedByKey(args),
      identity: { $0.did.rawValue },
      page: fetch)
  }
}

/// The quotes list: an infinite query over `app.bsky.feed.getQuotes`.
public struct QuotesQuery: Sendable {
  public let query: InfiniteQuery<PostQuote>

  public init(
    store: QueryStore,
    client: XrpcClient,
    args: PostThreadList.ListArgs
  ) {
    let fetch: @Sendable (String?) async throws -> QueryPage<PostQuote> = { cursor in
      let output: App.Bsky.FeedGetQuotes_Output = try await client.get(
        App.Bsky.FeedGetQuotes.id,
        params: [
          ("uri", args.uri),
          ("limit", String(PostThreadList.pageSize)),
          ("cursor", cursor),
        ]
      )
      return QueryPage(items: output.posts.map(PostQuote.init), cursor: output.cursor)
    }
    self.query = InfiniteQuery(
      store: store,
      key: PostThreadList.quotesKey(args),
      identity: \.id,
      page: fetch)
  }
}
