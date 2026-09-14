import Foundation

/// The pager's viewability state machine.
///
/// Port of the `onViewableItemsChanged` handler in
/// `src/screens/VideoFeed/index.tsx`, made pure. RN's handler does two things
/// when the viewable set changes:
///
/// 1. takes `viewableItems[0].index` as the new index (the first viewable entry,
///    which with a 100-percent threshold is the fully-covered item);
/// 2. calls `updateVideoState(newIndex)` to reassign the three pooled players.
///
/// Keeping the machine free of players and scroll views means the transitions -
/// which item is active, which are preloaded, what changed - are directly
/// assertable.
public struct VideoPagerStateMachine: Sendable {
  /// The identities in the pager, in order.
  public private(set) var itemIDs: [String]
  /// The viewability config.
  public var config: VideoViewabilityConfig
  /// The preload radius.
  public var preloadRadius: Int
  /// The active index, or `nil` before the first observation.
  public private(set) var activeIndex: Int?

  /// Creates a machine over an ordered list of item identities.
  public init(
    itemIDs: [String] = [],
    config: VideoViewabilityConfig = .immersive,
    preloadRadius: Int = VideoFeedConstants.preloadRadius
  ) {
    self.itemIDs = itemIDs
    self.config = config
    self.preloadRadius = preloadRadius
    self.activeIndex = nil
  }

  /// Replaces the item list, resetting the active index to the first item.
  ///
  /// RN's list is rebuilt whenever the feed data changes; the pager scroll
  /// position survives, so the caller re-observes. Resetting to index `0` here
  /// matches the initial `useState(0)` in the RN screen.
  public mutating func setItems(_ ids: [String], resetActive: Bool = true) {
    itemIDs = ids
    if resetActive {
      activeIndex = ids.isEmpty ? nil : 0
    } else if let activeIndex, !ids.indices.contains(activeIndex) {
      self.activeIndex = ids.isEmpty ? nil : min(activeIndex, ids.count - 1)
    }
  }

  /// Applies one scroll observation, returning the resulting state.
  ///
  /// - Parameter entries: the viewable entries the list reported, in list order.
  ///   An empty list clears the active item (the pager is between items).
  /// - Returns: the new ``VideoPagerState``, including which indices changed.
  @discardableResult
  public mutating func observe(_ entries: [VideoViewportEntry]) -> VideoPagerState {
    let viewable = entries.filter { config.isViewable($0) }
    let previousActive = activeIndex
    // RN reads `viewableItems[0].index`; the List reports entries in list order,
    // so the first one is the topmost viewable item.
    let nextActive = viewable.first(where: { itemIDs.indices.contains($0.index) })?.index
    activeIndex = nextActive
    return state(changed: changedIndices(previous: previousActive, next: nextActive))
  }

  /// Moves the pager directly to `index`, as a programmatic scroll would.
  ///
  /// Invalid indices are ignored rather than clamped, matching RN's
  /// `setCurrentIndex` usage where the index always comes from the list.
  @discardableResult
  public mutating func moveTo(_ index: Int) -> VideoPagerState {
    guard itemIDs.indices.contains(index) else { return state(changed: []) }
    let previousActive = activeIndex
    activeIndex = index
    return state(changed: changedIndices(previous: previousActive, next: index))
  }

  /// Clears the active item, as when the screen loses focus.
  ///
  /// RN releases every player on blur (`useFocusEffect` cleanup) and loses the
  /// active index with them.
  @discardableResult
  public mutating func clearActive() -> VideoPagerState {
    let previousActive = activeIndex
    activeIndex = nil
    return state(changed: changedIndices(previous: previousActive, next: nil))
  }

  /// The current state without mutating anything.
  public func state(changed: [Int] = []) -> VideoPagerState {
    let preloads = activeIndex.map {
      preloadWindow(around: $0, count: itemIDs.count, radius: preloadRadius)
    } ?? []
    let viewability = itemIDs.enumerated().map { index, id in
      videoViewability(
        index: index,
        id: id,
        activeIndex: activeIndex,
        preloadIndices: preloads)
    }
    return VideoPagerState(
      itemIDs: itemIDs,
      activeIndex: activeIndex,
      preloadIndices: preloads,
      viewability: viewability,
      changedIndices: changed)
  }

  /// The indices whose active/adjacent/preload status differs between two active
  /// indices. RN re-renders the whole list on a change, but knowing the delta is
  /// what lets the Views layer touch only the affected players.
  private func changedIndices(previous: Int?, next: Int?) -> [Int] {
    guard previous != next else { return [] }
    var changed: Set<Int> = []
    for index in unionWindows(previous: previous, next: next) {
      changed.insert(index)
    }
    return changed.sorted()
  }

  /// Every index touched by either active index's preload window.
  private func unionWindows(previous: Int?, next: Int?) -> [Int] {
    var indices: Set<Int> = []
    for active in [previous, next].compactMap({ $0 }) {
      for index in preloadWindow(around: active, count: itemIDs.count, radius: preloadRadius) {
        indices.insert(index)
      }
      for index in adjacentIndices(to: active, count: itemIDs.count) {
        indices.insert(index)
      }
    }
    return Array(indices)
  }

  /// One item's viewability value.
  private func videoViewability(
    index: Int,
    id: String,
    activeIndex: Int?,
    preloadIndices: [Int]
  ) -> VideoViewability {
    let isActive = activeIndex == index
    return VideoViewability(
      index: index,
      id: id,
      isViewable: isActive,
      isActive: isActive,
      isPreloaded: preloadIndices.contains(index),
      isAdjacent: activeIndex.map {
        adjacentIndices(to: $0, count: itemIDs.count).contains(index)
      } ?? false)
  }
}
