import Foundation
import Lexicons
import Moderation

/// A post that has no hydrated view: the server answered the branch with a
/// `#notFoundPost` or `#blockedPost` tombstone, or the record itself could not
/// be read.
///
/// Port of the RN `ThreadNotFound | ThreadBlocked` node types
/// (`state/queries/post-thread.ts`) plus the moderation-driven branch that the
/// newer flattened traversal handles inline.
public enum ThreadTombstoneKind: String, Sendable, Hashable, CaseIterable {
  /// The post record no longer exists (`#notFoundPost`, `notFound: true`).
  case deleted
  /// The viewer is blocked by, or has blocked, the author (`#blockedPost`).
  case blocked
  /// The post exists but the viewer's moderation settings hide it. RN splits
  /// this into a blurred row that stays in place plus a separate
  /// "other replies" bucket; the data layer surfaces the decision so a view can
  /// pick either presentation.
  case hiddenByModeration
}

/// One row of the flattened thread.
///
/// A flat list is what both RN implementations eventually render: the legacy
/// tree screen flattens to `parents + highlightedPost + replies`, and the newer
/// `getPostThreadV2` traversal is flat on the wire. Keeping the linear form in
/// the data layer means a view never walks a tree.
public struct ThreadItem: Sendable, Identifiable {
  public enum Content: Sendable {
    /// A hydrated post with its parsed record and the connector/indent state a
    /// view needs to draw the reply lines.
    case post(ThreadPostContent)
    /// A placeholder for a branch the server refused to hydrate.
    case tombstone(ThreadTombstone)
    /// A "read more" affordance. `direction` says whether it continues the
    /// chain upwards (unhydrated parents) or downwards (unhydrated replies).
    case readMore(ReadMoreContent)
    /// An inline row for unhydrated replies beyond the fetched window.
    case showMore
  }

  /// Stable identity: the post uri, or a synthesised key for synthetic rows.
  public let id: String
  public let uri: String
  /// 0 is the anchor. Negative values are parents, positive are replies.
  public let depth: Int
  /// The anchor row.
  public let isAnchor: Bool
  public let content: Content
  /// The connector/indent state a view needs to draw the reply lines around
  /// this row. `nil` for synthetic rows (tombstones, read-more, show-more).
  public let connector: ThreadConnector?

  public init(
    id: String,
    uri: String,
    depth: Int,
    isAnchor: Bool,
    content: Content,
    connector: ThreadConnector? = nil
  ) {
    self.id = id
    self.uri = uri
    self.depth = depth
    self.isAnchor = isAnchor
    self.content = content
    self.connector = connector
  }

  /// A copy with the connector filled in, used by the annotation pass.
  public func withConnector(_ connector: ThreadConnector?) -> ThreadItem {
    ThreadItem(
      id: id, uri: uri, depth: depth, isAnchor: isAnchor, content: content,
      connector: connector)
  }
}

/// The connector/indent state for one row.
///
/// Port of the `ui` object RN attaches to every `ThreadItem` in
/// `sortAndAnnotateThreadItems` (`state/queries/usePostThread/types.ts`), minus
/// the fields that only mean something to the tree presentation.
public struct ThreadConnector: Sendable, Hashable {
  /// How many indent levels sit to the left of this row.
  public let indent: Int
  /// Whether to draw a line up towards the parent.
  public let showParentReplyLine: Bool
  /// Whether to draw a line down towards rendered children.
  public let showChildReplyLine: Bool
  /// Whether this row is the last child of its branch, so the vertical line
  /// should terminate here.
  public let isLastChild: Bool
  /// Whether this row is the last of its siblings.
  public let isLastSibling: Bool
  /// This row's index among its siblings.
  public let replyIndex: Int
  /// Whether a "read more replies" row immediately follows because this row has
  /// unhydrated replies.
  public let precedesChildReadMore: Bool

  public init(
    indent: Int,
    showParentReplyLine: Bool,
    showChildReplyLine: Bool,
    isLastChild: Bool,
    isLastSibling: Bool,
    replyIndex: Int,
    precedesChildReadMore: Bool
  ) {
    self.indent = indent
    self.showParentReplyLine = showParentReplyLine
    self.showChildReplyLine = showChildReplyLine
    self.isLastChild = isLastChild
    self.isLastSibling = isLastSibling
    self.replyIndex = replyIndex
    self.precedesChildReadMore = precedesChildReadMore
  }
}

/// A hydrated post row.
public struct ThreadPostContent: Sendable {
  public let post: App.Bsky.FeedDefs_PostView
  /// The parsed `app.bsky.feed.post` record, when the opaque record decoded.
  public let record: App.Bsky.FeedPost?
  /// `#threadContext#rootAuthorLike` - the OP liked this reply.
  public let hasOPLike: Bool
  /// The moderation decision for this post, or `nil` when no options were
  /// supplied. Views read `.ui(.contentList)`/`.ui(.contentView)` off it for
  /// blur/interstitial/interaction decisions.
  public let moderation: ModerationDecision?

  /// Whether the viewer may reply to this post.
  public var replyDisabled: Bool {
    post.viewer?.replyDisabled == true
  }

  public init(
    post: App.Bsky.FeedDefs_PostView,
    record: App.Bsky.FeedPost?,
    hasOPLike: Bool,
    moderation: ModerationDecision?
  ) {
    self.post = post
    self.record = record
    self.hasOPLike = hasOPLike
    self.moderation = moderation
  }
}

/// A tombstone row.
public struct ThreadTombstone: Sendable {
  public let kind: ThreadTombstoneKind
  /// The post uri the tombstone stands in for.
  public let uri: String
  /// The depth of the row this tombstone replaces.
  public let depth: Int

  public init(kind: ThreadTombstoneKind, uri: String, depth: Int = 0) {
    self.kind = kind
    self.uri = uri
    self.depth = depth
  }
}

/// A "read more" row.
public struct ReadMoreContent: Sendable {
  public enum Direction: Sendable, Hashable {
    /// There are more parents above the top of the fetched chain.
    case up
    /// There are more replies below.
    case down
  }

  public let direction: Direction
  /// The uri the affordance should open to reveal the rest of the chain.
  public let href: String
  /// How many replies are known to be unhydrated, when the server said.
  public let moreReplies: Int?

  public init(direction: Direction, href: String, moreReplies: Int? = nil) {
    self.direction = direction
    self.href = href
    self.moreReplies = moreReplies
  }
}

/// Whether the thread has branching replies anywhere. RN uses this to decide
/// between the linear and tree presentations; a view that only supports the
/// linear reading can use it to skip the affordance entirely.
public enum ThreadShape: String, Sendable, Hashable {
  /// Every level has at most one reply, so the thread reads as one chain.
  case linear
  /// At least one level has two or more replies.
  case branching
}
