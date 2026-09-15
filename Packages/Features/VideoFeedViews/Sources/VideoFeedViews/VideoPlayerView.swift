import AVFoundation
import CoreMedia
import Observation
import VideoFeedLogic

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

  /// True when the slot will not start without an explicit instruction.
  var isPlaybackHalted: Bool {
    switch self {
    case .paused, .ended, .empty, .failed: return true
    case .loading, .ready, .buffering, .playing: return false
    }
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

  /// How far ahead the player buffers. One item of lookahead is what makes a
  /// swipe land on a ready frame; the pool size bounds the cost at three.
  static let forwardBufferDuration: TimeInterval = 2

  @ObservationIgnored private let player = AVPlayer()
  @ObservationIgnored private let playerLayer = AVPlayerLayer()
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var statusObservation: NSKeyValueObservation?
  @ObservationIgnored private var bufferObservation: NSKeyValueObservation?
  @ObservationIgnored private var rateObservation: NSKeyValueObservation?
  @ObservationIgnored private var endObserver: NSObjectProtocol?

  /// Reports the phase so the owner can drive the shared playback store.
  var onPhaseChange: ((VideoPlayerPhase) -> Void)?
  /// Reports a time update, so the store can drive its progress-based report.
  var onTimeUpdate: ((VideoPlayerTiming) -> Void)?

  init() {
    playerLayer.player = player
    playerLayer.videoGravity = .resizeAspect
    // The pool is built once and lives as long as the screen, so the observers
    // are installed here rather than per item; the item-scoped ones are in
    // `attach(playlist:loops:)`.
    rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
      let rate = player.rate
      Task { @MainActor in self?.rateChanged(rate) }
    }
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      MainActor.assumeIsolated { self?.timeChanged(time) }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let item = note.object as? AVPlayerItem else { return }
      MainActor.assumeIsolated {
        guard let self, item === self.player.currentItem else { return }
        self.reachedEnd()
      }
    }
  }

  deinit {
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
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
    if case .failed = phase, let playlist {
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
    case .failed:
      setPhase(.failed(message))
    case .unknown:
      break
    @unknown default:
      break
    }
  }

  private func bufferChanged(likelyToKeepUp: Bool, isEmpty: Bool) {
    guard player.currentItem != nil, phase != .failed else { return }
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

  private func timeChanged(_ time: CMTime) {
    guard let item = player.currentItem else { return }
    let seconds = time.seconds
    guard seconds.isFinite else { return }
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
