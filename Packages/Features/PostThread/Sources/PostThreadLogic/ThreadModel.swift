import Foundation
import Lexicons
import Moderation

/// The parsed thread tree.
///
/// Port of RN's `ThreadNode` union plus `responseToThreadNodes`
/// (`state/queries/post-thread.ts`), kept as a value tree so the flattening
/// pass is a pure function over it.
public indirect enum ThreadNode: Sendable {
  case post(ThreadPostNode)
  case tombstone(ThreadTombstone)

  /// The post uri, or the uri the tombstone stands in for.
  public var uri: String {
    switch self {
    case .post(let node): node.post.uri.rawValue
    case .tombstone(let tombstone): tombstone.uri
    }
  }

  /// The depth of the node in flattened space: 0 is the anchor, negative are
  /// parents, positive are replies.
  public var depth: Int {
    switch self {
    case .post(let node): node.depth
    case .tombstone(let tombstone): tombstone.depth
    }
  }
}

/// A hydrated post in the tree.
public struct ThreadPostNode: Sendable {
  public var post: App.Bsky.FeedDefs_PostView
  public var record: App.Bsky.FeedPost?
  /// `#threadContext#rootAuthorLike` - the OP liked this reply.
  public var hasOPLike: Bool
  /// The chain upwards, nearest parent first.
  public var parent: ThreadNode?
  public var replies: [ThreadNode]
  public var depth: Int
  public var isHighlighted: Bool
  /// Set when the node belongs to a self-thread (see ``ThreadTreeAnnotator``).
  public var isSelfThread: Bool = false
  /// Set on the deepest node of a self-thread that has unhydrated replies.
  public var hasMoreSelfThread: Bool = false
}

/// Builds a ``ThreadNode`` tree from a `getPostThread` response.
public enum ThreadTreeBuilder {
  /// Parses the response's root node.
  public static func build(output: App.Bsky.FeedGetPostThread_Output) -> ThreadNode {
    build(node: output.thread, depth: 0, direction: .start)
  }

  enum Direction {
    case up
    case down
    case start
  }

  static func build(
    node: App.Bsky.FeedGetPostThread_Output_Thread,
    depth: Int,
    direction: Direction
  ) -> ThreadNode {
    switch node {
    case .feedDefsThreadViewPost(let view):
      return buildPost(view, depth: depth, direction: direction)
    case .feedDefsBlockedPost(let blocked):
      return .tombstone(
        ThreadTombstone(kind: .blocked, uri: blocked.uri.rawValue, depth: depth))
    case .feedDefsNotFoundPost(let notFound):
      return .tombstone(
        ThreadTombstone(kind: .deleted, uri: notFound.uri.rawValue, depth: depth))
    case ._other:
      return .tombstone(
        ThreadTombstone(kind: .deleted, uri: "", depth: depth))
    }
  }

  static func buildPost(
    _ view: App.Bsky.FeedDefs_ThreadViewPost,
    depth: Int,
    direction: Direction
  ) -> ThreadNode {
    var post = view.post
    // These should normally be present. They are missing only for posts that
    // were *just* created; fill them in manually to compensate, as RN does.
    post.replyCount = post.replyCount ?? 0
    post.likeCount = post.likeCount ?? 0
    post.repostCount = post.repostCount ?? 0

    let record = post.record.postRecord
    let hasOPLike = view.threadContext?.rootAuthorLike != nil

    let parent: ThreadNode? =
      (view.parent != nil && direction != .down)
      ? build(parent: view.parent!, depth: depth - 1)
      : nil

    var replies: [ThreadNode] = []
    if let wireReplies = view.replies, direction != .up {
      for reply in wireReplies {
        replies.append(build(reply: reply, depth: depth + 1))
      }
    }

    return .post(
      ThreadPostNode(
        post: post,
        record: record,
        hasOPLike: hasOPLike,
        parent: parent,
        replies: replies,
        depth: depth,
        isHighlighted: depth == 0
      ))
  }

  static func build(parent: App.Bsky.FeedDefs_ThreadViewPost_Parent, depth: Int) -> ThreadNode {
    switch parent {
    case .feedDefsThreadViewPost(let view):
      return buildPost(view, depth: depth, direction: .up)
    case .feedDefsBlockedPost(let blocked):
      return .tombstone(
        ThreadTombstone(kind: .blocked, uri: blocked.uri.rawValue, depth: depth))
    case .feedDefsNotFoundPost(let notFound):
      return .tombstone(
        ThreadTombstone(kind: .deleted, uri: notFound.uri.rawValue, depth: depth))
    case ._other:
      return .tombstone(ThreadTombstone(kind: .deleted, uri: "", depth: depth))
    }
  }

  static func build(reply: App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem, depth: Int) -> ThreadNode {
    switch reply {
    case .feedDefsThreadViewPost(let view):
      return buildPost(view, depth: depth, direction: .down)
    case .feedDefsBlockedPost(let blocked):
      return .tombstone(
        ThreadTombstone(kind: .blocked, uri: blocked.uri.rawValue, depth: depth))
    case .feedDefsNotFoundPost(let notFound):
      return .tombstone(
        ThreadTombstone(kind: .deleted, uri: notFound.uri.rawValue, depth: depth))
    case ._other:
      return .tombstone(ThreadTombstone(kind: .deleted, uri: "", depth: depth))
    }
  }
}

/// Marks the viewer's own continuous chain of posts in a thread.
///
/// Port of RN's `annotateSelfThread`. A post is part of a self-thread when every
/// ancestor shares the anchor author's DID. The walk stops at the first
/// ancestor that breaks the chain, and it follows a single reply chain
/// downwards (at most `REPLY_TREE_DEPTH` hops) to flag the segment too.
public enum ThreadTreeAnnotator {
  /// The maximum number of hops down RN follows when marking a self-thread.
  /// Matches the request depth: past this the replies are not hydrated anyway.
  public static let maxSelfThreadDepth = PostThreadParams.replyTreeDepth

  /// Returns a copy of `tree` with self-thread flags applied.
  public static func annotate(_ tree: ThreadNode) -> ThreadNode {
    guard case .post(let anchor) = tree else { return tree }

    let anchorDid = anchor.post.author.did.rawValue
    var selfThreadUris: [String] = [anchor.post.uri.rawValue]

    // Walk up: every ancestor must be the same author.
    var parent = anchor.parent
    while let node = parent {
      guard case .post(let postNode) = node,
        postNode.post.author.did.rawValue == anchorDid
      else {
        // Not a self-thread.
        return tree
      }
      selfThreadUris.insert(postNode.post.uri.rawValue, at: 0)
      parent = postNode.parent
    }

    // Walk down: one reply chain, max depth hops.
    var deepest = anchor
    for _ in 0..<maxSelfThreadDepth {
      guard
        let reply = deepest.replies.first(where: {
          if case .post(let node) = $0 {
            return node.post.author.did.rawValue == anchorDid
          }
          return false
        }),
        case .post(let replyNode) = reply
      else { break }
      selfThreadUris.append(replyNode.post.uri.rawValue)
      deepest = replyNode
    }

    guard selfThreadUris.count > 1 else { return tree }

    var result = tree
    markSelfThread(in: &result, uris: Set(selfThreadUris))

    // RN sets `hasMoreSelfThread` on the deepest node when it sits at the tree
    // depth limit with replies it could not hydrate.
    let atDepthLimit = deepest.depth == maxSelfThreadDepth
    let hasUnhydrated = (deepest.post.replyCount ?? 0) > 0 && deepest.replies.isEmpty
    if deepest.post.uri.rawValue == selfThreadUris.last, atDepthLimit, hasUnhydrated {
      setHasMoreSelfThread(in: &result, uri: deepest.post.uri.rawValue, value: true)
    }

    return result
  }

  private static func markSelfThread(in node: inout ThreadNode, uris: Set<String>) {
    guard case .post(var postNode) = node else { return }
    if uris.contains(postNode.post.uri.rawValue) {
      postNode.isSelfThread = true
    }
    for index in postNode.replies.indices {
      markSelfThread(in: &postNode.replies[index], uris: uris)
    }
    node = .post(postNode)
  }

  private static func setHasMoreSelfThread(in node: inout ThreadNode, uri: String, value: Bool) {
    guard case .post(var postNode) = node else { return }
    if postNode.post.uri.rawValue == uri {
      postNode.hasMoreSelfThread = value
    }
    for index in postNode.replies.indices {
      setHasMoreSelfThread(in: &postNode.replies[index], uri: uri, value: value)
    }
    node = .post(postNode)
  }
}

/// Sorts every reply list in the tree, bottom-up.
///
/// Port of the recursive `sortThread` walk. The comparator is rebuilt per parent
/// because its OP check compares against that parent's author.
public enum ThreadTreeSorter {
  public static func sort(
    _ tree: ThreadNode,
    order: ThreadSortOrder,
    inputs: ThreadSortInputs
  ) -> ThreadNode {
    guard case .post(var node) = tree else { return tree }

    let comparator = ThreadReplyComparator(
      parentAuthorDid: node.post.author.did.rawValue,
      inputs: inputs,
      order: order
    )

    // Children are sorted before this level, so the whole tree is in order no
    // matter which level the caller inspects.
    node.replies = node.replies.map { sort($0, order: order, inputs: inputs) }
    node.replies.sort { comparator.sortsBefore($0, $1) }

    return .post(node)
  }
}

/// Thread shape detection.
extension ThreadShape {
  /// Whether the thread branches anywhere.
  ///
  /// Port of RN's `hasBranchingReplies`: a level with more than one reply
  /// branches; a level with exactly one reply defers to that reply. A thread
  /// with no replies is linear.
  public static func of(_ tree: ThreadNode) -> ThreadShape {
    guard case .post(let node) = tree else { return .linear }
    return hasBranching(node) ? .branching : .linear
  }

  static func hasBranching(_ node: ThreadPostNode) -> Bool {
    guard !node.replies.isEmpty else { return false }
    if node.replies.count > 1 { return true }
    if case .post(let only) = node.replies[0] {
      return hasBranching(only)
    }
    return false
  }
}
