import Foundation
import Lexicons
import Moderation

/// Turns the server's unavailable-branch markers and the viewer's moderation
/// decision into a single tombstone kind.
///
/// RN has two sources for this:
///
/// 1. the wire, where a node is `#notFoundPost` or `#blockedPost`
///    (`responseToThreadNodes` returns a `not-found` / `blocked` node, and the
///    tree builder drops blocked replies from the list entirely);
/// 2. moderation, where a hydrated post's decision blurs it in the content
///    list, which the newer traversal uses to move the post into a separate
///    "other replies" bucket rather than render it inline.
///
/// The data layer reports both through ``ThreadTombstoneKind`` and leaves the
/// presentation choice (drop, blur, or bucket) to the view.
public enum ThreadPlaceholder {
  /// The tombstone for a wire node, or `nil` when the node is a readable post.
  public static func tombstone(
    for node: App.Bsky.FeedDefs_ThreadViewPost_Parent
  ) -> ThreadTombstone? {
    switch node {
    case .feedDefsNotFoundPost(let post):
      return ThreadTombstone(kind: .deleted, uri: post.uri.rawValue)
    case .feedDefsBlockedPost(let post):
      return ThreadTombstone(kind: .blocked, uri: post.uri.rawValue)
    case .feedDefsThreadViewPost, ._other:
      return nil
    }
  }

  /// The tombstone for a reply-position node.
  public static func tombstone(
    for node: App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem
  ) -> ThreadTombstone? {
    switch node {
    case .feedDefsNotFoundPost(let post):
      return ThreadTombstone(kind: .deleted, uri: post.uri.rawValue)
    case .feedDefsBlockedPost(let post):
      return ThreadTombstone(kind: .blocked, uri: post.uri.rawValue)
    case .feedDefsThreadViewPost, ._other:
      return nil
    }
  }

  /// The tombstone for the response's root node.
  public static func tombstone(
    for node: App.Bsky.FeedGetPostThread_Output_Thread
  ) -> ThreadTombstone? {
    switch node {
    case .feedDefsNotFoundPost(let post):
      return ThreadTombstone(kind: .deleted, uri: post.uri.rawValue)
    case .feedDefsBlockedPost(let post):
      return ThreadTombstone(kind: .blocked, uri: post.uri.rawValue)
    case .feedDefsThreadViewPost, ._other:
      return nil
    }
  }

  /// Whether a hydrated post should be hidden from the inline thread.
  ///
  /// Port of the RN check that reads
  /// `modCache.get(node)?.ui('contentList').blur` in the comparator and
  /// `childPost.isBlurred` in the newer traversal. Returns `false` when no
  /// decision is available, so a caller without moderation options still gets
  /// the full thread.
  public static func isHiddenByModeration(_ decision: ModerationDecision?) -> Bool {
    decision?.ui(.contentList).blur == true
  }

  /// The tombstone a moderated-out post maps to, given its uri.
  public static func moderationTombstone(uri: String) -> ThreadTombstone {
    ThreadTombstone(kind: .hiddenByModeration, uri: uri)
  }
}
