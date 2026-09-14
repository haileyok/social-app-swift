import Foundation

/// One continuous progress timeline across the whole client-side video pipeline.
///
/// Ported from `src/view/com/composer/state/videoProgress.ts`. The RN code keeps
/// progress monotonic instead of showing three separate 0 -> 100 cycles;
/// backend processing covers the entire server-side job, so it maps onto the
/// final half.
public enum VideoProgressPhase: String, Sendable, CaseIterable {
  case compressing
  case uploading
  case uploadingWithoutCompression
  case processing

  /// `PHASE_RANGES` - the `[start, end]` band this phase occupies.
  public var range: (start: Double, end: Double) {
    switch self {
    case .compressing: (0, 0.3)
    case .uploading: (0.3, 0.5)
    case .uploadingWithoutCompression: (0, 0.5)
    case .processing: (0.5, 1)
    }
  }

  /// Maps phase-local progress (0...1, clamped) onto the global timeline.
  public func progress(for phaseProgress: Double) -> Double {
    let (start, end) = range
    let clamped = min(1, max(0, phaseProgress))
    return start + (end - start) * clamped
  }

  /// Maps global progress back onto phase-local progress (clamped to 0...1).
  public func progressWithinPhase(_ progress: Double) -> Double {
    let (start, end) = range
    return min(1, max(0, (progress - start) / (end - start)))
  }

  /// Advances a global progress value, never moving backwards.
  ///
  /// Ported from `advanceVideoProgress`. The RN comment explains why: a
  /// transport retry or a compression fallback must not make the indicator
  /// jump backwards.
  public func advance(_ currentProgress: Double, to phaseProgress: Double) -> Double {
    max(currentProgress, progress(for: phaseProgress))
  }
}

/// Why the compressor returned the original file instead of a new one.
///
/// Ported from `VideoCompressSkipReason` in `lib/media/video/types.ts`. Only the
/// cases the progress mapping branches on are modelled.
public enum VideoCompressSkipReason: String, Hashable, Sendable {
  case belowByteThreshold = "below-byte-threshold"
  case noWebCodecs = "no-webcodecs"
  case gif
  case compressErrorFallback = "compress-error-fallback"
}

/// Whether a passthrough counts as a *real* skip.
///
/// Ported from `didSkipVideoCompression`. A failed compression attempt that
/// falls back to the original file is **not** a skip: keeping it on the
/// post-compression upload band is what stops the global indicator jumping
/// backwards.
public func didSkipVideoCompression(_ passthroughReason: VideoCompressSkipReason?) -> Bool {
  guard let passthroughReason else { return false }
  return passthroughReason != .compressErrorFallback
}
