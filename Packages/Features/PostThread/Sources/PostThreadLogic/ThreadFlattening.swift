import Foundation
import Lexicons
import Moderation

/// The result of flattening a thread tree.
public struct FlattenedThread: Sendable {
  /// The linear rows, in render order.
  public var items: [ThreadItem]
  /// Whether the thread branches anywhere (drives tree-vs-linear presentation).
  public var shape: ThreadShape
  /// Whether any reply was withheld from the inline list because moderation
  /// hid it. RN renders these behind a "show other replies" affordance rather
  /// than dropping them silently.
  public var hasOtherReplies: Bool
  /// The rows moderation moved out of the inline list.
  public var otherItems: [ThreadItem]

  public init(
    items: [ThreadItem],
    shape: ThreadShape = .linear,
    hasOtherReplies: Bool = false,
    otherItems: [ThreadItem] = []
  ) {
    self.items = items
    self.shape = shape
    self.hasOtherReplies = hasOtherReplies
    self.otherItems = otherItems
  }
}

/// The options a flatten controls.
public struct ThreadFlattenOptions: Sendable {
  /// Whether the viewer is signed in. Drives the unauthenticated-PWI skip and
  /// whether tombstones for hidden posts are emitted.
  public var hasSession: Bool
  /// Moderation options. When `nil`, no post is hidden by moderation and no
  /// decision is attached to the rows.
  public var moderationOpts: ModerationOpts?
  /// Urls hidden by the threadgate record.
  public var threadgateHiddenReplies: Set<String>
  /// Skip moderation-driven bucketing, so every row lands inline in tree order.
  /// Used for the server's "other replies" fetch, whose items are already
  /// filtered.
  public var skipModerationHandling: Bool
  /// The fetch generation stamp, recorded on every post row for the comparator.
  public var fetchedAt: Int

  public init(
    hasSession: Bool = false,
    moderationOpts: ModerationOpts? = nil,
    threadgateHiddenReplies: Set<String> = [],
    skipModerationHandling: Bool = false,
    fetchedAt: Int = 0
  ) {
    self.hasSession = hasSession
    self.moderationOpts = moderationOpts
    self.threadgateHiddenReplies = threadgateHiddenReplies
    self.skipModerationHandling = skipModerationHandling
    self.fetchedAt = fetchedAt
  }
}

/// Flattens a thread tree into the linear row list a view renders.
///
/// The model, in words:
///
/// - The anchor sits at depth 0. Its ancestor chain is emitted first, top-down,
///   with depths `-n ... -1`, so the reader scrolls backwards into context and
///   lands on the anchor.
/// - Replies are emitted depth-first from the anchor, parents immediately
///   before their children. A reply's depth is its distance from the anchor, so
///   a view draws `depth` indent lines to the left of the row.
/// - Each row carries the connector state it needs (`showParentReplyLine`,
///   `showChildReplyLine`, `indent`, `isLastChild`), computed in a second pass
///   once sibling counts are known. This is the same two-pass shape as RN's
///   traversal: collect first, then annotate.
/// - A branch the server refused to hydrate becomes a tombstone at its depth,
///   and its subtree (which the server did not send) is simply absent. Blocked
///   replies are dropped from the list entirely, matching RN's
///   `filter(node => node.type !== 'blocked')` in `responseToThreadNodes`.
/// - Unhydrated replies - a post whose `replyCount` exceeds the replies the
///   server sent - produce a "read more" row after the last child of that
///   branch, which is how RN signals "there is more here".
/// - A reply-chain that is entirely the viewer's own author is a self-thread;
///   the deepest node with unhydrated replies gets the self-thread "read more"
///   treatment.
public enum ThreadFlattener {
  /// Flattens `tree`.
  public static func flatten(
    _ tree: ThreadNode,
    options: ThreadFlattenOptions = ThreadFlattenOptions()
  ) -> FlattenedThread {
    guard case .post(let anchor) = tree else {
      guard case .tombstone(let tombstone) = tree else {
        return FlattenedThread(items: [])
      }
      // The anchor itself is unavailable; emit just its tombstone.
      return FlattenedThread(
        items: [row(for: tombstone, connector: nil)])
    }

    var parents: [ThreadNode] = []
    collectParents(anchor.parent, into: &parents)

    let walk = Walk(options: options)

    for node in parents {
      walk.append(node, siblingIndex: 0, siblingCount: 1)
    }

    walk.append(.post(anchor), siblingIndex: 0, siblingCount: 1)

    let annotated = annotate(walk.items, metadata: walk.metadata, options: options)
    let annotatedOthers = annotate(walk.others, metadata: walk.metadata, options: options)

    return FlattenedThread(
      items: annotated,
      shape: ThreadShape.of(tree),
      hasOtherReplies: !annotatedOthers.isEmpty,
      otherItems: annotatedOthers
    )
  }

  // MARK: - Collection

  /// Walks the ancestor chain into top-down order.
  static func collectParents(_ node: ThreadNode?, into out: inout [ThreadNode]) {
    guard let node else { return }
    if case .post(let postNode) = node {
      collectParents(postNode.parent, into: &out)
    }
    out.append(node)
  }

  /// Accumulates rows, the other bucket and per-row metadata as the tree is
  /// walked. A reference type so the recursive appends do not need to thread
  /// four `inout` parameters through every call.
  private final class Walk {
    let options: ThreadFlattenOptions
    var items: [ThreadItem] = []
    var others: [ThreadItem] = []
    var metadata: [String: RowMetadata] = [:]

    init(options: ThreadFlattenOptions) {
      self.options = options
    }

    /// Appends a node and, for posts, its subtree.
    func append(_ node: ThreadNode, siblingIndex: Int, siblingCount: Int) {
      switch node {
      case .tombstone(let tombstone):
        // Blocked replies are dropped from the inline list, as RN does.
        if tombstone.kind == .blocked && tombstone.depth > 0 {
          return
        }
        items.append(ThreadFlattener.row(for: tombstone, connector: nil))
      case .post(let postNode):
        appendPost(postNode, siblingIndex: siblingIndex, siblingCount: siblingCount)
      }
    }

    private func appendPost(
      _ node: ThreadPostNode, siblingIndex: Int, siblingCount: Int
    ) {
      if !options.hasSession && ThreadFlattener.hasPWIOptOut(node) {
        return
      }

      let content = ThreadFlattener.postContent(node, options: options)
      let blurred =
        !options.skipModerationHandling
        && ThreadPlaceholder.isHiddenByModeration(content.moderation)

      let item = ThreadItem(
        id: node.post.uri.rawValue,
        uri: node.post.uri.rawValue,
        depth: node.depth,
        isAnchor: node.isHighlighted,
        content: .post(content)
      )

      let unhydrated = ThreadFlattener.unhydratedCount(node)
      metadata[node.post.uri.rawValue] = RowMetadata(
        depth: node.depth,
        siblingIndex: siblingIndex,
        siblingCount: siblingCount,
        repliesCount: node.post.replyCount ?? 0,
        repliesUnhydrated: unhydrated,
        isModerated: blurred
      )

      if blurred && !options.skipModerationHandling {
        // A hydrated post the viewer's settings hide is bucketed when it is a
        // top-level reply; deeper ones are dropped with their subtree, exactly
        // as RN's traversal does.
        if node.depth <= 1 {
          others.append(item)
        }
        return
      }

      items.append(item)

      let siblings = node.replies
      for (index, reply) in siblings.enumerated() {
        append(reply, siblingIndex: index, siblingCount: siblings.count)
      }

      // A branch with unhydrated replies gets a "read more" immediately after
      // its last rendered descendant.
      if unhydrated > 0 {
        items.append(
          ThreadFlattener.readMoreRow(
            depth: node.depth, uri: node.post.uri.rawValue, unhydrated: unhydrated))
      }
    }
  }

  static func row(for tombstone: ThreadTombstone, connector: ThreadConnector?) -> ThreadItem {
    ThreadItem(
      id: "\(tombstone.kind.rawValue):\(tombstone.uri)",
      uri: tombstone.uri,
      depth: tombstone.depth,
      isAnchor: tombstone.depth == 0,
      content: .tombstone(tombstone),
      connector: connector
    )
  }

  static func readMoreRow(depth: Int, uri: String, unhydrated: Int) -> ThreadItem {
    ThreadItem(
      id: "readMore:\(uri)",
      uri: uri,
      depth: depth + 1,
      isAnchor: false,
      content: .readMore(
        ReadMoreContent(direction: .down, href: uri, moreReplies: unhydrated)),
      connector: nil
    )
  }

  static func postContent(
    _ node: ThreadPostNode,
    options: ThreadFlattenOptions
  ) -> ThreadPostContent {
    let decision = options.moderationOpts.map {
      PostModerationAdapter.moderate(node.post, opts: $0)
    }
    return ThreadPostContent(
      post: node.post,
      record: node.record,
      hasOPLike: node.hasOPLike,
      moderation: decision
    )
  }

  /// The number of replies the server said exist but did not send.
  ///
  /// RN derives this from the newer API's explicit `moreReplies`, and from
  /// `replyCount` minus hydrated children in the tree API. The tree response
  /// carries no `moreReplies`, so the difference is the signal.
  static func unhydratedCount(_ node: ThreadPostNode) -> Int {
    let total = node.post.replyCount ?? 0
    let hydrated = node.replies.count
    return max(0, total - hydrated)
  }

  /// The `!no-unauthenticated` opt-out label, which RN honours only when
  /// logged out.
  static func hasPWIOptOut(_ node: ThreadPostNode) -> Bool {
    node.post.author.labels?.contains { $0.val == "!no-unauthenticated" } ?? false
  }

  // MARK: - Connector annotation

  /// Second pass: fills in the connector state each row needs, now that sibling
  /// counts and the surrounding rows are known.
  ///
  /// Port of the per-item UI computation in RN's traversal. A row shows a line
  /// up to its parent when the row above is its parent (a lower depth), and a
  /// line down to children when the row has replies rendered beneath it.
  static func annotate(
    _ items: [ThreadItem],
    metadata: [String: RowMetadata],
    options: ThreadFlattenOptions
  ) -> [ThreadItem] {
    var out: [ThreadItem] = []
    out.reserveCapacity(items.count)

    for (index, item) in items.enumerated() {
      guard case .post(let content) = item.content,
        let meta = metadata[item.uri]
      else {
        out.append(item)
        continue
      }

      let previousDepth = previousPostDepth(in: items, before: index)
      let nextDepth = nextPostDepth(in: items, after: index)

      // A reply is the last child of its branch when the next row is at or
      // above its own depth (a sibling or a shallower post), or there is no
      // next row at all.
      let isLastChild = nextDepth == nil || nextDepth! <= meta.depth

      // A reply has a line down to its children when it is a parent at all
      // (depth < 0, i.e. an ancestor with rendered children) or it has replies
      // that were actually rendered beneath it.
      let hasRenderedReplies = meta.repliesCount > 0 && !isLastChild
      let showChildReplyLine = meta.depth < 0 || hasRenderedReplies

      // A line up to the parent when the row above is this row's parent: it is
      // shallower than this row. The anchor (depth 0) never shows one.
      let showParentReplyLine: Bool
      if let previous = previousDepth {
        showParentReplyLine = previous != 0 && previous < meta.depth
      } else {
        showParentReplyLine = false
      }

      let connector = ThreadConnector(
        indent: max(0, meta.depth),
        showParentReplyLine: showParentReplyLine,
        showChildReplyLine: showChildReplyLine,
        isLastChild: isLastChild,
        isLastSibling: meta.siblingIndex == meta.siblingCount - 1,
        replyIndex: meta.siblingIndex,
        precedesChildReadMore: meta.repliesUnhydrated > 0 && isLastChild
      )

      _ = content
      out.append(item.withConnector(connector))
    }

    return out
  }

  /// The depth of the nearest preceding post row, skipping synthetic rows.
  static func previousPostDepth(in items: [ThreadItem], before index: Int) -> Int? {
    guard index > 0 else { return nil }
    for i in stride(from: index - 1, through: 0, by: -1) {
      if case .post = items[i].content { return items[i].depth }
    }
    return nil
  }

  /// The depth of the nearest following post row, skipping synthetic rows.
  static func nextPostDepth(in items: [ThreadItem], after index: Int) -> Int? {
    guard index + 1 < items.count else { return nil }
    for i in (index + 1)..<items.count {
      if case .post = items[i].content { return items[i].depth }
    }
    return nil
  }

  /// Per-row facts collected during the walk, used to compute connectors.
  struct RowMetadata: Sendable {
    var depth: Int
    var siblingIndex: Int
    var siblingCount: Int
    var repliesCount: Int
    var repliesUnhydrated: Int
    var isModerated: Bool
  }

}
