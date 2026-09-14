import Foundation
import Testing

@testable import VideoFeedLogic

/// The per-item playback state store: pure transitions, no player.
///
/// Ports the component-local state RN keeps inside each mounted `VideoItem`
/// (`isPlaying`, `isActive`, `isLoading`, `muted`, `timeRemaining`, `error`) plus
/// the `playbackStartTrackedRef` guard and the `maxTimeRemainingSeconds` duration
/// estimate in `src/screens/VideoFeed/index.tsx`.
@Suite("Video playback store")
struct VideoPlaybackStoreTests {
  /// A store with one registered item.
  func makeStore() -> (VideoPlaybackStore, String) {
    var store = VideoPlaybackStore()
    let id = "item-1"
    store.register(itemID: id, postURI: Fixtures.uri("p1"), playlist: Fixtures.playlist("p1"))
    return (store, id)
  }

  // MARK: - Registration

  @Test("registering an item starts it in the loading phase")
  func registerStartsLoading() throws {
    let (store, id) = makeStore()
    let state = try #require(store.state(for: id))
    #expect(state.phase == .loading)
    #expect(state.playlist == Fixtures.playlist("p1"))
    #expect(state.postURI == Fixtures.uri("p1"))
    #expect(state.currentTime == 0)
    #expect(!state.isActive)
  }

  @Test("a new item inherits the store's default mute state")
  func registerInheritsDefaultMute() throws {
    var store = VideoPlaybackStore(defaultMuted: false)
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    #expect(try #require(store.state(for: "a")).isMuted == false)

    let (mutedStore, id) = makeStore()
    // RN initialises the mute context to `true`.
    #expect(try #require(mutedStore.state(for: id)).isMuted)
    #expect(VideoPlaybackStore().defaultMuted)
  }

  @Test("re-registering with a different playlist resets the phase")
  func reRegisterDifferentPlaylistResets() throws {
    var (store, id) = makeStore()
    store.statusChanged(itemID: id, phase: .ready)
    store.playingChanged(itemID: id, isPlaying: true)
    #expect(try #require(store.state(for: id)).phase == .playing)

    // A recycled player slot pointing at a new playlist: the old media's phase
    // no longer describes the item, so it reloads.
    store.register(itemID: id, postURI: Fixtures.uri("p1"), playlist: Fixtures.playlist("p2"))
    let state = try #require(store.state(for: id))
    #expect(state.phase == .loading)
    #expect(state.playlist == Fixtures.playlist("p2"))
  }

  @Test("re-registering with the same playlist preserves the phase")
  func reRegisterSamePlaylistPreserves() throws {
    var (store, id) = makeStore()
    store.statusChanged(itemID: id, phase: .ready)
    store.register(itemID: id, postURI: Fixtures.uri("p1"), playlist: Fixtures.playlist("p1"))
    #expect(try #require(store.state(for: id)).phase == .ready)
  }

  @Test("an unregistered item has no state")
  func unknownItemHasNoState() {
    let (store, _) = makeStore()
    #expect(store.state(for: "nope") == nil)
  }

  @Test("an event for an unregistered item is a no-op")
  func eventForUnknownItemIsNoop() {
    var (store, _) = makeStore()
    store.statusChanged(itemID: "nope", phase: .playing)
    store.playingChanged(itemID: "nope", isPlaying: true)
    store.timeUpdated(itemID: "nope", currentTime: 5, timeRemaining: 1)
    #expect(store.state(for: "nope") == nil)
  }

  // MARK: - Load / status transitions

  @Test("the load lifecycle moves loading -> ready -> playing -> paused")
  func loadLifecycle() throws {
    var (store, id) = makeStore()
    #expect(try #require(store.state(for: id)).phase == .loading)

    store.loadingChanged(itemID: id, isLoading: false)
    #expect(try #require(store.state(for: id)).phase == .ready)
    #expect(try #require(store.state(for: id)).phase.hasMedia)

    store.playingChanged(itemID: id, isPlaying: true)
    #expect(try #require(store.state(for: id)).phase.isPlaying)

    store.playingChanged(itemID: id, isPlaying: false)
    #expect(try #require(store.state(for: id)).phase == .paused)
  }

  @Test("a readyToPlay status moves the item to ready")
  func readyStatus() throws {
    var (store, id) = makeStore()
    // RN: `onStatusChange` with `readyToPlay`.
    store.statusChanged(itemID: id, phase: .ready)
    #expect(try #require(store.state(for: id)).phase == .ready)
  }

  @Test("mid-playback buffering returns to playing when the active item recovers")
  func bufferingRecoversWhileActive() throws {
    var (store, id) = makeStore()
    store.statusChanged(itemID: id, phase: .ready)
    store.activeChanged(itemID: id, isActive: true)
    store.playingChanged(itemID: id, isPlaying: true)

    store.loadingChanged(itemID: id, isLoading: true)
    #expect(try #require(store.state(for: id)).phase == .loading)

    store.statusChanged(itemID: id, phase: .buffering)
    store.loadingChanged(itemID: id, isLoading: false)
    #expect(try #require(store.state(for: id)).phase == .playing)
  }

  @Test("mid-playback buffering returns to paused when the item is not active")
  func bufferingReturnsToPausedWhenInactive() throws {
    var (store, id) = makeStore()
    store.statusChanged(itemID: id, phase: .buffering)
    store.loadingChanged(itemID: id, isLoading: false)
    #expect(try #require(store.state(for: id)).phase == .paused)
  }

  @Test("ending playback is a distinct phase from pausing")
  func endedIsDistinct() throws {
    var (store, id) = makeStore()
    store.playingChanged(itemID: id, isPlaying: true)
    store.ended(itemID: id)
    #expect(try #require(store.state(for: id)).phase == .ended)
    #expect(try #require(store.state(for: id)).phase.isPlaybackHalted)
    #expect(try #require(store.state(for: id)).phase.hasMedia)
    // A subsequent play starts again.
    store.playingChanged(itemID: id, isPlaying: true)
    #expect(try #require(store.state(for: id)).phase == .playing)
  }

  @Test("a failure records its message and clears the active flag")
  func failure() throws {
    var (store, id) = makeStore()
    store.activeChanged(itemID: id, isActive: true)
    store.failed(itemID: id, message: "decode failed")
    let state = try #require(store.state(for: id))
    #expect(state.phase == .failed(message: "decode failed"))
    #expect(state.phase.isFailed)
    #expect(!state.phase.hasMedia)
    #expect(!state.isActive)
    #expect(store.activeItemID == nil)
  }

  @Test("a failure with no message still records the failed phase")
  func failureWithoutMessage() throws {
    var (store, id) = makeStore()
    store.failed(itemID: id, message: nil)
    #expect(try #require(store.state(for: id)).phase == .failed(message: nil))
  }

  @Test("a pause while already paused does not disturb a non-playing phase")
  func pauseWhileIdleKeepsPhase() throws {
    var (store, id) = makeStore()
    // Still loading: a spurious `playing: false` must not claim it is paused.
    store.playingChanged(itemID: id, isPlaying: false)
    #expect(try #require(store.state(for: id)).phase == .loading)
  }

  // MARK: - Active transitions

  @Test("making an item active deactivates the previous one")
  func activeIsExclusive() throws {
    var store = VideoPlaybackStore()
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    store.register(itemID: "b", postURI: Fixtures.uri("b"), playlist: nil)

    store.activeChanged(itemID: "a", isActive: true)
    #expect(store.activeItemID == "a")
    #expect(try #require(store.state(for: "a")).isActive)

    store.activeChanged(itemID: "b", isActive: true)
    #expect(store.activeItemID == "b")
    #expect(!(try #require(store.state(for: "a")).isActive))
    #expect(try #require(store.state(for: "b")).isActive)
  }

  @Test("deactivating the active item clears the pointer")
  func deactivateClearsPointer() {
    var store = VideoPlaybackStore()
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    store.activeChanged(itemID: "a", isActive: true)
    store.activeChanged(itemID: "a", isActive: false)
    #expect(store.activeItemID == nil)
  }

  @Test("deactivating a non-active item leaves the pointer alone")
  func deactivateOtherKeepsPointer() {
    var store = VideoPlaybackStore()
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    store.register(itemID: "b", postURI: Fixtures.uri("b"), playlist: nil)
    store.activeChanged(itemID: "a", isActive: true)
    store.activeChanged(itemID: "b", isActive: false)
    #expect(store.activeItemID == "a")
  }

  @Test("a preloaded neighbor can be ready without being active")
  func preloadedNeighborNotActive() throws {
    var store = VideoPlaybackStore()
    store.register(itemID: "next", postURI: Fixtures.uri("next"), playlist: nil)
    store.statusChanged(itemID: "next", phase: .ready)
    let state = try #require(store.state(for: "next"))
    // This is what `usePlaybackTelemetry` calls "preloaded".
    #expect(state.phase == .ready)
    #expect(!state.isActive)
    #expect(store.activeItemID == nil)
  }

  @Test("the active state is exposed for the active item only")
  func activeStateAccessor() throws {
    var store = VideoPlaybackStore()
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    #expect(store.activeState == nil)
    store.activeChanged(itemID: "a", isActive: true)
    #expect(store.activeState?.itemID == "a")
  }

  // MARK: - Mute

  @Test("mute changes are recorded per item")
  func muteChanges() throws {
    var (store, id) = makeStore()
    store.mutedChanged(itemID: id, isMuted: false)
    #expect(try #require(store.state(for: id)).isMuted == false)
    store.mutedChanged(itemID: id, isMuted: true)
    #expect(try #require(store.state(for: id)).isMuted)
  }

  // MARK: - Time updates and progress

  @Test("a time update records the position and the duration estimate")
  func timeUpdateRecordsDuration() throws {
    var (store, id) = makeStore()
    store.timeUpdated(itemID: id, currentTime: 3, timeRemaining: 7)
    let state = try #require(store.state(for: id))
    #expect(state.currentTime == 3)
    #expect(state.timeRemaining == 7)
    // RN: `maxTimeRemainingSeconds.current = Math.max(current, timeRemaining)`.
    #expect(state.maxTimeRemaining == 7)
    #expect(state.progressSeconds == 0)
  }

  @Test("the duration estimate ratchets up and never down")
  func durationRatchets() throws {
    var (store, id) = makeStore()
    store.timeUpdated(itemID: id, currentTime: 1, timeRemaining: 9)
    store.timeUpdated(itemID: id, currentTime: 2, timeRemaining: 8)
    // A later callback reporting a smaller remaining value must not shrink the
    // derived duration.
    store.timeUpdated(itemID: id, currentTime: 3, timeRemaining: 6)
    #expect(try #require(store.state(for: id)).maxTimeRemaining == 9)
    #expect(try #require(store.state(for: id)).progressSeconds == 3)
  }

  @Test("progress is duration minus time remaining, clamped at zero")
  func progressClamped() throws {
    var (store, id) = makeStore()
    // A spurious remaining value larger than the estimate yields zero, not a
    // negative timestamp.
    store.timeUpdated(itemID: id, currentTime: 1, timeRemaining: 5)
    store.timeUpdated(itemID: id, currentTime: 2, timeRemaining: 5)
    #expect(try #require(store.state(for: id)).progressSeconds == 0)

    var (store2, id2) = makeStore()
    store2.timeUpdated(itemID: id2, currentTime: 0, timeRemaining: 10)
    store2.timeUpdated(itemID: id2, currentTime: 4, timeRemaining: 6)
    #expect(try #require(store2.state(for: id2)).progressSeconds == 4)
  }

  @Test("a non-finite time update is ignored")
  func nonFiniteTimeIgnored() throws {
    var (store, id) = makeStore()
    store.timeUpdated(itemID: id, currentTime: .nan, timeRemaining: .nan)
    let state = try #require(store.state(for: id))
    #expect(state.currentTime == 0)
    #expect(state.timeRemaining == 0)
    #expect(state.maxTimeRemaining == 0)

    store.timeUpdated(itemID: id, currentTime: -1, timeRemaining: -1)
    #expect(try #require(store.state(for: id)).currentTime == 0)
  }

  @Test("an infinite time remaining is stored but does not set the estimate")
  func infiniteRemaining() throws {
    var (store, id) = makeStore()
    store.timeUpdated(itemID: id, currentTime: 1, timeRemaining: .infinity)
    let state = try #require(store.state(for: id))
    #expect(state.timeRemaining == .infinity)
    // RN guards the estimate with `Number.isFinite`, so infinity never becomes
    // the duration.
    #expect(state.maxTimeRemaining == 0)
  }

  // MARK: - Playback-start tracking

  @Test("hasPlaybackStarted follows RN's 0.05 s threshold")
  func playbackStartThreshold() {
    // The exact table from `src/lib/media/video/__tests__/analytics.test.ts`.
    #expect(!hasPlaybackStarted(progressSeconds: 0))
    #expect(!hasPlaybackStarted(progressSeconds: 0.049))
    #expect(hasPlaybackStarted(progressSeconds: 0.05))
    #expect(hasPlaybackStarted(progressSeconds: 1))
    #expect(!hasPlaybackStarted(progressSeconds: .nan))
    #expect(!hasPlaybackStarted(progressSeconds: .infinity))
  }

  @Test("the playback-start report fires once, at the threshold")
  func playbackStartFiresOnce() throws {
    var (store, id) = makeStore()
    store.timeUpdated(itemID: id, currentTime: 0, timeRemaining: 10)
    // Below the threshold: no report.
    let beforeThreshold = store.trackPlaybackStartIfNeeded(itemID: id)
    #expect(!beforeThreshold)

    store.timeUpdated(itemID: id, currentTime: 0.05, timeRemaining: 9.95)
    #expect(try #require(store.state(for: id)).hasPlaybackStarted)
    let firstReport = store.trackPlaybackStartIfNeeded(itemID: id)
    #expect(firstReport)
    // The ref is now set: a second call is a no-op.
    let secondReport = store.trackPlaybackStartIfNeeded(itemID: id)
    #expect(!secondReport)
    #expect(try #require(store.state(for: id)).hasTrackedPlaybackStart)
  }

  @Test("the playback-start report does not fire for an unregistered item")
  func playbackStartUnknownItem() {
    var (store, _) = makeStore()
    let reported = store.trackPlaybackStartIfNeeded(itemID: "nope")
    #expect(!reported)
  }

  // MARK: - Derived views and lifecycle

  @Test("isAnythingPlaying reflects the playing items")
  func anythingPlaying() {
    var store = VideoPlaybackStore()
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    #expect(!store.isAnythingPlaying)
    store.playingChanged(itemID: "a", isPlaying: true)
    #expect(store.isAnythingPlaying)
    store.playingChanged(itemID: "a", isPlaying: false)
    #expect(!store.isAnythingPlaying)
  }

  @Test("removing an item drops its state and clears the active pointer")
  func removeItem() {
    var store = VideoPlaybackStore()
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    store.activeChanged(itemID: "a", isActive: true)
    store.remove(itemID: "a")
    #expect(store.state(for: "a") == nil)
    #expect(store.activeItemID == nil)
  }

  @Test("retainOnly drops the items that left the list")
  func retainOnly() {
    var store = VideoPlaybackStore()
    for id in ["a", "b", "c"] {
      store.register(itemID: id, postURI: Fixtures.uri(id), playlist: nil)
    }
    store.activeChanged(itemID: "c", isActive: true)
    store.retainOnly(["a", "b"])
    #expect(store.state(for: "c") == nil)
    #expect(store.state(for: "a") != nil)
    #expect(store.state(for: "b") != nil)
    // The active item left the list, so the pointer is cleared.
    #expect(store.activeItemID == nil)
  }

  @Test("retainOnly keeps the active pointer when the active item survives")
  func retainOnlyKeepsActive() {
    var store = VideoPlaybackStore()
    for id in ["a", "b"] {
      store.register(itemID: id, postURI: Fixtures.uri(id), playlist: nil)
    }
    store.activeChanged(itemID: "a", isActive: true)
    store.retainOnly(["a", "b"])
    #expect(store.activeItemID == "a")
  }

  @Test("registered item ids are enumerable")
  func registeredIDs() {
    var store = VideoPlaybackStore()
    store.register(itemID: "b", postURI: Fixtures.uri("b"), playlist: nil)
    store.register(itemID: "a", postURI: Fixtures.uri("a"), playlist: nil)
    #expect(store.registeredItemIDs == ["a", "b"])
  }

  // MARK: - Phase semantics

  @Test("phase flags describe the lifecycle")
  func phaseFlags() {
    #expect(!VideoPlaybackPhase.idle.hasMedia)
    #expect(!VideoPlaybackPhase.idle.isPlaying)
    #expect(VideoPlaybackPhase.idle.isPlaybackHalted)
    #expect(!VideoPlaybackPhase.loading.hasMedia)
    #expect(VideoPlaybackPhase.ready.hasMedia)
    #expect(!VideoPlaybackPhase.ready.isPlaybackHalted)
    #expect(VideoPlaybackPhase.buffering.hasMedia)
    #expect(VideoPlaybackPhase.playing.isPlaying)
    #expect(!VideoPlaybackPhase.playing.isPlaybackHalted)
    #expect(VideoPlaybackPhase.paused.isPlaybackHalted)
    #expect(VideoPlaybackPhase.ended.isPlaybackHalted)
    #expect(VideoPlaybackPhase.failed(message: "x").isPlaybackHalted)
    #expect(VideoPlaybackPhase.failed(message: "x").isFailed)
    #expect(!VideoPlaybackPhase.ready.isFailed)
  }
}
