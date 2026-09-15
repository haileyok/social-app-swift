import AVFoundation
import CoreMedia
import Observation
import VideoFeedLogic

/// One selectable caption track the player offers for an item.
///
/// These come from the player's legible media selection group rather than from
/// the record: `app.bsky.embed.video#main` declares caption blobs by CID
/// (``VideoCaptionTrack`` in `VideoFeedLogic`), and dereferencing one to a
/// playable URL needs the account's authenticated blob endpoint, which this
/// package does not own. A stream with embedded captions therefore offers its
/// tracks here, and a stream whose captions live only on the record offers none.
struct VideoCaptionOption: Identifiable, Equatable {
  /// The option's index in its media selection group, which is what selection
  /// uses: `AVMediaSelectionOption` exposes no stable identifier.
  let id: String
  /// The track's display name, e.g. `English`.
  let name: String
  /// The track's BCP-47 language tag, when the track carries one.
  let language: String?
}

/// The current and total time of a playing item, as the overlay reads it.
struct VideoPlayerTiming: Equatable {
  /// The playhead position in seconds.
  var currentTime: Double
  /// The media duration in seconds. Zero until the item reports one.
  var duration: Double

  /// The playback position as a `0...1` fraction, or zero when unknown.
  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(1, max(0, currentTime / duration))
  }

  /// The time left, in seconds.
  var remaining: Double { max(0, duration - currentTime) }

  static let zero = VideoPlayerTiming(currentTime: 0, duration: 0)
}

/// The lifecycle of one recycled player slot.
///
/// This is the AVFoundation side of ``VideoPlaybackPhase`` in `VideoFeedLogic`:
/// that type models the states the UI reasons about, and this enum is what
/// `AVPlayer` actually reports, so the two never have to be confused and the
/// view layer holds no policy of its own.
enum VideoPlayerPhase: Equatable {
  /// No item is attached to the slot.
  case empty
  /// The item is attached and the first frame is not available yet.
  case loading
  /// The media is loaded and can start without further buffering.
  case ready
  /// Filling a buffer mid-playback.
  case buffering
  /// Playing.
  case playing
  /// Paused, by the viewer or by the pager.
  case paused
  /// Reached the end. A looping (GIF) item restarts from here.
  case ended
  /// Playback failed; the associated value is the player's message.
  case failed(String?)

  /// The matching ``VideoPlaybackPhase`` for the shared playback store.
  var playbackPhase: VideoPlaybackPhase {
    switch self {
    case .empty: return .idle
    case .loading: return .loading
    case .ready: return .ready
    case .buffering: return .buffering
    case .playing: return .playing
    case .paused: return .paused
    case .ended: return .ended
    case .failed(let message): return .failed(message: message)
    }
  }

  /// True while the media is rendering.
  var isPlaying: Bool { self == .playing }

  /// True when the slot cannot play without a reload.
  ///
  /// The `failed` case carries a message, so it cannot be compared with `==` in
  /// an expression; every call site uses this instead.
  var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }

  /// True when the slot will not start without an explicit instruction.
  var isPlaybackHalted: Bool {
    switch self {
    case .paused, .ended, .empty, .failed: return true
    case .loading, .ready, .buffering, .playing: return false
    }
  }
}

/// Owns the `AVPlayer` and the observer registrations that must be removed when
/// the slot goes away.
///
/// The removal cannot happen in the slot's own `deinit`: the slot is main-actor
/// isolated, and a `deinit` is not, so it may not touch isolated state. Giving
/// the player and the registration tokens to a small nonisolated box means the
/// cleanup runs when the slot releases the box, without the slot needing a
/// `deinit` at all.
private final class VideoPlayerObserverCleanup: @unchecked Sendable {
  /// The player every observer is registered against.
  let player = AVPlayer()
  /// The periodic time-observer token, removed on release.
  var timeObserver: Any?
  /// The notification tokens, removed on release.
  var notificationTokens: [NSObjectProtocol] = []

  deinit {
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    for token in notificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
  }

  /// Stores a notification token for removal on release.
  func add(_ token: NSObjectProtocol) {
    notificationTokens.append(token)
  }
}

/// One recycled player slot: the `AVPlayer`, the item it holds, and an
/// `AVPlayerLayer` for the view to show.
///
/// Port of the three-player pool in `src/screens/VideoFeed/index.tsx`, with the
/// policy removed. The screen there builds a plain array of player handles
/// recycled by `index % 3`; ``playerSlotAssignments(activeIndex:count:poolSize:)``
/// in `VideoFeedLogic` owns that arithmetic, the controller decides which slot
/// holds which item, and this class only carries out the resulting attachment.
///
/// The slot never decides *whether* to play: `play()` and `pause()` are issued
/// from the autoplay decision, which is what keeps the moderation gate and the
/// autoplay preference in one place.
@MainActor
@Observable
final class VideoPlayerSlot {
  /// The item's HLS playlist URL, or `nil` when the slot is empty.
  private(set) var playlist: String?
  /// Whether the item loops. A GIF presentation loops; a standard video does not.
  private(set) var loops = false
  /// The slot's lifecycle phase.
  private(set) var phase: VideoPlayerPhase = .empty
  /// The current and total time, for the scrubber.
  private(set) var timing: VideoPlayerTiming = .zero
  /// The mute state. A slot starts muted, matching the RN volume context.
  private(set) var isMuted = true
  /// The caption tracks the current item offers, empty when it has none.
  private(set) var legibleOptions: [VideoCaptionOption] = []
  /// The selected caption track's id, or `nil` when captions are off.
  private(set) var selectedCaptionID: String?

  /// How far ahead the player buffers. One item of lookahead is what makes a
  /// swipe land on a ready frame; the pool size bounds the cost at three.
  static let forwardBufferDuration: TimeInterval = 2

  @ObservationIgnored private let cleanup = VideoPlayerObserverCleanup()
  @ObservationIgnored private let playerLayer = AVPlayerLayer()
  @ObservationIgnored private var statusObservation: NSKeyValueObservation?
  @ObservationIgnored private var bufferObservation: NSKeyValueObservation?
  @ObservationIgnored private var rateObservation: NSKeyValueObservation?

  /// Reports the phase so the owner can drive the shared playback store.
  var onPhaseChange: ((VideoPlayerPhase) -> Void)?
  /// Reports a time update, so the store can drive its progress-based report.
  var onTimeUpdate: ((VideoPlayerTiming) -> Void)?

  private var player: AVPlayer { cleanup.player }

  init() {
    playerLayer.player = player
    playerLayer.videoGravity = .resizeAspect
    // The pool is built once and lives as long as the screen, so the player-wide
    // observers are installed here rather than per item; the item-scoped ones are
    // installed by `attach(playlist:loops:)`.
    rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
      let rate = player.rate
      Task { @MainActor in self?.rateChanged(rate) }
    }
    cleanup.timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      let seconds = time.seconds
      Task { @MainActor in self?.timeChanged(seconds) }
    }
    cleanup.add(
      NotificationCenter.default.addObserver(
        forName: AVPlayerItem.didPlayToEndTimeNotification,
        object: nil,
        queue: .main
      ) { [weak self] note in
        let item = note.object as? AVPlayerItem
        Task { @MainActor in
          guard let self, let item, item === self.player.currentItem else { return }
          self.reachedEnd()
        }
      })
  }

  /// The layer the SwiftUI surface hosts.
  var layer: AVPlayerLayer { playerLayer }

  /// The item currently attached, for duration queries.
  var currentItem: AVPlayerItem? { player.currentItem }

  // MARK: - Attachment

  /// Points the slot at an item, or empties it.
  ///
  /// The playlist is the identity: re-attaching the same URL and loop flag is a
  /// no-op, so a view update that fires while the item is already loaded cannot
  /// restart playback. A different URL replaces the item and returns the slot to
  /// ``VideoPlayerPhase/loading``.
  ///
  /// - Parameters:
  ///   - playlist: the HLS playlist, or `nil` to empty the slot.
  ///   - loops: whether the item restarts when it reaches its end.
  func attach(playlist: String?, loops: Bool) {
    guard self.playlist != playlist || self.loops != loops else { return }
    self.playlist = playlist
    self.loops = loops
    timing = .zero
    observeItem(nil)
    guard let playlist, let url = URL(string: playlist) else {
      player.replaceCurrentItem(with: nil)
      setPhase(.empty)
      return
    }
    let item = AVPlayerItem(url: url)
    item.preferredForwardBufferDuration = Self.forwardBufferDuration
    player.replaceCurrentItem(with: item)
    observeItem(item)
    setPhase(.loading)
  }

  /// Empties the slot, releasing the item. Used when an index leaves the
  /// preload window.
  func detach() {
    attach(playlist: nil, loops: false)
  }

  // MARK: - Transport

  /// Starts playback, reloading first when the previous load failed.
  func play() {
    if phase.isFailed, let playlist {
      self.playlist = nil
      attach(playlist: playlist, loops: loops)
    }
    guard player.currentItem != nil else { return }
    player.play()
  }

  /// Pauses playback, leaving the frame on screen.
  func pause() {
    guard player.currentItem != nil else { return }
    player.pause()
  }

  /// Restarts from the beginning and plays. Used by a looping item at its end.
  func restart() {
    guard player.currentItem != nil else { return }
    player.seek(to: .zero)
    player.play()
  }

  /// Sets the mute state.
  func setMuted(_ muted: Bool) {
    isMuted = muted
    player.isMuted = muted
  }

  /// Seeks to a `0...1` progress fraction, for the scrubber.
  func seek(toProgress fraction: Double) {
    guard player.currentItem != nil, timing.duration > 0 else { return }
    let seconds = min(max(0, fraction), 1) * timing.duration
    player.seek(
      to: CMTime(seconds: seconds, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero)
  }

  // MARK: - Captions

  /// Selects a caption track, or turns captions off when `id` is `nil`.
  ///
  /// Selection goes through the item's legible media selection group, which is
  /// what `AVPlayer` uses for both embedded and sidecar captions on an HLS
  /// stream. `id` is the option's index in the group, which
  /// ``VideoCaptionOption/id`` carries.
  func selectCaption(id: String?) {
    guard let item = player.currentItem,
      let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    else { return }
    let option = id.flatMap(Int.init).flatMap { index in
      group.options.indices.contains(index) ? group.options[index] : nil
    }
    item.select(option, in: group)
    selectedCaptionID = option == nil ? nil : id
  }

  /// Refreshes the offered caption tracks from the current item.
  ///
  /// Called when the item reaches `.readyToPlay`: before the asset is loaded the
  /// selection group is not populated, so an item that carries captions reports
  /// none until it is ready.
  private func refreshLegibleOptions() {
    guard let item = player.currentItem,
      let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    else {
      legibleOptions = []
      selectedCaptionID = nil
      return
    }
    // The selection container is the item's `currentMediaSelection`; the group
    // itself holds no selection state.
    let current = item.currentMediaSelection.selectedMediaOption(in: group)
    legibleOptions = group.options.enumerated().map { index, option in
      VideoCaptionOption(
        id: "\(index)",
        name: option.displayName,
        language: option.locale?.identifier)
    }
    selectedCaptionID = current.flatMap { selected in
      group.options.firstIndex { $0 === selected }.map(String.init)
    }
  }

  // MARK: - Observation

  /// Moves the KVO observations from the previous item to `item`.
  ///
  /// `AVPlayerItem.status` and `isPlaybackLikelyToKeepUp` are observed on the
  /// item itself rather than through a `currentItem` keypath: the nested
  /// optional keypath is not a valid KVO target, and an item-scoped observation
  /// is also what lets the callbacks be dropped when the item is replaced.
  private func observeItem(_ item: AVPlayerItem?) {
    statusObservation?.invalidate()
    bufferObservation?.invalidate()
    statusObservation = nil
    bufferObservation = nil
    guard let item else { return }
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      let status = item.status
      let message = item.error?.localizedDescription
      Task { @MainActor in self?.statusChanged(status, message: message) }
    }
    bufferObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .initial]) {
      [weak self] item, _ in
      let likely = item.isPlaybackLikelyToKeepUp
      let empty = item.isPlaybackBufferEmpty
      Task { @MainActor in self?.bufferChanged(likelyToKeepUp: likely, isEmpty: empty) }
    }
  }

  private func statusChanged(_ status: AVPlayerItem.Status, message: String?) {
    guard player.currentItem != nil else { return }
    switch status {
    case .readyToPlay:
      if phase == .loading { setPhase(.ready) }
      // The legible selection group is only populated once the asset has loaded,
      // so an item that carries captions reports none before this point.
      refreshLegibleOptions()
    case .failed:
      setPhase(.failed(message))
    case .unknown:
      break
    @unknown default:
      break
    }
  }

  private func bufferChanged(likelyToKeepUp: Bool, isEmpty: Bool) {
    guard player.currentItem != nil, !phase.isFailed else { return }
    if isEmpty, !likelyToKeepUp, phase == .playing || phase == .ready {
      setPhase(.buffering)
    } else if likelyToKeepUp, phase == .buffering {
      setPhase(player.rate > 0 ? .playing : .paused)
    }
  }

  /// The rate is the only reliable "is it really rendering" signal: a failed or
  /// stalled item reports a zero rate without any status change.
  private func rateChanged(_ rate: Float) {
    guard player.currentItem != nil, player.currentItem?.status != .failed else { return }
    if rate == 0, phase == .playing { setPhase(.paused) }
    if rate > 0, phase != .playing { setPhase(.playing) }
  }

  private func timeChanged(_ seconds: Double) {
    guard let item = player.currentItem, seconds.isFinite else { return }
    let duration = item.duration.seconds
    timing = VideoPlayerTiming(
      currentTime: seconds,
      duration: duration.isFinite && duration > 0 ? duration : timing.duration)
    onTimeUpdate?(timing)
  }

  private func reachedEnd() {
    setPhase(.ended)
    if loops { restart() }
  }

  private func setPhase(_ next: VideoPlayerPhase) {
    guard phase != next else { return }
    phase = next
    onPhaseChange?(next)
  }
}
