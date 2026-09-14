import Foundation

/// The playback lifecycle of one video, as data.
///
/// Port of the player states the RN immersive feed observes, with every
/// AVFoundation/expo-video type removed. RN learns these from its player's
/// events in `VideoItemInner` and `usePlaybackTelemetry`:
///
/// - `onLoadingChange` -> ``buffering`` / back to ``ready``;
/// - `onStatusChange` -> `readyToPlay` -> ``ready``, `error` -> ``failed``;
/// - `onPlayingChange` -> ``playing`` / ``paused``;
/// - `timeUpdate` reaching the end -> ``ended``.
///
/// The `.active` / `.inactive` distinction RN tracks via `onActiveChange` is
/// separate: it says whether the *player* is the visible one, and belongs to
/// ``VideoPlaybackState/isActive`` rather than to this enum, because a player can
/// be ready while inactive (that is exactly what the preload window produces).
public enum VideoPlaybackPhase: Sendable, Equatable {
  /// Nothing has been asked of this item yet.
  case idle
  /// A load has started and the first frame is not available.
  case loading
  /// The media is loaded and can start without further buffering.
  case ready
  /// Filling a buffer mid-playback.
  case buffering
  /// Playing.
  case playing
  /// Paused by the viewer or by the pager.
  case paused
  /// Reached the end of the media. RN loops, so this is a brief state.
  case ended
  /// Playback failed. `message` is the player's error text.
  case failed(message: String?)

  /// True while the media is rendering.
  public var isPlaying: Bool { self == .playing }

  /// True when playback has stopped and needs an explicit start.
  public var isPlaybackHalted: Bool {
    switch self {
    case .paused, .ended, .idle, .failed: return true
    case .loading, .ready, .buffering, .playing: return false
    }
  }

  /// True when the item cannot play without a reload.
  public var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }

  /// True when the item is loaded enough to show a frame.
  public var hasMedia: Bool {
    switch self {
    case .ready, .buffering, .playing, .paused, .ended: return true
    case .idle, .loading, .failed: return false
    }
  }
}

/// Everything known about one item's playback, as pure data.
public struct VideoPlaybackState: Sendable, Equatable {
  /// The item identity (`VideoItem.id`).
  public let itemID: String
  /// The post URI, the key RN's analytics and feedback use.
  public let postURI: String
  /// The playlist URL currently loaded into a player slot, if any.
  public let playlist: String?
  /// The lifecycle phase.
  public var phase: VideoPlaybackPhase
  /// Whether this item's player is the visible/active one.
  ///
  /// RN: the `isActive` flag from `onActiveChange`. Distinct from the pager's
  /// active index: a preloaded neighbor has a live player that is not active.
  public var isActive: Bool
  /// Whether the player is muted.
  public var isMuted: Bool
  /// The playback position, in seconds.
  public var currentTime: TimeInterval
  /// The time remaining, in seconds. RN shows this on the scrubber.
  public var timeRemaining: TimeInterval
  /// The highest `timeRemaining` seen, which recovers the duration.
  ///
  /// RN tracks exactly this (`maxTimeRemainingSeconds` in `VideoItemInner`) so it
  /// can convert `timeRemaining` into a progress figure for the report dialog.
  public var maxTimeRemaining: TimeInterval
  /// Whether a playback-start has already been recorded for this item, so the
  /// impression is reported once. RN: `playbackStartTrackedRef`.
  public var hasTrackedPlaybackStart: Bool

  public init(
    itemID: String,
    postURI: String,
    playlist: String? = nil,
    phase: VideoPlaybackPhase = .idle,
    isActive: Bool = false,
    isMuted: Bool = true,
    currentTime: TimeInterval = 0,
    timeRemaining: TimeInterval = 0,
    maxTimeRemaining: TimeInterval = 0,
    hasTrackedPlaybackStart: Bool = false
  ) {
    self.itemID = itemID
    self.postURI = postURI
    self.playlist = playlist
    self.phase = phase
    self.isActive = isActive
    self.isMuted = isMuted
    self.currentTime = currentTime
    self.timeRemaining = timeRemaining
    self.maxTimeRemaining = maxTimeRemaining
    self.hasTrackedPlaybackStart = hasTrackedPlaybackStart
  }

  /// The playback progress in seconds: `maxTimeRemaining - timeRemaining`.
  ///
  /// Port of the `reportDialogMetadata.current.videoTimestampSeconds` assignment
  /// in `VideoItemInner`. Clamped at zero.
  public var progressSeconds: TimeInterval {
    max(0, maxTimeRemaining - timeRemaining)
  }

  /// Whether playback has started, by RN's threshold.
  ///
  /// RN: `hasPlaybackStarted(progressSeconds)` with a 0.05 s threshold, which
  /// distinguishes real playback from zero-valued player callbacks while still
  /// representing the first frame.
  public var hasPlaybackStarted: Bool {
    VideoFeedLogic.hasPlaybackStarted(progressSeconds: progressSeconds)
  }
}

/// The RN `hasPlaybackStarted` predicate.
///
/// Port of `src/lib/media/video/analytics.ts`. A non-finite or negative value is
/// not a start.
public func hasPlaybackStarted(progressSeconds: TimeInterval) -> Bool {
  progressSeconds.isFinite && progressSeconds >= VideoFeedConstants.playbackStartThresholdSeconds
}

/// A per-item playback store, keyed by item identity.
///
/// This is the Swift counterpart of the state RN keeps *inside* each mounted
/// `VideoItem`: `isPlaying`, `isActive`, `isLoading`, `muted`, `timeRemaining`
/// and `error`. RN spreads that state across the component tree and the
/// `VideoVolumeContext`; hoisting it into one keyed store is what lets the Logic
/// layer be tested without mounting a player, and lets the Views package read a
/// single snapshot.
///
/// The store is a value type with mutating updates, so callers can hold it in
/// whatever isolation their layer uses. It never touches a player: the Views
/// package observes the store and issues imperative play/pause calls.
public struct VideoPlaybackStore: Sendable {
  /// The states, keyed by item id.
  public private(set) var states: [String: VideoPlaybackState]
  /// The item id whose player is currently active, if any.
  public private(set) var activeItemID: String?
  /// The default muted state new items inherit. RN initialises mute to `true`.
  public var defaultMuted: Bool

  public init(defaultMuted: Bool = true) {
    self.states = [:]
    self.activeItemID = nil
    self.defaultMuted = defaultMuted
  }

  /// The state for `itemID`, or `nil` when this item has never been touched.
  public func state(for itemID: String) -> VideoPlaybackState? {
    states[itemID]
  }

  /// Registers an item without changing its phase, returning its state.
  ///
  /// Called as the pager preloads a window, so a state exists before any player
  /// event arrives.
  @discardableResult
  public mutating func register(
    itemID: String, postURI: String, playlist: String?
  ) -> VideoPlaybackState {
    if var existing = states[itemID] {
      if existing.playlist != playlist {
        // A recycled slot pointed at a different playlist: the old media's
        // phase no longer describes this item.
        existing = VideoPlaybackState(
          itemID: itemID,
          postURI: postURI,
          playlist: playlist,
          phase: .loading,
          isActive: existing.isActive,
          isMuted: existing.isMuted)
      }
      states[itemID] = existing
      return existing
    }
    let state = VideoPlaybackState(
      itemID: itemID,
      postURI: postURI,
      playlist: playlist,
      phase: .loading,
      isMuted: defaultMuted)
    states[itemID] = state
    return state
  }

  /// Drops an item entirely, as when it leaves the list.
  public mutating func remove(itemID: String) {
    states.removeValue(forKey: itemID)
    if activeItemID == itemID { activeItemID = nil }
  }

  /// Keeps only the items in `itemIDs`, dropping everything else.
  ///
  /// The pager calls this when the item list shrinks so player state cannot leak
  /// across a feed refresh.
  public mutating func retainOnly(_ itemIDs: [String]) {
    let keep = Set(itemIDs)
    states = states.filter { keep.contains($0.key) }
    if let activeItemID, !keep.contains(activeItemID) { self.activeItemID = nil }
  }

  // MARK: - Player events

  /// The player started loading.
  public mutating func loadingChanged(itemID: String, isLoading: Bool) {
    guard var state = states[itemID] else { return }
    if isLoading {
      state.phase = .loading
    } else if state.phase == .loading {
      state.phase = .ready
    } else if state.phase == .buffering {
      state.phase = state.isActive ? .playing : .paused
    }
    states[itemID] = state
  }

  /// The player reported a status. RN: `onStatusChange` with
  /// `readyToPlay` / `error`.
  public mutating func statusChanged(itemID: String, phase: VideoPlaybackPhase) {
    guard var state = states[itemID] else { return }
    state.phase = phase
    states[itemID] = state
  }

  /// The player reported a failure.
  public mutating func failed(itemID: String, message: String?) {
    guard var state = states[itemID] else { return }
    state.phase = .failed(message: message)
    state.isActive = false
    states[itemID] = state
    if activeItemID == itemID { activeItemID = nil }
  }

  /// The player started or stopped playing.
  public mutating func playingChanged(itemID: String, isPlaying: Bool) {
    guard var state = states[itemID] else { return }
    if isPlaying {
      state.phase = .playing
    } else if state.phase == .playing || state.phase == .buffering {
      state.phase = .paused
    }
    states[itemID] = state
  }

  /// The player reached the end of the media.
  public mutating func ended(itemID: String) {
    guard var state = states[itemID] else { return }
    state.phase = .ended
    states[itemID] = state
  }

  /// The player became the visible one, or stopped being it.
  ///
  /// RN: `onActiveChange`. Making an item active implicitly deactivates the
  /// previously active one, matching RN's single-active-player model.
  public mutating func activeChanged(itemID: String, isActive: Bool) {
    if isActive {
      if let previous = activeItemID, previous != itemID, var previousState = states[previous] {
        previousState.isActive = false
        states[previous] = previousState
      }
      activeItemID = itemID
    } else if activeItemID == itemID {
      activeItemID = nil
    }
    guard var state = states[itemID] else { return }
    state.isActive = isActive
    states[itemID] = state
  }

  /// The mute state changed. RN: `onMutedChange`, ignored for GIFs.
  public mutating func mutedChanged(itemID: String, isMuted: Bool) {
    guard var state = states[itemID] else { return }
    state.isMuted = isMuted
    states[itemID] = state
  }

  /// A time update. RN: `onTimeUpdate`, which drives both the scrubber and the
  /// progress-based playback-start report.
  ///
  /// Non-finite values are ignored, exactly as RN's `Number.isFinite` guard does,
  /// so a player reporting `NaN` cannot corrupt the duration estimate.
  public mutating func timeUpdated(
    itemID: String, currentTime: TimeInterval, timeRemaining: TimeInterval
  ) {
    guard var state = states[itemID] else { return }
    if currentTime.isFinite, currentTime >= 0 {
      state.currentTime = currentTime
    }
    if timeRemaining.isFinite, timeRemaining >= 0 {
      state.timeRemaining = timeRemaining
      state.maxTimeRemaining = max(state.maxTimeRemaining, timeRemaining)
    } else if timeRemaining == .infinity {
      // RN also ignores infinity for the duration estimate.
      state.timeRemaining = timeRemaining
    }
    states[itemID] = state
  }

  /// Marks the playback-start report as sent, returning whether it should be
  /// sent now.
  ///
  /// Port of the `playbackStartTrackedRef` guard in `VideoItemInner`: the report
  /// fires once per item, on the first time update past the threshold. Returns
  /// `false` for every subsequent call.
  @discardableResult
  public mutating func trackPlaybackStartIfNeeded(itemID: String) -> Bool {
    guard var state = states[itemID] else { return false }
    guard !state.hasTrackedPlaybackStart, state.hasPlaybackStarted else { return false }
    state.hasTrackedPlaybackStart = true
    states[itemID] = state
    return true
  }

  // MARK: - Derived views

  /// The active item's state, if any.
  public var activeState: VideoPlaybackState? {
    activeItemID.flatMap { states[$0] }
  }

  /// True when any item is actively playing.
  public var isAnythingPlaying: Bool {
    states.values.contains { $0.phase.isPlaying }
  }

  /// The identities of the items in a playable phase, in insertion-stable order.
  public var registeredItemIDs: [String] {
    states.keys.sorted()
  }
}
