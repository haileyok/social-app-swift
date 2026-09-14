import Foundation
import Lexicons
import SwiftAtproto

/// An action the video pipeline dispatches into the reducer.
///
/// Ported from the `VideoAction` union in `state/video.ts`. Every case carries
/// the ``VideoJobToken`` of the task that produced it; the reducer drops any
/// action whose token no longer matches the state's (the RN code compares
/// `AbortSignal` identity and checks `aborted`).
public enum VideoAction: Sendable {
  /// Compression finished; the upload is starting.
  case compressingToUploading(video: CompressedVideo, compressionSkipped: Bool, token: VideoJobToken)
  /// The upload was accepted; server-side processing has begun.
  case uploadingToProcessing(jobId: String, token: VideoJobToken)
  /// The pipeline failed with a user-presentable message.
  case toError(error: String, token: VideoJobToken)
  /// The job completed and returned a blob.
  case toDone(blobRef: LexBlob, token: VideoJobToken)
  /// Byte-level progress within the current phase (0...1).
  case updateProgress(progress: Double, token: VideoJobToken)
  /// Alt text edited.
  case updateAltText(altText: String, token: VideoJobToken)
  /// Captions edited.
  case updateCaptions(captions: [VideoCaptionTrack], token: VideoJobToken)
  /// A `getJobStatus` response arrived.
  case updateJobStatus(jobStatus: App.Bsky.VideoDefs_JobStatus, token: VideoJobToken)
  /// The job was cancelled; the reducer marks the state so late actions stop.
  case cancel(token: VideoJobToken)
  /// The token of the task that produced this action.
  var token: VideoJobToken {
    switch self {
    case .compressingToUploading(_, _, let token): token
    case .uploadingToProcessing(_, let token): token
    case .toError(_, let token): token
    case .toDone(_, let token): token
    case .updateProgress(_, let token): token
    case .updateAltText(_, let token): token
    case .updateCaptions(_, let token): token
    case .updateJobStatus(_, let token): token
    case .cancel(let token): token
    }
  }

  /// The action name, for the "unexpected action" diagnostic.
  var name: String {
    switch self {
    case .compressingToUploading: "compressing_to_uploading"
    case .uploadingToProcessing: "uploading_to_processing"
    case .toError: "to_error"
    case .toDone: "to_done"
    case .updateProgress: "update_progress"
    case .updateAltText: "update_alt_text"
    case .updateCaptions: "update_captions"
    case .updateJobStatus: "update_job_status"
    case .cancel: "cancel"
    }
  }
}

/// What the reducer did with an action, for callers that want to log.
public enum VideoReductionOutcome: Sendable, Equatable {
  /// The state changed.
  case applied
  /// The action was stale (its token no longer matches) and was dropped.
  case stale
  /// The action did not apply in the current state.
  case unexpected(action: String, state: String)
}

/// The video state reducer.
///
/// Ported from `videoReducer` in `state/video.ts`. Two behaviours are easy to
/// miss and are preserved deliberately:
///
/// - An action whose token has been superseded (or whose state is cancelled)
///   is dropped **entirely**, including `to_error` — the RN check runs before
///   the `to_error` branch.
/// - `to_error` applies from any state, but `to_done` only applies from
///   `processing`.
public enum VideoReducer {
  /// Applies `action` to `state`, returning the new state.
  public static func reduce(_ state: ComposerVideo, _ action: VideoAction) -> ComposerVideo {
    reduceReporting(state, action).state
  }

  /// Applies `action`, also reporting what happened.
  ///
  /// Named separately from ``reduce(_:_:)`` because a tuple-returning overload
  /// is ambiguous at call sites that discard the outcome.
  public static func reduceReporting(
    _ state: ComposerVideo,
    _ action: VideoAction
  ) -> (state: ComposerVideo, outcome: VideoReductionOutcome) {
    if state.isCancelled || action.token != state.token {
      return (state, .stale)
    }

    switch action {
    case .cancel:
      return (markCancelled(state), .applied)

    case .toError(let error, _):
      return (toErrorState(state, error: error), .applied)

    case .updateAltText(let altText, _):
      return (withAltText(state, altText), .applied)

    case .updateCaptions(let captions, _):
      return (withCaptions(state, captions), .applied)

    case .updateProgress(let progress, _):
      return applyProgress(state, progress, action: action)

    case .compressingToUploading(let video, let compressionSkipped, _):
      return applyCompressingToUploading(
        state, video: video, compressionSkipped: compressionSkipped, action: action)

    case .uploadingToProcessing(let jobId, _):
      return applyUploadingToProcessing(state, jobId: jobId, action: action)

    case .updateJobStatus(let jobStatus, _):
      return applyJobStatus(state, jobStatus, action: action)

    case .toDone(let blobRef, _):
      return applyDone(state, blobRef: blobRef, action: action)
    }
  }

  /// Moves compressing -> uploading, landing on the band the compression did or
  /// did not skip.
  static func applyCompressingToUploading(
    _ state: ComposerVideo, video: CompressedVideo, compressionSkipped: Bool, action: VideoAction
  ) -> (state: ComposerVideo, outcome: VideoReductionOutcome) {
    guard case .compressing(let compressing) = state else {
      return (state, .unexpected(action: action.name, state: state.status))
    }
    let phase: VideoProgressPhase =
      compressionSkipped ? .uploadingWithoutCompression : .uploading
    return (
      .uploading(
        VideoUploadingState(
          progress: phase.progress(for: 0),
          token: compressing.token,
          compressionSkipped: compressionSkipped,
          asset: compressing.asset,
          video: video,
          altText: compressing.altText,
          captions: compressing.captions)),
      .applied)
  }

  /// Moves uploading -> processing and records the job id.
  static func applyUploadingToProcessing(
    _ state: ComposerVideo, jobId: String, action: VideoAction
  ) -> (state: ComposerVideo, outcome: VideoReductionOutcome) {
    guard case .uploading(let uploading) = state else {
      return (state, .unexpected(action: action.name, state: state.status))
    }
    return (
      .processing(
        VideoProcessingState(
          progress: VideoProgressPhase.processing.progress(for: 0),
          token: uploading.token,
          asset: uploading.asset,
          video: uploading.video,
          jobId: jobId,
          jobStatus: nil,
          altText: uploading.altText,
          captions: uploading.captions)),
      .applied)
  }

  /// Records a `getJobStatus` response and advances progress from its percentage.
  static func applyJobStatus(
    _ state: ComposerVideo,
    _ jobStatus: App.Bsky.VideoDefs_JobStatus,
    action: VideoAction
  ) -> (state: ComposerVideo, outcome: VideoReductionOutcome) {
    guard case .processing(let processing) = state else {
      return (state, .unexpected(action: action.name, state: state.status))
    }
    var next = processing
    next.jobStatus = jobStatus
    if let progress = jobStatus.progress {
      next.progress = VideoProgressPhase.processing.advance(
        processing.progress, to: Double(progress) / 100)
    }
    return (.processing(next), .applied)
  }

  /// Moves processing -> done with the uploaded blob.
  static func applyDone(
    _ state: ComposerVideo, blobRef: LexBlob, action: VideoAction
  ) -> (state: ComposerVideo, outcome: VideoReductionOutcome) {
    guard case .processing(let processing) = state else {
      return (state, .unexpected(action: action.name, state: state.status))
    }
    return (
      .done(
        VideoDoneState(
          token: processing.token,
          asset: processing.asset,
          video: processing.video,
          pendingBlob: blobRef,
          altText: processing.altText,
          captions: processing.captions)),
      .applied)
  }

  /// Applies byte-level progress within the current phase.
  ///
  /// A skipped compression uploads on its own band, so the indicator does not
  /// jump backwards when compression is bypassed.
  static func applyProgress(
    _ state: ComposerVideo, _ progress: Double, action: VideoAction
  ) -> (state: ComposerVideo, outcome: VideoReductionOutcome) {
    switch state {
    case .compressing(let compressing):
      var next = compressing
      next.progress = VideoProgressPhase.compressing.advance(compressing.progress, to: progress)
      return (.compressing(next), .applied)
    case .uploading(let uploading):
      let phase: VideoProgressPhase =
        uploading.compressionSkipped ? .uploadingWithoutCompression : .uploading
      var next = uploading
      next.progress = phase.advance(uploading.progress, to: progress)
      return (.uploading(next), .applied)
    default:
      return (state, .unexpected(action: action.name, state: state.status))
    }
  }

  /// The copy with alt text replaced (used by the composer reducer directly).
  public static func withAltText(_ state: ComposerVideo, _ altText: String) -> ComposerVideo {
    switch state {
    case .error(var s): s.altText = altText; return .error(s)
    case .compressing(var s): s.altText = altText; return .compressing(s)
    case .uploading(var s): s.altText = altText; return .uploading(s)
    case .processing(var s): s.altText = altText; return .processing(s)
    case .done(var s): s.altText = altText; return .done(s)
    }
  }

  /// The copy with captions replaced.
  public static func withCaptions(
    _ state: ComposerVideo, _ captions: [VideoCaptionTrack]
  ) -> ComposerVideo {
    switch state {
    case .error(var s): s.captions = captions; return .error(s)
    case .compressing(var s): s.captions = captions; return .compressing(s)
    case .uploading(var s): s.captions = captions; return .uploading(s)
    case .processing(var s): s.captions = captions; return .processing(s)
    case .done(var s): s.captions = captions; return .done(s)
    }
  }

  /// The copy with cancellation recorded, so later actions are dropped.
  public static func markCancelled(_ state: ComposerVideo) -> ComposerVideo {
    switch state {
    case .error(var s): s.isCancelled = true; return .error(s)
    case .compressing(var s): s.isCancelled = true; return .compressing(s)
    case .uploading(var s): s.isCancelled = true; return .uploading(s)
    case .processing(var s): s.isCancelled = true; return .processing(s)
    case .done(var s): s.isCancelled = true; return .done(s)
    }
  }

  /// Moves any state into `error`, carrying forward everything it knows.
  ///
  /// Mirrors the `to_error` branch, which preserves `progress`, `asset`,
  /// `video`, `jobId`, `altText` and `captions` from whatever state it fired in.
  public static func toErrorState(_ state: ComposerVideo, error: String) -> ComposerVideo {
    .error(
      VideoErrorState(
        progress: state.progress,
        token: state.token,
        isCancelled: state.isCancelled,
        error: error,
        asset: state.asset,
        video: state.video,
        jobId: state.jobId,
        altText: state.altText,
        captions: state.captions))
  }
}
