import Domain
import Foundation
import Lexicons
import SwiftAtproto

/// A single renderable post within a slice, with the parent context needed to
/// render it.
///
/// The Swift counterpart of `FeedPostSliceItem` in
/// `src/state/queries/post-feed.ts`. Moderation is deliberately absent: it is a
/// UI-layer decision and the Logic package has no moderation engine dependency.
public struct HomeFeedSliceItem: Sendable {
  public var post: App.Bsky.FeedDefs_PostView
  public var record: App.Bsky.FeedPost
  public var postNumbering: ValidFeedPostNumbering?
  public var parentAuthor: App.Bsky.ActorDefs_ProfileViewBasic?
  public var isParentBlocked: Bool
  public var isParentNotFound: Bool
  /// The `_reactKey` form: `<slice key>-<index>-<uri>`.
  public var reactKey: String
  public var uri: String

  public init(
    post: App.Bsky.FeedDefs_PostView,
    record: App.Bsky.FeedPost,
    postNumbering: ValidFeedPostNumbering? = nil,
    parentAuthor: App.Bsky.ActorDefs_ProfileViewBasic? = nil,
    isParentBlocked: Bool = false,
    isParentNotFound: Bool = false,
    reactKey: String = "",
    uri: String = ""
  ) {
    self.post = post
    self.record = record
    self.postNumbering = postNumbering
    self.parentAuthor = parentAuthor
    self.isParentBlocked = isParentBlocked
    self.isParentNotFound = isParentNotFound
    self.reactKey = reactKey
    self.uri = uri.isEmpty ? post.uri.rawValue : uri
  }
}

/// A renderable group of posts (a thread, or a single post) plus the feed
/// metadata the list view needs.
///
/// Port of `FeedPostSlice` in `src/state/queries/post-feed.ts`. The `reason` is
/// preserved exactly so the Views layer can render repost/pin attribution, and
/// `feedContext` / `reqId` survive because the Discover feedback pipeline reads
/// them.
public struct HomeFeedSlice: Sendable {
  public var reactKey: String
  public var items: [HomeFeedSliceItem]
  public var isIncompleteThread: Bool
  public var isFallbackMarker: Bool
  public var isOrphan: Bool
  public var isThreadMuted: Bool
  public var feedContext: String?
  public var reqId: String?
  public var feedPostUri: String
  /// The feed-item reason (repost, pin, ...). Preserved from the wire.
  public var reason: App.Bsky.FeedDefs_FeedViewPost_Reason?
  /// The app-internal feed-source marker, when the feed attached one.
  public var source: ReasonFeedSource?
  public var rootUri: String

  public init(
    reactKey: String,
    items: [HomeFeedSliceItem],
    isIncompleteThread: Bool = false,
    isFallbackMarker: Bool = false,
    isOrphan: Bool = false,
    isThreadMuted: Bool = false,
    feedContext: String? = nil,
    reqId: String? = nil,
    feedPostUri: String = "",
    reason: App.Bsky.FeedDefs_FeedViewPost_Reason? = nil,
    source: ReasonFeedSource? = nil,
    rootUri: String = ""
  ) {
    self.reactKey = reactKey
    self.items = items
    self.isIncompleteThread = isIncompleteThread
    self.isFallbackMarker = isFallbackMarker
    self.isOrphan = isOrphan
    self.isThreadMuted = isThreadMuted
    self.feedContext = feedContext
    self.reqId = reqId
    self.feedPostUri = feedPostUri
    self.reason = reason
    self.source = source
    self.rootUri = rootUri
  }

  /// The post URI of the slice's selected (last) item, for feedback tracking.
  public var likeCount: Int { items.last?.post.likeCount ?? 0 }
}

/// Turns a ``Domain/FeedViewPostsSlice`` into a ``HomeFeedSlice``, stamping the
/// per-item react keys the list view uses.
///
/// The slice key comes from the tuner; the item key is
/// `<slice key>-<index>-<uri>`, matching `post-feed.ts`.
public func makeHomeFeedSlice(from slice: FeedViewPostsSlice) -> HomeFeedSlice {
  let items = slice.items.enumerated().map { index, item in
    HomeFeedSliceItem(
      post: item.post,
      record: item.record,
      postNumbering: item.postNumbering,
      parentAuthor: item.parentAuthor,
      isParentBlocked: item.isParentBlocked,
      isParentNotFound: item.isParentNotFound,
      reactKey: "\(slice.reactKey)-\(index)-\(item.post.uri.rawValue)",
      uri: item.post.uri.rawValue)
  }
  return HomeFeedSlice(
    reactKey: slice.reactKey,
    items: items,
    isIncompleteThread: slice.isIncompleteThread,
    isFallbackMarker: slice.isFallbackMarker,
    isOrphan: slice.isOrphan,
    isThreadMuted: slice.isThreadMuted,
    feedContext: slice.feedContext,
    reqId: slice.reqId,
    feedPostUri: slice.feedPostUri,
    reason: slice.feedPost.reason,
    source: slice.sourceReason,
    rootUri: slice.rootUri)
}
