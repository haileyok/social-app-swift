import Foundation

/// A scroll observation for one item, as the list reports it.
///
/// This is the Swift form of the `ViewToken` entries RN's `onViewableItemsChanged`
/// receives: an index and the fraction of the item that is on screen.
public struct VideoViewportEntry: Sendable, Equatable {
  /// The item's index in the pager.
  public let index: Int
  /// The fraction of the item visible, `0...1`.
  public let visibleFraction: Double
  /// How long the item has been continuously visible, in seconds.
  public let visibleDuration: TimeInterval

  public init(index: Int, visibleFraction: Double, visibleDuration: TimeInterval = 0) {
    self.index = index
    self.visibleFraction = visibleFraction
    self.visibleDuration = visibleDuration
  }

  /// The percent form RN's config uses.
  public var visiblePercent: Double { visibleFraction * 100 }
}

/// One item's computed viewability, as data.
public struct VideoViewability: Sendable, Equatable {
  /// The item's index.
  public let index: Int
  /// The item's identity in the pager.
  public let id: String
  /// Whether the item satisfies the viewability config.
  public let isViewable: Bool
  /// Whether the item is the active (playing) item.
  public let isActive: Bool
  /// Whether the item is inside the preload window.
  public let isPreloaded: Bool
  /// Whether the item is adjacent to the active item, i.e. one swipe away.
  public let isAdjacent: Bool

  public init(
    index: Int,
    id: String,
    isViewable: Bool,
    isActive: Bool,
    isPreloaded: Bool,
    isAdjacent: Bool
  ) {
    self.index = index
    self.id = id
    self.isViewable = isViewable
    self.isActive = isActive
    self.isPreloaded = isPreloaded
    self.isAdjacent = isAdjacent
  }
}

/// The viewability config an item must satisfy to become active.
///
/// Port of RN's immersive-feed config:
///
/// ```js
/// { itemVisiblePercentThreshold: 100, minimumViewTime: 0 }
/// ```
///
/// The default in RN's shared `List` is `40` percent / `500` ms, and the video
/// feed deliberately overrides both: only a fully-covered item plays, and it
/// plays immediately.
public struct VideoViewabilityConfig: Sendable, Equatable {
  /// The visible-fraction percent (0-100) an item must reach.
  public var itemVisiblePercentThreshold: Double
  /// How long it must hold that fraction before counting, in seconds.
  public var minimumViewTime: TimeInterval

  public init(
    itemVisiblePercentThreshold: Double = Double(
      VideoFeedConstants.itemVisiblePercentThreshold),
    minimumViewTime: TimeInterval = VideoFeedConstants.minimumViewTime
  ) {
    self.itemVisiblePercentThreshold = itemVisiblePercentThreshold
    self.minimumViewTime = minimumViewTime
  }

  /// RN's immersive video config.
  public static let immersive = VideoViewabilityConfig()

  /// Whether `entry` satisfies this config. RN compares
  /// `visiblePercent >= threshold` and `visibleDuration >= minimumViewTime`.
  public func isViewable(_ entry: VideoViewportEntry) -> Bool {
    entry.visiblePercent >= itemVisiblePercentThreshold
      && entry.visibleDuration >= minimumViewTime
  }
}

/// The pager's state after a scroll observation.
///
/// Pure data: no player, no scroll view. The Views package renders from this and
/// feeds scroll events back in.
public struct VideoPagerState: Sendable, Equatable {
  /// Every item's identity, in order.
  public let itemIDs: [String]
  /// The active item's index, or `nil` when nothing is viewable.
  public let activeIndex: Int?
  /// The indices inside the preload window, always including the active one.
  public let preloadIndices: [Int]
  /// Per-index viewability, in item order.
  public let viewability: [VideoViewability]
  /// The indices that changed state in the transition that produced this value.
  public let changedIndices: [Int]

  public init(
    itemIDs: [String],
    activeIndex: Int?,
    preloadIndices: [Int],
    viewability: [VideoViewability],
    changedIndices: [Int] = []
  ) {
    self.itemIDs = itemIDs
    self.activeIndex = activeIndex
    self.preloadIndices = preloadIndices
    self.viewability = viewability
    self.changedIndices = changedIndices
  }

  /// The active item's identity, when there is one.
  public var activeID: String? {
    guard let activeIndex, itemIDs.indices.contains(activeIndex) else { return nil }
    return itemIDs[activeIndex]
  }

  /// Whether `index` is the active item.
  public func isActive(_ index: Int) -> Bool { activeIndex == index }

  /// The identities of the items to preload, in order.
  public var preloadIDs: [String] {
    preloadIndices.compactMap { itemIDs.indices.contains($0) ? itemIDs[$0] : nil }
  }

  /// The identities of the items adjacent to the active one (one swipe each
  /// way). RN uses this to decide which adjacent items get a rendered player on
  /// iOS (`shouldRenderVideo = active || ios(adjacent)`).
  public var adjacentIDs: [String] {
    guard let activeIndex else { return [] }
    return adjacentIndices(to: activeIndex, count: itemIDs.count).compactMap {
      itemIDs.indices.contains($0) ? itemIDs[$0] : nil
    }
  }

  /// A transition in which nothing changed.
  public static func empty(index: Int? = nil) -> VideoPagerState {
    VideoPagerState(itemIDs: [], activeIndex: index, preloadIndices: [], viewability: [])
  }
}

/// Computes the indices within `radius` of `index`, clamped to `count`.
///
/// The window is symmetric and includes `index` itself, matching RN's
/// `index - 1`, `index`, `index + 1` player assignment. Order is ascending, so
/// callers can zip it against the item list directly.
public func preloadWindow(
  around index: Int,
  count: Int,
  radius: Int = VideoFeedConstants.preloadRadius
) -> [Int] {
  // `index < count` implies a non-empty list, which is what makes the window
  // well-defined.
  guard index >= 0, index < count else { return [] }
  let lower = max(0, index - max(0, radius))
  let upper = min(count - 1, index + max(0, radius))
  return Array(lower...upper)
}

/// The indices immediately before and after `index`, clamped to `count`.
///
/// This is ``preloadWindow(around:count:radius:)`` with `radius: 1` minus the
/// index itself.
public func adjacentIndices(to index: Int, count: Int) -> [Int] {
  guard index >= 0, index < count else { return [] }
  return [index - 1, index + 1].filter { $0 >= 0 && $0 < count }
}

/// The index of the item the RN player pool would assign for `index`.
///
/// RN recycles three players by `index % 3`, so this is the slot identity the
/// Views layer needs to know whether it must swap a player's source. Exposed
/// here as plain arithmetic so it is testable without a player.
public func playerPoolSlot(
  for index: Int, poolSize: Int = VideoFeedConstants.playerPoolSize
) -> Int {
  guard poolSize > 0 else { return 0 }
  return ((index % poolSize) + poolSize) % poolSize
}

/// The three pool slots the active index needs, as a source-assignment map.
///
/// Port of the slot arithmetic in `updateVideoState`: the previous item takes
/// `(index + 2) % 3`, the current takes `index % 3`, the next takes
/// `(index + 1) % 3`. Returned as slot -> item index so a caller can reconcile a
/// player pool without re-deriving the offsets.
public func playerSlotAssignments(
  activeIndex: Int,
  count: Int,
  poolSize: Int = VideoFeedConstants.playerPoolSize
) -> [Int: Int] {
  guard activeIndex >= 0, activeIndex < count, poolSize >= 1 else { return [:] }
  var assignments: [Int: Int] = [:]
  let offsets: [(slotOffset: Int, itemOffset: Int)] = [
    (poolSize - 1, -1), (0, 0), (1, 1),
  ]
  for entry in offsets {
    let itemIndex = activeIndex + entry.itemOffset
    guard itemIndex >= 0, itemIndex < count else { continue }
    assignments[playerPoolSlot(for: activeIndex + entry.slotOffset, poolSize: poolSize)] =
      itemIndex
  }
  return assignments
}
