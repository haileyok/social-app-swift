import Foundation
import Testing

@testable import VideoFeedLogic

/// Viewability, the preload window, and the pager state machine.
///
/// Ports the `viewabilityConfig` and the `onViewableItemsChanged` handler in
/// `src/screens/VideoFeed/index.tsx`, plus the three-player slot arithmetic in
/// `updateVideoState`.
@Suite("Video viewability and pager")
struct VideoViewabilityTests {
  // MARK: - Config

  @Test("the immersive config is 100 percent and no minimum view time")
  func immersiveConfig() {
    let config = VideoViewabilityConfig.immersive
    #expect(config.itemVisiblePercentThreshold == 100)
    #expect(config.minimumViewTime == 0)
  }

  @Test("the immersive config is stricter than the shared list default")
  func stricterThanListDefault() {
    // RN's `List` default is 40 percent / 500 ms; the video feed overrides both.
    let config = VideoViewabilityConfig.immersive
    #expect(config.itemVisiblePercentThreshold > 40)
    #expect(config.minimumViewTime < 0.5)
  }

  @Test("only a fully-covered item is viewable at the immersive threshold")
  func fullyCoveredIsViewable() {
    let config = VideoViewabilityConfig.immersive
    #expect(config.isViewable(VideoViewportEntry(index: 0, visibleFraction: 1.0)))
    #expect(!config.isViewable(VideoViewportEntry(index: 0, visibleFraction: 0.999)))
    #expect(!config.isViewable(VideoViewportEntry(index: 0, visibleFraction: 0.5)))
    #expect(!config.isViewable(VideoViewportEntry(index: 0, visibleFraction: 0)))
  }

  @Test("a minimum view time holds an item back until it has been visible long enough")
  func minimumViewTimeGate() {
    let config = VideoViewabilityConfig(
      itemVisiblePercentThreshold: 100, minimumViewTime: 0.5)
    #expect(
      !config.isViewable(
        VideoViewportEntry(index: 0, visibleFraction: 1, visibleDuration: 0.4)))
    #expect(
      config.isViewable(
        VideoViewportEntry(index: 0, visibleFraction: 1, visibleDuration: 0.5)))
  }

  @Test("a viewport entry reports its percent form")
  func percentForm() {
    #expect(VideoViewportEntry(index: 0, visibleFraction: 0.75).visiblePercent == 75)
  }

  // MARK: - Preload window math

  @Test("the preload window is symmetric and includes the active index")
  func preloadWindowSymmetric() {
    #expect(preloadWindow(around: 3, count: 10) == [2, 3, 4])
  }

  @Test("the preload window clamps at the list edges")
  func preloadWindowClamps() {
    #expect(preloadWindow(around: 0, count: 10) == [0, 1])
    #expect(preloadWindow(around: 9, count: 10) == [8, 9])
    #expect(preloadWindow(around: 0, count: 1) == [0])
    #expect(preloadWindow(around: 1, count: 3) == [0, 1, 2])
  }

  @Test("a zero-radius window is just the active index")
  func preloadWindowZeroRadius() {
    #expect(preloadWindow(around: 4, count: 10, radius: 0) == [4])
  }

  @Test("a wider radius preloads further ahead")
  func preloadWindowWiderRadius() {
    #expect(preloadWindow(around: 5, count: 10, radius: 2) == [3, 4, 5, 6, 7])
  }

  @Test("the preload window is empty for an out-of-range or empty list")
  func preloadWindowDegenerate() {
    #expect(preloadWindow(around: 0, count: 0).isEmpty)
    #expect(preloadWindow(around: -1, count: 5).isEmpty)
    #expect(preloadWindow(around: 5, count: 5).isEmpty)
  }

  @Test("the default radius preloads one video either side")
  func defaultRadiusIsOne() {
    #expect(VideoFeedConstants.preloadRadius == 1)
    #expect(preloadWindow(around: 5, count: 10).count == 3)
  }

  @Test("adjacent indices are the neighbors, clamped")
  func adjacentIndicesClamp() {
    #expect(adjacentIndices(to: 5, count: 10) == [4, 6])
    #expect(adjacentIndices(to: 0, count: 10) == [1])
    #expect(adjacentIndices(to: 9, count: 10) == [8])
    #expect(adjacentIndices(to: 0, count: 1).isEmpty)
    #expect(adjacentIndices(to: 5, count: 0).isEmpty)
  }

  // MARK: - Player pool

  @Test("the player pool slot follows RN's index modulo the pool size")
  func poolSlotModulo() {
    #expect(playerPoolSlot(for: 0) == 0)
    #expect(playerPoolSlot(for: 1) == 1)
    #expect(playerPoolSlot(for: 2) == 2)
    #expect(playerPoolSlot(for: 3) == 0)
    #expect(playerPoolSlot(for: 4) == 1)
    #expect(VideoFeedConstants.playerPoolSize == 3)
  }

  @Test("the slot assignment matches RN's previous/current/next offsets")
  func slotAssignments() {
    // RN: previous -> (index + 2) % 3, current -> index % 3, next -> (index + 1) % 3.
    let atThree = playerSlotAssignments(activeIndex: 3, count: 10)
    #expect(atThree.count == 3)
    // At index 3 all three offsets hit distinct slots: 2 -> previous, 0 ->
    // current, 1 -> next.
    #expect(atThree[2] == 2)
    #expect(atThree[0] == 3)
    #expect(atThree[1] == 4)
    #expect(Set(atThree.values) == [2, 3, 4])
  }

  @Test("slot assignments clamp at the list edges")
  func slotAssignmentsClamp() {
    let atStart = playerSlotAssignments(activeIndex: 0, count: 10)
    #expect(Set(atStart.values) == [0, 1])
    let atEnd = playerSlotAssignments(activeIndex: 9, count: 10)
    #expect(Set(atEnd.values) == [8, 9])
    #expect(playerSlotAssignments(activeIndex: 0, count: 0).isEmpty)
  }

  // MARK: - Pager state machine

  @Test("an empty observation clears the active item")
  func emptyObservationClearsActive() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    machine.setItems(["a", "b", "c"])
    #expect(machine.activeIndex == 0)
    let state = machine.observe([])
    #expect(state.activeIndex == nil)
    #expect(state.activeID == nil)
    #expect(state.preloadIndices.isEmpty)
  }

  @Test("a fully-visible item becomes the active one")
  func fullyVisibleBecomesActive() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    let state = machine.observe([
      VideoViewportEntry(index: 1, visibleFraction: 1.0)
    ])
    #expect(state.activeIndex == 1)
    #expect(state.activeID == "b")
    #expect(state.viewability[1].isActive)
  }

  @Test("a partially-visible item does not become active")
  func partialVisibilityDoesNotActivate() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    machine.setItems(["a", "b", "c"])
    let state = machine.observe([
      VideoViewportEntry(index: 1, visibleFraction: 0.8)
    ])
    #expect(state.activeIndex == nil)
  }

  @Test("the first viewable entry wins when several are reported")
  func firstViewableWins() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    // A transition where two items are momentarily both fully visible: RN reads
    // `viewableItems[0].index`, so the topmost wins.
    let state = machine.observe([
      VideoViewportEntry(index: 2, visibleFraction: 1.0),
      VideoViewportEntry(index: 1, visibleFraction: 1.0),
    ])
    #expect(state.activeIndex == 2)
  }

  @Test("the preload window follows the active index")
  func preloadFollowsActive() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c", "d", "e"])
    let state = machine.observe([VideoViewportEntry(index: 2, visibleFraction: 1.0)])
    #expect(state.preloadIndices == [1, 2, 3])
    #expect(state.preloadIDs == ["b", "c", "d"])
  }

  @Test("the preload window clamps at the first and last items")
  func preloadClampsAtEdges() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    #expect(machine.observe([VideoViewportEntry(index: 0, visibleFraction: 1)]).preloadIndices == [0, 1])
    #expect(machine.observe([VideoViewportEntry(index: 2, visibleFraction: 1)]).preloadIndices == [1, 2])
  }

  @Test("per-index viewability agrees with the active and preload sets")
  func perIndexViewability() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c", "d"])
    let state = machine.observe([VideoViewportEntry(index: 1, visibleFraction: 1.0)])
    #expect(state.viewability.count == 4)
    #expect(state.viewability[0].isPreloaded)
    #expect(!state.viewability[0].isActive)
    #expect(state.viewability[1].isActive)
    #expect(state.viewability[1].isViewable)
    #expect(state.viewability[2].isPreloaded)
    #expect(!state.viewability[3].isPreloaded)
    #expect(state.viewability[3].id == "d")
  }

  @Test("adjacent items are one swipe away and inside the preload window")
  func adjacentItems() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c", "d"])
    let state = machine.observe([VideoViewportEntry(index: 1, visibleFraction: 1.0)])
    #expect(state.adjacentIDs == ["a", "c"])
    #expect(state.viewability[0].isAdjacent)
    #expect(state.viewability[2].isAdjacent)
    // Two swipes away is preloaded but not adjacent.
    #expect(!state.viewability[3].isAdjacent)
  }

  @Test("a scroll transition reports the changed indices")
  func transitionReportsChanges() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c", "d", "e"])
    machine.observe([VideoViewportEntry(index: 1, visibleFraction: 1.0)])
    let state = machine.observe([VideoViewportEntry(index: 2, visibleFraction: 1.0)])
    #expect(state.activeIndex == 2)
    // The union of both windows: {0,1,2} and {1,2,3} -> 0...3.
    #expect(state.changedIndices == [0, 1, 2, 3])
  }

  @Test("re-observing the same index reports no change")
  func sameIndexNoChange() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    machine.observe([VideoViewportEntry(index: 1, visibleFraction: 1.0)])
    let state = machine.observe([VideoViewportEntry(index: 1, visibleFraction: 1.0)])
    #expect(state.changedIndices.isEmpty)
  }

  @Test("a programmatic move sets the active index and reports the delta")
  func programmaticMove() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c", "d"])
    machine.observe([VideoViewportEntry(index: 0, visibleFraction: 1.0)])
    let state = machine.moveTo(2)
    #expect(state.activeIndex == 2)
    #expect(state.preloadIndices == [1, 2, 3])
    #expect(!state.changedIndices.isEmpty)
  }

  @Test("an out-of-range programmatic move is ignored")
  func invalidMoveIgnored() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b"])
    machine.observe([VideoViewportEntry(index: 0, visibleFraction: 1.0)])
    let state = machine.moveTo(5)
    #expect(state.activeIndex == 0)
    #expect(state.changedIndices.isEmpty)
  }

  @Test("clearing the active item releases the preload window")
  func clearActiveReleasesPreloads() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    machine.observe([VideoViewportEntry(index: 1, visibleFraction: 1.0)])
    let state = machine.clearActive()
    #expect(state.activeIndex == nil)
    #expect(state.preloadIndices.isEmpty)
    #expect(state.adjacentIDs.isEmpty)
    #expect(state.changedIndices == [0, 1, 2])
  }

  @Test("replacing the item list resets to the first item")
  func setItemsResets() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b"])
    machine.moveTo(1)
    machine.setItems(["x", "y", "z"])
    #expect(machine.activeIndex == 0)
    let state = machine.state()
    #expect(state.itemIDs == ["x", "y", "z"])
    #expect(state.preloadIndices == [0, 1])
  }

  @Test("replacing the item list without a reset clamps the active index")
  func setItemsClampsWhenNotResetting() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b", "c"])
    machine.moveTo(2)
    machine.setItems(["x", "y"], resetActive: false)
    #expect(machine.activeIndex == 1)
  }

  @Test("an empty item list has no active item")
  func emptyItemList() {
    var machine = VideoPagerStateMachine(itemIDs: [])
    let state = machine.observe([VideoViewportEntry(index: 0, visibleFraction: 1.0)])
    #expect(state.activeIndex == nil)
    #expect(state.itemIDs.isEmpty)
    #expect(state.preloadIDs.isEmpty)
  }

  @Test("an observation for an index outside the item list is ignored")
  func outOfRangeObservation() {
    var machine = VideoPagerStateMachine(itemIDs: ["a", "b"])
    let state = machine.observe([VideoViewportEntry(index: 7, visibleFraction: 1.0)])
    #expect(state.activeIndex == nil)
  }

  @Test("a wider preload radius widens the state's window")
  func widerRadiusInMachine() {
    var machine = VideoPagerStateMachine(
      itemIDs: ["a", "b", "c", "d", "e"], preloadRadius: 2)
    let state = machine.observe([VideoViewportEntry(index: 2, visibleFraction: 1.0)])
    #expect(state.preloadIndices == [0, 1, 2, 3, 4])
  }

  @Test("the default state is empty with no active item")
  func defaultState() {
    let state = VideoPagerState.empty()
    #expect(state.activeIndex == nil)
    #expect(state.activeID == nil)
    #expect(state.itemIDs.isEmpty)
  }
}
