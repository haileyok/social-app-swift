import Foundation

/// The row that terminates a windowed list, telling the view there is more to
/// reveal.
///
/// Port of RN's `LOAD_MORE` sentinel in `PostThread.tsx`, which is pushed onto
/// the row array in place of the truncated tail.
public struct ShowMoreWindow: Sendable {
  /// The rows to render, after truncation.
  public var visible: [ThreadItem]
  /// How many rows were withheld from the tail.
  public var hiddenCount: Int
  /// True when a "load more" row should be appended after `visible`.
  public var showsLoadMore: Bool

  public init(visible: [ThreadItem], hiddenCount: Int, showsLoadMore: Bool) {
    self.visible = visible
    self.hiddenCount = hiddenCount
    self.showsLoadMore = showsLoadMore
  }
}

/// Collapse/expand logic for long threads.
///
/// RN has two independent windows (`PostThread.tsx`, commit `c5641ac2b`):
///
/// - **parents**, revealed in chunks of `PARENTS_CHUNK_SIZE = 15` via
///   `maxParents`. The screen keeps only the *last* `maxParents` ancestors, so
///   the anchor stays adjacent to its immediate parent and older context is
///   what gets withheld. Revealing more grows the window by one chunk.
/// - **replies**, capped at `maxReplies = 100` rows. Past the cap a single
///   `LOAD_MORE` row is appended.
///
/// The gating reason RN gives for both is the same: `FlatList` misbehaves when
/// a large number of rows are prepended at once. The window is therefore a
/// rendering concern, but the *rule* is data, which is what this type captures.
public struct ThreadShowMore: Sendable {
  /// RN's parent reveal chunk. "FlatList maintainVisibleContentPosition breaks
  /// if too many items are prepended."
  public static let defaultParentsChunkSize = 15
  /// RN's reply cap before the `LOAD_MORE` row.
  public static let defaultMaxReplies = 100

  public var parentsChunkSize: Int
  public var maxReplies: Int
  /// How many parents are currently revealed.
  public var maxParents: Int

  public init(
    parentsChunkSize: Int = ThreadShowMore.defaultParentsChunkSize,
    maxReplies: Int = ThreadShowMore.defaultMaxReplies,
    maxParents: Int = 0
  ) {
    self.parentsChunkSize = parentsChunkSize
    self.maxReplies = maxReplies
    self.maxParents = maxParents
  }

  /// The initial window: one chunk of parents, and the reply cap.
  public static func initial() -> ThreadShowMore {
    ThreadShowMore(maxParents: ThreadShowMore.defaultParentsChunkSize)
  }

  // MARK: - Windows

  /// Splits a flattened thread into the parent chain, the anchor, and the
  /// replies, applying both windows.
  ///
  /// Mirrors RN's array construction order: the visible parents, then the
  /// anchor, then the visible replies (with a load-more row when truncated).
  public func window(_ thread: FlattenedThread) -> [ThreadItem] {
    guard let anchorIndex = thread.items.firstIndex(where: \.isAnchor) else {
      // No anchor (it was a tombstone): window the whole list by reply cap.
      return truncateReplies(thread.items)
    }

    let parents = Array(thread.items[..<anchorIndex])
    let anchor = thread.items[anchorIndex]
    let replies = Array(thread.items[(anchorIndex + 1)...])

    // Keep the *last* `maxParents` ancestors, as RN does: the anchor's nearest
    // parent is always shown and the far past is what gets withheld.
    let visibleParents: [ThreadItem]
    if parents.count <= maxParents {
      visibleParents = parents
    } else {
      visibleParents = Array(parents.suffix(maxParents))
    }

    var out: [ThreadItem] = []
    // RN inserts a "read more up" affordance above the window when parents were
    // withheld, so the user knows the chain continues. It is a data row here.
    if visibleParents.count < parents.count {
      out.append(parentChainReadMore(withheld: parents.count - visibleParents.count, parents: parents))
    }
    out.append(contentsOf: visibleParents)
    out.append(anchor)
    out.append(contentsOf: truncateReplies(replies))
    return out
  }

  /// A "read more" row standing in for the parents that were withheld by the
  /// window.
  func parentChainReadMore(withheld: Int, parents: [ThreadItem]) -> ThreadItem {
    // Point at the oldest withheld parent, which is where revealing more starts.
    let target = parents.first?.uri ?? ""
    return ThreadItem(
      id: "readMoreUp:\(target)",
      uri: target,
      depth: -(withheld),
      isAnchor: false,
      content: .readMore(
        ReadMoreContent(direction: .up, href: target, moreReplies: withheld)),
      connector: nil
    )
  }

  /// Applies the reply cap, appending a load-more row when rows were withheld.
  func truncateReplies(_ replies: [ThreadItem]) -> [ThreadItem] {
    guard replies.count > maxReplies else { return replies }
    var out = Array(replies.prefix(maxReplies))
    out.append(
      ThreadItem(
        id: "showMore",
        uri: "",
        depth: 0,
        isAnchor: false,
        content: .showMore,
        connector: nil
      ))
    return out
  }

  // MARK: - Expansion

  /// Grows the parent window by one chunk. Returns a new value; callers drive
  /// this from a scroll-against-the-top signal or an explicit affordance.
  public func revealingMoreParents() -> ThreadShowMore {
    var copy = self
    copy.maxParents += parentsChunkSize
    return copy
  }

  /// Grows the reply window by one cap, for the `LOAD_MORE` row's action.
  public func revealingMoreReplies() -> ThreadShowMore {
    var copy = self
    copy.maxReplies += maxReplies
    return copy
  }

  /// Whether another parent chunk is available given the total parent count.
  public func hasMoreParents(totalParents: Int) -> Bool {
    maxParents < totalParents
  }
}

/// The windowed view of a thread, plus the actions to widen it.
///
/// RN keeps `maxParents`/`maxReplies` in component state and nudges them from
/// scroll events. This value type holds the same state so a view target can
/// own the trigger and the logic stays testable.
public struct ThreadWindow: Sendable {
  public var showMore: ThreadShowMore
  public private(set) var thread: FlattenedThread

  public init(thread: FlattenedThread, showMore: ThreadShowMore = .initial()) {
    self.thread = thread
    self.showMore = showMore
  }

  /// The rows to render right now.
  public var items: [ThreadItem] {
    showMore.window(thread)
  }

  /// Whether there are parents beyond the current window.
  public var hasMoreParents: Bool {
    let total = thread.items.prefix { !$0.isAnchor }.count
    return showMore.hasMoreParents(totalParents: total)
  }

  /// Reveals one more chunk of parents.
  public mutating func revealMoreParents() {
    showMore = showMore.revealingMoreParents()
  }

  /// Reveals one more chunk of replies.
  public mutating func revealMoreReplies() {
    showMore = showMore.revealingMoreReplies()
  }

  /// Replaces the underlying thread, keeping the window. Used after a refetch.
  public mutating func update(thread: FlattenedThread) {
    self.thread = thread
  }
}
