import Foundation
import Observation
import VideoFeedLogic

/// Drives the immersive pager: which item is active, which three player slots
/// hold which items, and whether each one may play.
///
/// This is the Swift counterpart of the `players` array and the `updateVideoState`
/// callback-plus-`useEffect` pair in `src/screens/VideoFeed/index.tsx`. Every
/// decision it makes is delegated:
///
/// - which item is active and which indices are in the preload window comes from
///   ``VideoPagerStateMachine``;
/// - which slot holds which item comes from
///   ``playerSlotAssignments(activeIndex:count:poolSize:)``;
/// - whether an item may play at all comes from ``videoAutoplayDecision``;
/// - the mute state an item starts in comes from ``videoBeginMuted``;
/// - the recorded playback state goes into ``VideoPlaybackStore``.
///
/// What is left here is the plumbing that needs both a scroll position and an
/// `AVPlayer`: reconcile the pool, apply the gate, and keep the store in step
/// with what the players report.
@MainActor
@Observable
final class VideoFeedController {
  /// The items the pager pages through, in order.
  private(set) var items: [VideoItem]
  /// The current autoplay inputs.
  private(set) var settings: VideoAutoplaySettings
  /// The pager's viewability state, recomputed on every move.
  private(set) var state: VideoPagerState
  /// The active index. Kept as a plain `Int` because a pager always shows one
  /// page; ``state`` carries the "nothing is viewable" case.
  private(set) var currentIndex: Int
  /// The recorded playback state per item.
  private(set) var playback = VideoPlaybackStore()

  /// The recycled player slots. Three by default, matching RN's pool.
  private let pool: [VideoPlayerSlot]
  /// The item indices currently attached to a slot.
  private var attachedIndices: Set<Int> = []
  /// The current slot -> item-index assignment, as ``VideoFeedLogic`` computes it.
  private var assignment: [Int: Int] = [:]
  /// Items the viewer explicitly started, which play despite a disabled autoplay.
  private var manuallyStarted: Set<String> = []
  /// Items whose moderation blur the viewer revealed, which may then play.
  private var revealedItemIDs: Set<String> = []
  /// Items liked from this screen, so the affordance can reflect the intent.
  private var likedItemIDs: Set<String> = []

  private var machine: VideoPagerStateMachine

  /// Creates a controller over an ordered item list.
  ///
  /// - Parameters:
  ///   - items: the feed items, in pager order.
  ///   - settings: the autoplay inputs. Pass the value
  ///     ``VideoAutoplayPreference/settings(account:did:)`` produced so the
  ///     persisted preference applies.
  ///   - initialIndex: the page to start on.
  ///   - poolSize: the number of recycled players.
  init(
    items: [VideoItem],
    settings: VideoAutoplaySettings = VideoAutoplaySettings(),
    initialIndex: Int = 0,
    poolSize: Int = VideoFeedConstants.playerPoolSize
  ) {
    self.items = items
    self.settings = settings
    self.pool = (0..<max(1, poolSize)).map { _ in VideoPlayerSlot() }
    let start = items.indices.contains(initialIndex) ? initialIndex : 0
    self.currentIndex = start
    // The machine is built and advanced locally: touching `self.machine` here
    // would read the observation registrar before every stored property is
    // initialized.
    var machine = VideoPagerStateMachine(itemIDs: items.map(\.id))
    if !items.isEmpty {
      machine.moveTo(start)
    }
    self.machine = machine
    self.state = machine.state()
    registerSlotCallbacks()
    synchronize()
  }

  // MARK: - Slots

  /// The slot the pool assigns to the item at `index`, or `nil` when there is
  /// none.
  func slot(for index: Int) -> VideoPlayerSlot? {
    guard items.indices.contains(index) else { return nil }
    return pool[playerPoolSlot(for: index, poolSize: pool.count)]
  }

  /// The time the item at `index` currently reports, for the scrubber.
  func timing(for index: Int) -> VideoPlayerTiming {
    slot(for: index)?.timing ?? .zero
  }

  /// Whether the item at `index` should render a player surface at all.
  ///
  /// RN: `shouldRenderVideo = active || (IS_IOS && adjacent)`. The preload
  /// window is exactly those indices, so the machines's own window is the answer.
  func shouldRenderPlayer(at index: Int) -> Bool {
    state.preloadIndices.contains(index)
  }

  // MARK: - Gating

  /// The autoplay decision for the item at `index`.
  func decision(for index: Int) -> VideoAutoplayDecision {
    guard items.indices.contains(index) else { return .suppressedInMessage }
    return videoAutoplayDecision(settings: settings, moderation: items[index].moderation)
  }

  /// Whether the item at `index` may play, taking a revealed moderation blur
  /// into account.
  func isPlayable(at index: Int) -> Bool {
    guard items.indices.contains(index) else { return false }
    return decision(for: index).isPlayable || revealedItemIDs.contains(items[index].id)
  }

  /// True when the item at `index` is held back by moderation the viewer has not
  /// yet revealed, so the view shows the blur overlay instead of a frame.
  func isBlurredByModeration(at index: Int) -> Bool {
    guard items.indices.contains(index) else { return false }
    return decision(for: index).isModerationBlocked && !revealedItemIDs.contains(items[index].id)
  }

  /// Records that the viewer revealed a moderation blur, which lets the item
  /// play.
  func revealModeration(at index: Int) {
    guard items.indices.contains(index) else { return }
    revealedItemIDs.insert(items[index].id)
    synchronize()
  }

  /// The muted state the item at `index` should begin in.
  func beginMuted(at index: Int) -> Bool {
    guard items.indices.contains(index) else { return true }
    return videoBeginMuted(settings: settings, isGif: items[index].isGif)
  }

  // MARK: - Transport

  /// Toggles play/pause for the active item, as a tap does.
  ///
  /// A GIF presentation has no controls in RN, so a tap on one is ignored here
  /// too: the clip is always looping.
  func togglePlayPause(at index: Int) {
    guard items.indices.contains(index), let slot = slot(for: index) else { return }
    let item = items[index]
    guard !item.isGif, isPlayable(at: index) else { return }
    if slot.phase.isPlaying {
      manuallyStarted.remove(item.id)
      slot.pause()
    } else {
      manuallyStarted.insert(item.id)
      slot.play()
    }
    recordPhase(slotIndex: playerPoolSlot(for: index, poolSize: pool.count), phase: slot.phase)
  }

  /// Sets the mute state for the item at `index`.
  ///
  /// RN ignores mute changes on a GIF (`onMutedChange` is a no-op for
  /// `presentation === 'gif'`), and so does this.
  func setMuted(_ muted: Bool, at index: Int) {
    guard items.indices.contains(index), let slot = slot(for: index) else { return }
    let item = items[index]
    guard !item.isGif else { return }
    slot.setMuted(muted)
    playback.mutedChanged(itemID: item.id, isMuted: muted)
  }

  /// The current mute state for the item at `index` (`true` for GIFs).
  func isMuted(at index: Int) -> Bool {
    guard items.indices.contains(index), let slot = slot(for: index) else { return true }
    return slot.isMuted
  }

  /// Seeks the item at `index` to a `0...1` progress fraction.
  func seek(toProgress fraction: Double, at index: Int) {
    slot(for: index)?.seek(toProgress: fraction)
  }

  /// Records a like for the item at `index`.
  ///
  /// The double-tap gesture in the immersive feed likes the post
  /// (`queueLike()` in `src/screens/VideoFeed/index.tsx`). There is no like
  /// mutation wired into this package yet, so this records that the intent
  /// happened; the App surface that owns the account's agent supplies the
  /// mutation when it lands.
  func like(at index: Int) {
    guard items.indices.contains(index) else { return }
    likedItemIDs.insert(items[index].id)
  }

  /// Whether the item at `index` has been liked from this screen.
  func isLiked(at index: Int) -> Bool {
    guard items.indices.contains(index) else { return false }
    return likedItemIDs.contains(items[index].id)
  }

  /// The playback phase of the item at `index`, as the view renders it.
  func phase(at index: Int) -> VideoPlayerPhase {
    slot(for: index)?.phase ?? .empty
  }

  /// The caption tracks the item at `index` offers, empty when it has none.
  ///
  /// These come from the player's legible media selection group; an item whose
  /// stream carries no captions reports none.
  func captionOptions(at index: Int) -> [VideoCaptionOption] {
    slot(for: index)?.legibleOptions ?? []
  }

  /// The selected caption track's id for the item at `index`, or `nil` when
  /// captions are off.
  func selectedCaptionID(at index: Int) -> String? {
    slot(for: index)?.selectedCaptionID
  }

  /// Selects a caption track for the item at `index`, or turns captions off.
  func selectCaption(id: String?, at index: Int) {
    slot(for: index)?.selectCaption(id: id)
  }

  /// The playback state the store holds for the item at `index`.
  func playbackState(at index: Int) -> VideoPlaybackState? {
    guard items.indices.contains(index) else { return nil }
    return playback.state(for: items[index].id)
  }

  // MARK: - Pager

  /// Handles a scroll landing on `index`.
  func moveTo(_ index: Int) {
    guard items.indices.contains(index), index != currentIndex else { return }
    currentIndex = index
    // A manual start belongs to the item that was tapped; leaving it is the end
    // of that interaction, so the next item follows the autoplay gate again.
    manuallyStarted.removeAll()
    machine.moveTo(index)
    state = machine.state()
    synchronize()
  }

  /// Applies one scroll observation, returning the resulting state.
  @discardableResult
  func observe(_ entries: [VideoViewportEntry]) -> VideoPagerState {
    let previous = currentIndex
    let next = machine.observe(entries)
    state = next
    if let active = next.activeIndex, active != previous {
      currentIndex = active
      manuallyStarted.removeAll()
      synchronize()
    }
    return state
  }

  /// Releases every player, as a lost screen focus does.
  ///
  /// RN's `useFocusEffect` cleanup releases all three players; keeping that
  /// behaviour means a backgrounded screen holds no media.
  func stop() {
    machine.clearActive()
    state = machine.state()
    for slot in pool { slot.pause() }
  }

  /// Starts (or restarts) playback for the active item, applying the gate.
  func start() {
    machine.moveTo(currentIndex)
    state = machine.state()
    synchronize()
  }

  /// Replaces the item list, keeping the current index when it is still valid.
  func update(items: [VideoItem], settings: VideoAutoplaySettings? = nil) {
    self.items = items
    if let settings { self.settings = settings }
    machine.setItems(items.map(\.id), resetActive: false)
    if let active = machine.state().activeIndex {
      currentIndex = active
    } else if items.isEmpty {
      currentIndex = 0
    } else {
      currentIndex = min(currentIndex, items.count - 1)
      machine.moveTo(currentIndex)
    }
    state = machine.state()
    attachedIndices.removeAll()
    for slot in pool { slot.detach() }
    synchronize()
  }

  // MARK: - Pool reconciliation

  /// Reconciles the three slots against the current active index.
  ///
  /// The sequence is RN's `updateVideoState`: compute the assignment, release
  /// the slots that lost their item, attach the ones that gained one, then apply
  /// the gate to each.
  private func synchronize() {
    playback.retainOnly(items.map(\.id))
    assignment = playerSlotAssignments(
      activeIndex: currentIndex, count: items.count, poolSize: pool.count)
    let assigned = Set(assignment.values)
    for index in attachedIndices.subtracting(assigned) {
      slot(for: index)?.detach()
    }
    attachedIndices = assigned
    for (slotIndex, itemIndex) in assignment {
      guard items.indices.contains(itemIndex) else { continue }
      let item = items[itemIndex]
      let slot = pool[slotIndex]
      let isNewSource = slot.playlist != item.video.playlist
      slot.attach(playlist: item.video.playlist, loops: item.isGif)
      if isNewSource {
        // A fresh source begins in the state ``videoBeginMuted`` derives, which
        // is the mute state the RN player is constructed with. An explicit
        // unmute on an already-playing item is not undone by a later update.
        slot.setMuted(beginMuted(at: itemIndex))
      }
      playback.register(itemID: item.id, postURI: item.postURI, playlist: item.video.playlist)
      playback.mutedChanged(itemID: item.id, isMuted: slot.isMuted)
      applyGating(itemIndex: itemIndex, slot: slot)
    }
    // An item that left the pool keeps its recorded state, but it is no longer
    // the active player.
    for index in items.indices where !assigned.contains(index) {
      playback.activeChanged(itemID: items[index].id, isActive: false)
    }
  }

  /// Applies the autoplay gate to one slot.
  private func applyGating(itemIndex: Int, slot: VideoPlayerSlot) {
    let item = items[itemIndex]
    let isActive = itemIndex == currentIndex && isPlayable(at: itemIndex)
    playback.activeChanged(itemID: item.id, isActive: isActive)
    guard isPlayable(at: itemIndex) else {
      slot.pause()
      return
    }
    guard isActive else {
      // A preloaded neighbour is loaded but not started: that is what makes the
      // swipe land on a ready frame without a second of black.
      slot.pause()
      return
    }
    if decision(for: itemIndex).autoplays || manuallyStarted.contains(item.id) {
      slot.play()
    } else {
      // `playOnDemand`: the item is rendered and tappable but does not start.
      slot.pause()
    }
  }

  // MARK: - Player callbacks

  /// Routes each slot's phase and time reports into the shared store.
  private func registerSlotCallbacks() {
    for (slotIndex, slot) in pool.enumerated() {
      slot.onPhaseChange = { [weak self] phase in
        Task { @MainActor in self?.playerPhaseChanged(slotIndex: slotIndex, phase: phase) }
      }
      slot.onTimeUpdate = { [weak self] timing in
        Task { @MainActor in self?.playerTimeChanged(slotIndex: slotIndex, timing: timing) }
      }
    }
  }

  private func playerPhaseChanged(slotIndex: Int, phase: VideoPlayerPhase) {
    recordPhase(slotIndex: slotIndex, phase: phase)
  }

  /// Writes a slot's phase into the store under the item it currently holds.
  private func recordPhase(slotIndex: Int, phase: VideoPlayerPhase) {
    guard let itemIndex = assignment[slotIndex], items.indices.contains(itemIndex) else { return }
    let itemID = items[itemIndex].id
    switch phase {
    case .empty, .loading:
      playback.loadingChanged(itemID: itemID, isLoading: phase == .loading)
    case .ready, .buffering, .failed:
      playback.statusChanged(itemID: itemID, phase: phase.playbackPhase)
    case .playing:
      playback.playingChanged(itemID: itemID, isPlaying: true)
    case .paused:
      playback.playingChanged(itemID: itemID, isPlaying: false)
    case .ended:
      playback.ended(itemID: itemID)
    }
  }

  private func playerTimeChanged(slotIndex: Int, timing: VideoPlayerTiming) {
    guard let itemIndex = assignment[slotIndex], items.indices.contains(itemIndex) else { return }
    let itemID = items[itemIndex].id
    playback.timeUpdated(
      itemID: itemID,
      currentTime: timing.currentTime,
      timeRemaining: timing.remaining)
    // The impression fires once per item, on the first update past the
    // threshold - the same `playbackStartTrackedRef` guard RN uses.
    _ = playback.trackPlaybackStartIfNeeded(itemID: itemID)
  }
}
