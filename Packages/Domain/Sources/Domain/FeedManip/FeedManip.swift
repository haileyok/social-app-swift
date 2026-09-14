import Foundation
import Lexicons

// Port of `src/lib/api/feed-manip.ts`.
//
// The `lexicons` markers below flag local stand-in types that the generated
// lexicon package should eventually replace; they are intentional and tracked,
// so the `todo` rule is disabled for this file.
// swiftlint:disable todo

// MARK: - Post numbering

/// The AppView numbering fields.
///
/// `app.bsky.unspecced.defs#threadItemPost` carries these, but
/// `app.bsky.feed.defs#feedViewPost` does not yet, so the generated
/// `App.Bsky.FeedDefs_FeedViewPost` has no fields for them.
/// TODO(lexicons): replace when generated.
public struct FeedPostNumbering: Hashable, Sendable {
  public var opThreadPostIndex: Int?
  public var opThreadPostCount: Int?

  public init(opThreadPostIndex: Int? = nil, opThreadPostCount: Int? = nil) {
    self.opThreadPostIndex = opThreadPostIndex
    self.opThreadPostCount = opThreadPostCount
  }
}

/// Numbering where both fields are present and in range.
public struct ValidFeedPostNumbering: Hashable, Sendable {
  public let opThreadPostIndex: Int
  public let opThreadPostCount: Int

  public init(opThreadPostIndex: Int, opThreadPostCount: Int) {
    self.opThreadPostIndex = opThreadPostIndex
    self.opThreadPostCount = opThreadPostCount
  }
}

/// The feed source marker the app attaches to feed-generated items.
/// Port of `ReasonFeedSource` from `src/lib/api/feed/types.ts`.
public struct ReasonFeedSource: Hashable, Sendable {
  public static let type = "reasonFeedSource"
  public let uri: String
  public let href: String

  public init(uri: String, href: String) {
    self.uri = uri
    self.href = href
  }
}

/// `app.bsky.feed.defs#feedViewPost` plus the AppView numbering fields and the
/// app-internal `__source` marker.
///
/// The generated `FeedViewPost` has no numbering fields and no `__source`; this
/// wraps it with both.
/// TODO(lexicons): replace when generated.
public struct FeedViewPost: Sendable {
  public var post: App.Bsky.FeedDefs_PostView
  public var reply: App.Bsky.FeedDefs_ReplyRef?
  public var reason: App.Bsky.FeedDefs_FeedViewPost_Reason?
  public var feedContext: String?
  public var reqId: String?
  public var opThreadPostIndex: Int?
  public var opThreadPostCount: Int?
  /// The app-internal feed-source marker; preferred over `reason` by ``reason``.
  public var source: ReasonFeedSource?

  public init(
    post: App.Bsky.FeedDefs_PostView,
    reply: App.Bsky.FeedDefs_ReplyRef? = nil,
    reason: App.Bsky.FeedDefs_FeedViewPost_Reason? = nil,
    feedContext: String? = nil,
    reqId: String? = nil,
    opThreadPostIndex: Int? = nil,
    opThreadPostCount: Int? = nil,
    source: ReasonFeedSource? = nil
  ) {
    self.post = post
    self.reply = reply
    self.reason = reason
    self.feedContext = feedContext
    self.reqId = reqId
    self.opThreadPostIndex = opThreadPostIndex
    self.opThreadPostCount = opThreadPostCount
    self.source = source
  }

  /// Wraps a decoded generated feed view post. Numbering is unavailable on
  /// decoded generated values, so callers set it explicitly when known.
  public init(_ generated: App.Bsky.FeedDefs_FeedViewPost) {
    self.init(
      post: generated.post,
      reply: generated.reply,
      reason: generated.reason,
      feedContext: generated.feedContext,
      reqId: generated.reqId
    )
  }
}

/// The synthetic fallback marker post (`src/lib/api/feed/home.ts`).
public enum FallbackMarkerPost {
  /// Only `post.uri` is ever read.
  public static let uri = "fallback-marker-post"
}

/// Reads the valid numbering out of a ``FeedPostNumbering``.
func getPostNumbering(_ value: FeedPostNumbering) -> ValidFeedPostNumbering? {
  guard let index = value.opThreadPostIndex, let count = value.opThreadPostCount,
    index >= 1, count >= 1, index <= count
  else {
    return nil
  }
  return ValidFeedPostNumbering(opThreadPostIndex: index, opThreadPostCount: count)
}

/// Derives the hydrated context numbering from the selected post's numbering.
func inferPostNumbering(_ feedPost: FeedViewPost, position: ContextPosition) -> ValidFeedPostNumbering? {
  guard let numbering = getPostNumbering(
    FeedPostNumbering(
      opThreadPostIndex: feedPost.opThreadPostIndex,
      opThreadPostCount: feedPost.opThreadPostCount))
  else {
    return nil
  }

  // Feed responses number only the selected post, so derive the hydrated
  // context that the feed renders alongside it.
  return getPostNumbering(
    FeedPostNumbering(
      opThreadPostIndex: position == .root ? 1 : numbering.opThreadPostIndex - 1,
      opThreadPostCount: numbering.opThreadPostCount))
}

/// Which hydrated context position is being numbered.
public enum ContextPosition: Hashable, Sendable {
  case parent
  case root
}

// MARK: - Slice items

/// One post within a slice, with the parent context needed to render it.
public struct FeedSliceItem: Sendable {
  public var post: App.Bsky.FeedDefs_PostView
  public var record: App.Bsky.FeedPost
  public var postNumbering: ValidFeedPostNumbering?
  public var parentAuthor: App.Bsky.ActorDefs_ProfileViewBasic?
  public var isParentBlocked: Bool
  public var isParentNotFound: Bool

  public init(
    post: App.Bsky.FeedDefs_PostView,
    record: App.Bsky.FeedPost,
    postNumbering: ValidFeedPostNumbering?,
    parentAuthor: App.Bsky.ActorDefs_ProfileViewBasic?,
    isParentBlocked: Bool,
    isParentNotFound: Bool
  ) {
    self.post = post
    self.record = record
    self.postNumbering = postNumbering
    self.parentAuthor = parentAuthor
    self.isParentBlocked = isParentBlocked
    self.isParentNotFound = isParentNotFound
  }
}

/// The authors a slice's reply chain touches.
public struct AuthorContext: Hashable, Sendable {
  public var author: App.Bsky.ActorDefs_ProfileViewBasic
  public var parentAuthor: App.Bsky.ActorDefs_ProfileViewBasic?
  public var grandparentAuthor: App.Bsky.ActorDefs_ProfileViewBasic?
  public var rootAuthor: App.Bsky.ActorDefs_ProfileViewBasic?

  public init(
    author: App.Bsky.ActorDefs_ProfileViewBasic,
    parentAuthor: App.Bsky.ActorDefs_ProfileViewBasic? = nil,
    grandparentAuthor: App.Bsky.ActorDefs_ProfileViewBasic? = nil,
    rootAuthor: App.Bsky.ActorDefs_ProfileViewBasic? = nil
  ) {
    self.author = author
    self.parentAuthor = parentAuthor
    self.grandparentAuthor = grandparentAuthor
    self.rootAuthor = rootAuthor
  }
}

// MARK: - Slice

/// A renderable group of posts (a thread, or a single post).
///
/// Reference semantics, because ``FeedTuner/tune(_:dryRun:)`` mutates
/// `items` in place while de-duplicating.
public final class FeedViewPostsSlice {
  public let reactKey: String
  public let feedPost: FeedViewPost
  public var items: [FeedSliceItem]
  public var isIncompleteThread: Bool
  public var isFallbackMarker: Bool
  public var isOrphan: Bool
  public var isThreadMuted: Bool
  public let rootUri: String
  public let feedPostUri: String

  public init(_ feedPost: FeedViewPost, postNumberingByUri: [String: ValidFeedPostNumbering]) {
    let post = feedPost.post
    let reply = feedPost.reply

    self.items = []
    self.isIncompleteThread = false
    self.isFallbackMarker = false
    self.isOrphan = false
    self.isThreadMuted = post.viewer?.threadMuted ?? false
    self.feedPostUri = post.uri.rawValue

    if let rootView = reply?.root.postView {
      self.rootUri = rootView.uri.rawValue
    } else {
      self.rootUri = post.uri.rawValue
    }

    self.feedPost = feedPost
    self.reactKey = Self.makeReactKey(feedPost)

    if post.uri.rawValue == FallbackMarkerPost.uri {
      self.isFallbackMarker = true
      return
    }

    guard let record = post.record.feedPostRecord else {
      return
    }

    let parent = reply?.parent
    self.items.append(
      FeedSliceItem(
        post: post,
        record: record,
        postNumbering: postNumberingByUri[post.uri.rawValue],
        parentAuthor: parent?.postView?.author,
        isParentBlocked: parent?.isBlocked ?? false,
        isParentNotFound: parent?.isNotFound ?? false))

    guard let reply else {
      if record.reply != nil {
        // This reply wasn't properly hydrated by the AppView.
        self.isOrphan = true
        self.items[0].isParentNotFound = true
      }
      return
    }

    if feedPost.reason != nil {
      return
    }

    hydrateParentAndRoot(
      reply: reply, parent: parent, feedPost: feedPost, postNumberingByUri: postNumberingByUri)
  }

  /// `slice-<uri>-<indexedAt>`, where a repost reason supplies its own
  /// `indexedAt` and a pin does not.
  private static func makeReactKey(_ feedPost: FeedViewPost) -> String {
    let indexedAt: String
    if case .feedDefsReasonRepost(let repost) = feedPost.reason {
      indexedAt = repost.indexedAt.rawValue
    } else {
      indexedAt = feedPost.post.indexedAt.rawValue
    }
    return "slice-\(feedPost.post.uri.rawValue)-\(indexedAt)"
  }

  /// Adds the hydrated parent/root context to `items`, setting the orphan and
  /// incomplete-thread flags the RN constructor derives along the way.
  private func hydrateParentAndRoot(
    reply: App.Bsky.FeedDefs_ReplyRef,
    parent: App.Bsky.FeedDefs_ReplyRef_Parent?,
    feedPost: FeedViewPost,
    postNumberingByUri: [String: ValidFeedPostNumbering]
  ) {
    guard let parentView = parent?.postView,
      let parentRecord = parentView.record.feedPostRecord
    else {
      self.isOrphan = true
      return
    }

    let root = reply.root
    let rootIsView = root.postView != nil || root.isBlocked || root.isNotFound
    /*
     * If the parent is also the root, we just so happen to have the data we
     * need to compute if the parent's parent (grandparent) is blocked. This
     * doesn't always happen, of course, but we can take advantage of it when
     * it does.
     */
    let grandparent: App.Bsky.FeedDefs_ReplyRef_Root? =
      (rootIsView && parentRecord.reply?.parent.uri.rawValue == root.uriValue) ? root : nil
    let isGrandparentBlocked = grandparent?.isBlocked ?? false
    let isGrandparentNotFound = grandparent?.isNotFound ?? false

    self.items.insert(
      FeedSliceItem(
        post: parentView,
        record: parentRecord,
        postNumbering: postNumberingByUri[parentView.uri.rawValue]
          ?? inferPostNumbering(feedPost, position: .parent),
        parentAuthor: reply.grandparentAuthor,
        isParentBlocked: isGrandparentBlocked,
        isParentNotFound: isGrandparentNotFound),
      at: 0)

    if isGrandparentBlocked {
      self.isOrphan = true
      // Keep going, it might still have a root, and we need this for thread
      // de-deduping.
    }

    guard let rootView = root.postView, let rootRecord = rootView.record.feedPostRecord else {
      self.isOrphan = true
      return
    }
    if rootView.uri.rawValue == parentView.uri.rawValue {
      return
    }

    self.items.insert(
      FeedSliceItem(
        post: rootView,
        record: rootRecord,
        postNumbering: postNumberingByUri[rootView.uri.rawValue]
          ?? inferPostNumbering(feedPost, position: .root),
        parentAuthor: nil,
        isParentBlocked: false,
        isParentNotFound: false),
      at: 0)

    if parentRecord.reply?.parent.uri.rawValue != rootView.uri.rawValue {
      self.isIncompleteThread = true
    }
  }

  /// Whether the selected post carries a quote embed.
  public var isQuotePost: Bool {
    switch feedPost.post.embed {
    case .embedRecordView, .embedRecordWithMediaView: return true
    default: return false
    }
  }

  /// Whether the selected post is a reply.
  public var isReply: Bool {
    (feedPost.post.record.feedPostRecord?.reply) != nil
  }

  /// The feed source when the app attached one, else the feed's reason.
  public var reason: App.Bsky.FeedDefs_FeedViewPost_Reason? {
    if feedPost.source != nil {
      return nil
    }
    return feedPost.reason
  }

  /// The app-internal feed source, when present.
  public var sourceReason: ReasonFeedSource? {
    feedPost.source
  }

  public var feedContext: String? {
    feedPost.feedContext
  }

  public var reqId: String? {
    feedPost.reqId
  }

  /// Whether the feed item is a repost. Reads the raw `reason`, not ``reason``.
  public var isRepost: Bool {
    if case .feedDefsReasonRepost = feedPost.reason { return true }
    return false
  }

  public var likeCount: Int {
    feedPost.post.likeCount ?? 0
  }

  public func containsUri(_ uri: String) -> Bool {
    items.contains { $0.post.uri.rawValue == uri }
  }

  public func getAuthors() -> AuthorContext {
    let feedPost = self.feedPost
    let author = feedPost.post.author
    var parentAuthor: App.Bsky.ActorDefs_ProfileViewBasic?
    var grandparentAuthor: App.Bsky.ActorDefs_ProfileViewBasic?
    var rootAuthor: App.Bsky.ActorDefs_ProfileViewBasic?

    if let reply = feedPost.reply {
      if let parent = reply.parent.postView {
        parentAuthor = parent.author
      }
      if let grandparent = reply.grandparentAuthor {
        grandparentAuthor = grandparent
      }
      if let root = reply.root.postView {
        rootAuthor = root.author
      }
    }

    return AuthorContext(
      author: author,
      parentAuthor: parentAuthor,
      grandparentAuthor: grandparentAuthor,
      rootAuthor: rootAuthor)
  }
}

// MARK: - Slice creation

/// Builds slices from a feed page, dropping empties (except fallback markers).
public func createFeedViewPostsSlices(_ feed: [FeedViewPost]) -> [FeedViewPostsSlice] {
  var postNumberingByUri: [String: ValidFeedPostNumbering] = [:]
  for item in feed {
    let numbering = getPostNumbering(
      FeedPostNumbering(
        opThreadPostIndex: item.opThreadPostIndex,
        opThreadPostCount: item.opThreadPostCount))
    if let numbering {
      postNumberingByUri[item.post.uri.rawValue] = numbering
    }
  }

  return feed
    .map { FeedViewPostsSlice($0, postNumberingByUri: postNumberingByUri) }
    .filter { !$0.items.isEmpty || $0.isFallbackMarker }
}
