import Foundation
import Lexicons
import SwiftAtproto

/// The picked video, before compression.
///
/// Ported from the subset of `ImagePickerAsset` that the video pipeline reads.
public struct ComposerVideoAsset: Hashable, Sendable {
  /// A local file path or URI.
  public var uri: String
  /// Declared mime type.
  public var mimeType: String
  /// Byte size of the picked file.
  public var size: Int
  /// Width in pixels.
  public var width: Double
  /// Height in pixels.
  public var height: Double
  /// Duration in milliseconds, when known.
  public var durationMs: Int?

  public init(
    uri: String,
    mimeType: String = "video/mp4",
    size: Int,
    width: Double,
    height: Double,
    durationMs: Int? = nil
  ) {
    self.uri = uri
    self.mimeType = mimeType
    self.size = size
    self.width = width
    self.height = height
    self.durationMs = durationMs
  }
}

/// The compressed (or passed-through) video file handed to the uploader.
///
/// Ported from `CompressedVideo` in `lib/media/video/types.ts`.
public struct CompressedVideo: Hashable, Sendable {
  /// A local file path or URI of the upload-ready file.
  public var uri: String
  public var mimeType: String
  public var size: Int
  /// Set when the compressor returned the original file; see
  /// ``VideoCompressSkipReason``.
  public var passthroughReason: VideoCompressSkipReason?

  public init(
    uri: String,
    mimeType: String,
    size: Int,
    passthroughReason: VideoCompressSkipReason? = nil
  ) {
    self.uri = uri
    self.mimeType = mimeType
    self.size = size
    self.passthroughReason = passthroughReason
  }
}

/// A caption track attached to a video.
///
/// The RN state holds a `File` because captions are read lazily at publish time;
/// the composer state here holds the already-read VTT text, which is the only
/// thing the publish path uses.
public struct VideoCaptionTrack: Hashable, Sendable {
  /// The BCP-47 language tag.
  public var lang: String
  /// The WebVTT file contents.
  public var content: String

  public init(lang: String, content: String) {
    self.lang = lang
    self.content = content
  }
}

/// A per-upload identity token.
///
/// Stands in for the RN `AbortController.signal`: every action an async task
/// dispatches carries the token it started with, and the reducer drops any
/// action whose token no longer matches the state's. That is what makes a
/// removed-then-replaced video immune to late dispatches from the old job.
public struct VideoJobToken: Hashable, Sendable {
  public let id: String

  public init(id: String = UUID().uuidString) {
    self.id = id
  }
}

/// The video attachment state machine.
///
/// Ported from the `VideoState` union in
/// `src/view/com/composer/state/video.ts`. The RN union branches on `status`;
/// this enum keeps the shared fields on each case so a switch is exhaustive.
public enum ComposerVideo: Hashable, Sendable {
  case error(VideoErrorState)
  case compressing(VideoCompressingState)
  case uploading(VideoUploadingState)
  case processing(VideoProcessingState)
  case done(VideoDoneState)

  /// The status discriminator, matching the RN `status` string.
  public var status: String {
    switch self {
    case .error: "error"
    case .compressing: "compressing"
    case .uploading: "uploading"
    case .processing: "processing"
    case .done: "done"
    }
  }

  /// Global pipeline progress, 0...1.
  public var progress: Double {
    switch self {
    case .error(let state): state.progress
    case .compressing(let state): state.progress
    case .uploading(let state): state.progress
    case .processing(let state): state.progress
    case .done: 1
    }
  }

  /// The job token that guards this state's actions.
  public var token: VideoJobToken {
    switch self {
    case .error(let state): state.token
    case .compressing(let state): state.token
    case .uploading(let state): state.token
    case .processing(let state): state.token
    case .done(let state): state.token
    }
  }

  /// Whether a cancellation has been recorded for this token.
  public var isCancelled: Bool {
    switch self {
    case .error(let state): state.isCancelled
    case .compressing(let state): state.isCancelled
    case .uploading(let state): state.isCancelled
    case .processing(let state): state.isCancelled
    case .done(let state): state.isCancelled
    }
  }

  /// The picked asset, when one is still known.
  public var asset: ComposerVideoAsset? {
    switch self {
    case .error(let state): state.asset
    case .compressing(let state): state.asset
    case .uploading(let state): state.asset
    case .processing(let state): state.asset
    case .done(let state): state.asset
    }
  }

  /// The compressed file, once compression has produced one.
  public var video: CompressedVideo? {
    switch self {
    case .error(let state): state.video
    case .compressing: nil
    case .uploading(let state): state.video
    case .processing(let state): state.video
    case .done(let state): state.video
    }
  }

  /// The upload job id, while one is known.
  public var jobId: String? {
    switch self {
    case .error(let state): state.jobId
    case .processing(let state): state.jobId
    case .compressing, .uploading, .done: nil
    }
  }

  /// Alt text, editable in every state.
  public var altText: String {
    switch self {
    case .error(let state): state.altText
    case .compressing(let state): state.altText
    case .uploading(let state): state.altText
    case .processing(let state): state.altText
    case .done(let state): state.altText
    }
  }

  /// Caption tracks, editable in every state.
  public var captions: [VideoCaptionTrack] {
    switch self {
    case .error(let state): state.captions
    case .compressing(let state): state.captions
    case .uploading(let state): state.captions
    case .processing(let state): state.captions
    case .done(let state): state.captions
    }
  }

  /// The published blob, present only once the job has completed.
  public var pendingBlob: LexBlob? {
    if case .done(let state) = self { return state.pendingBlob }
    return nil
  }

  /// The processing job status, present only while processing.
  public var jobStatus: App.Bsky.VideoDefs_JobStatus? {
    if case .processing(let state) = self { return state.jobStatus }
    return nil
  }

  /// A new video state in the `compressing` phase.
  ///
  /// Ported from `createVideoState`.
  public static func created(
    asset: ComposerVideoAsset,
    token: VideoJobToken = VideoJobToken()
  ) -> ComposerVideo {
    .compressing(
      VideoCompressingState(
        progress: 0,
        token: token,
        asset: asset,
        altText: "",
        captions: [],
        isCancelled: false))
  }
}

/// Fields shared by every video state.
public protocol VideoStateFields: Hashable, Sendable {
  var progress: Double { get }
  var token: VideoJobToken { get }
  var isCancelled: Bool { get }
  var altText: String { get }
  var captions: [VideoCaptionTrack] { get }
}

/// The failed video state. Mirrors `ErrorState`.
public struct VideoErrorState: VideoStateFields {
  public var progress: Double
  public var token: VideoJobToken
  public var isCancelled: Bool
  public var error: String
  public var asset: ComposerVideoAsset?
  public var video: CompressedVideo?
  public var jobId: String?
  public var altText: String
  public var captions: [VideoCaptionTrack]

  public init(
    progress: Double,
    token: VideoJobToken,
    isCancelled: Bool = false,
    error: String,
    asset: ComposerVideoAsset?,
    video: CompressedVideo?,
    jobId: String?,
    altText: String,
    captions: [VideoCaptionTrack]
  ) {
    self.progress = progress
    self.token = token
    self.isCancelled = isCancelled
    self.error = error
    self.asset = asset
    self.video = video
    self.jobId = jobId
    self.altText = altText
    self.captions = captions
  }
}

/// The compressing state. Mirrors `CompressingState`.
public struct VideoCompressingState: VideoStateFields {
  public var progress: Double
  public var token: VideoJobToken
  public var isCancelled: Bool
  public var asset: ComposerVideoAsset
  public var altText: String
  public var captions: [VideoCaptionTrack]

  public init(
    progress: Double,
    token: VideoJobToken,
    asset: ComposerVideoAsset,
    altText: String,
    captions: [VideoCaptionTrack],
    isCancelled: Bool = false
  ) {
    self.progress = progress
    self.token = token
    self.isCancelled = isCancelled
    self.asset = asset
    self.altText = altText
    self.captions = captions
  }
}

/// The uploading state. Mirrors `UploadingState`.
public struct VideoUploadingState: VideoStateFields {
  public var progress: Double
  public var token: VideoJobToken
  public var isCancelled: Bool
  /// Whether the compressor returned the original file (a real skip, not a
  /// failed compression fallback).
  public var compressionSkipped: Bool
  public var asset: ComposerVideoAsset
  public var video: CompressedVideo
  public var altText: String
  public var captions: [VideoCaptionTrack]

  public init(
    progress: Double,
    token: VideoJobToken,
    compressionSkipped: Bool,
    asset: ComposerVideoAsset,
    video: CompressedVideo,
    altText: String,
    captions: [VideoCaptionTrack],
    isCancelled: Bool = false
  ) {
    self.progress = progress
    self.token = token
    self.isCancelled = isCancelled
    self.compressionSkipped = compressionSkipped
    self.asset = asset
    self.video = video
    self.altText = altText
    self.captions = captions
  }
}

/// The server-processing state. Mirrors `ProcessingState`.
public struct VideoProcessingState: VideoStateFields {
  public var progress: Double
  public var token: VideoJobToken
  public var isCancelled: Bool
  public var asset: ComposerVideoAsset
  public var video: CompressedVideo
  public var jobId: String
  /// The last status seen from `getJobStatus`; `nil` until the first response.
  public var jobStatus: App.Bsky.VideoDefs_JobStatus?
  public var altText: String
  public var captions: [VideoCaptionTrack]

  public init(
    progress: Double,
    token: VideoJobToken,
    asset: ComposerVideoAsset,
    video: CompressedVideo,
    jobId: String,
    jobStatus: App.Bsky.VideoDefs_JobStatus?,
    altText: String,
    captions: [VideoCaptionTrack],
    isCancelled: Bool = false
  ) {
    self.progress = progress
    self.token = token
    self.isCancelled = isCancelled
    self.asset = asset
    self.video = video
    self.jobId = jobId
    self.jobStatus = jobStatus
    self.altText = altText
    self.captions = captions
  }
}

/// The completed state. Mirrors `DoneState`; `progress` is pinned to 1.
public struct VideoDoneState: VideoStateFields {
  public var progress: Double { 1 }
  public var token: VideoJobToken
  public var isCancelled: Bool
  public var asset: ComposerVideoAsset
  public var video: CompressedVideo
  /// The uploaded blob returned by the completed job.
  public var pendingBlob: LexBlob
  public var altText: String
  public var captions: [VideoCaptionTrack]

  public init(
    token: VideoJobToken,
    asset: ComposerVideoAsset,
    video: CompressedVideo,
    pendingBlob: LexBlob,
    altText: String,
    captions: [VideoCaptionTrack],
    isCancelled: Bool = false
  ) {
    self.token = token
    self.isCancelled = isCancelled
    self.asset = asset
    self.video = video
    self.pendingBlob = pendingBlob
    self.altText = altText
    self.captions = captions
  }
}
