import Foundation
import Lexicons
import SwiftAtproto

/// The multipart-upload steps the composer performs against the video service.
///
/// Deliberately narrow: the composer owns the *orchestration* (when to poll, how
/// many failures to tolerate, what a completed job means), while the transport
/// owns the HTTP. RN's `multipart/api.ts` implements this same surface.
public protocol VideoUploadService: Sendable {
  /// `app.bsky.video.startUpload` - reserves a multipart upload.
  func startUpload(
    mimeType: String,
    sizeBytes: Int,
    hints: VideoUploadHints
  ) async throws -> VideoUploadHandle

  /// Uploads the bytes for a reserved job. Implementations split into parts.
  func uploadParts(
    _ handle: VideoUploadHandle,
    fileURL: String,
    onProgress: @Sendable (Double) -> Void
  ) async throws

  /// `app.bsky.video.finishUpload` - completes the multipart upload and returns
  /// the job to poll.
  func finishUpload(_ handle: VideoUploadHandle) async throws -> String

  /// `app.bsky.video.getJobStatus` - the current processing state.
  func jobStatus(jobId: String) async throws -> App.Bsky.VideoDefs_JobStatus
}

/// The advisory dimensions and name sent with `startUpload`.
///
/// The lexicon calls these "advisory, non-authoritative ... used only for early
/// failure"; bundling them keeps the service surface small.
public struct VideoUploadHints: Hashable, Sendable {
  /// Optional client-provided file name.
  public var name: String?
  /// Declared width in pixels.
  public var width: Int?
  /// Declared height in pixels.
  public var height: Int?
  /// Declared duration in milliseconds.
  public var durationMs: Int?

  public init(name: String? = nil, width: Int? = nil, height: Int? = nil, durationMs: Int? = nil) {
    self.name = name
    self.width = width
    self.height = height
    self.durationMs = durationMs
  }
}

/// A reserved multipart upload.
public struct VideoUploadHandle: Hashable, Sendable {
  /// The job id returned by `startUpload`.
  public var jobId: String
  /// The number of parts the file must be split into.
  public var partCount: Int
  /// The size of each part, except possibly the last.
  public var partSizeBytes: Int
  /// When the reservation expires.
  public var expiresAt: String

  public init(jobId: String, partCount: Int, partSizeBytes: Int, expiresAt: String) {
    self.jobId = jobId
    self.partCount = partCount
    self.partSizeBytes = partSizeBytes
    self.expiresAt = expiresAt
  }
}

/// What the poll loop decided.
public enum VideoPollOutcome: Sendable, Equatable {
  /// The job completed and returned a blob.
  case completed(blob: LexBlob)
  /// The job failed, with the message the UI should show.
  case failed(message: String)
  /// Polling gave up after ``ComposerConstants/videoMaxPollFailures``
  /// consecutive request failures.
  case gaveUp(message: String)
  /// The job exceeded the caller's deadline.
  case timedOut
  /// The caller cancelled.
  case cancelled
}

/// Messages the video pipeline surfaces.
///
/// Ported from `getProcessingErrorMessage` / `getValidationErrorMessage` /
/// `getUploadErrorMessage` in `state/video.ts`. Kept as stable identifiers
/// rather than English strings, so the views package owns the copy.
public enum VideoPipelineMessageID: String, Hashable, Sendable {
  case videoTooLong
  case badAspectRatio
  case unsupportedCodec
  case encodedVideoTooLarge
  case couldNotBeProcessed
  case couldNotBeEncoded
  case pdsUploadFailed
  case pdsUnsupportedBlobSize
  case genericFailure
  case jobFailedToProcess
  case uploadNotAllowed
  case uploadDisabled
  case couldNotDetermineUploadPermission
  case exceededDailyBytes
  case exceededDailyVideos
  case accountTooNew
  case confirmEmail
  case network
  case unknown
}

/// Maps a `getJobStatus` failure onto a message identifier.
///
/// Ported from `getProcessingErrorMessage`, including its backwards-compatibility
/// rule: workers deployed before `failureCode` existed only send `error`, so a
/// known validation error is honoured even when no code is present.
public func processingMessage(
  failureCode: App.Bsky.VideoDefs_JobStatus_FailureCode?,
  error: String?
) -> VideoPipelineMessageID {
  let validation = validationMessage(error)

  if failureCode == .validationFailure {
    return validation ?? .couldNotBeProcessed
  }
  if failureCode == nil, let validation {
    return validation
  }

  switch failureCode {
  case .encodingFailure: return .couldNotBeEncoded
  case .pdsUploadFailure: return .pdsUploadFailed
  case .pdsUploadUnsupportedBlobSize: return .pdsUnsupportedBlobSize
  case .genericFailure, .none, .some(._other): return .genericFailure
  case .validationFailure: return .couldNotBeProcessed
  }
}

/// Maps the job's plain `error` string onto a validation message.
///
/// Ported from `getValidationErrorMessage`.
public func validationMessage(_ error: String?) -> VideoPipelineMessageID? {
  switch error {
  case "video_too_long": return .videoTooLong
  case "bad_aspect_ratio": return .badAspectRatio
  case "unsupported_codec": return .unsupportedCodec
  case "encoded_video_too_large": return .encodedVideoTooLarge
  default: return nil
  }
}

/// The video upload orchestration.
///
/// Ported from `processVideo` in `state/video.ts`, minus compression (which is a
/// platform media concern) and minus the UI dispatch (which the caller does by
/// feeding the returned actions into ``VideoReducer``).
///
/// The poll policy is preserved exactly:
///
/// - Between successful polls, wait ``ComposerConstants/videoPollIntervalSeconds``.
/// - A poll request that *throws with no status* counts as a failure; after 50
///   consecutive failures the job is reported failed.
/// - A job in `JOB_STATE_FAILED` fails immediately, with the mapped message.
/// - A job in `JOB_STATE_COMPLETED` with no blob fails immediately.
public struct VideoUploadOrchestrator: Sendable {
  let service: VideoUploadService
  let clock: VideoPollClock
  let maxPollFailures: Int

  public init(
    service: VideoUploadService,
    clock: VideoPollClock = SystemVideoPollClock(),
    maxPollFailures: Int = ComposerConstants.videoMaxPollFailures
  ) {
    self.service = service
    self.clock = clock
    self.maxPollFailures = maxPollFailures
  }

  /// Runs startUpload, the part uploads and finishUpload, returning the job to
  /// poll.
  ///
  /// - Parameter onProgress: byte-level upload progress, 0...1.
  /// - Throws: whatever the service throws.
  public func upload(
    fileURL: String,
    mimeType: String,
    sizeBytes: Int,
    name: String? = nil,
    width: Int? = nil,
    height: Int? = nil,
    durationMs: Int? = nil,
    onProgress: @Sendable @escaping (Double) -> Void = { _ in }
  ) async throws -> String {
    let handle = try await service.startUpload(
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      hints: VideoUploadHints(
        name: name, width: width, height: height, durationMs: durationMs))
    try await service.uploadParts(handle, fileURL: fileURL, onProgress: onProgress)
    return try await service.finishUpload(handle)
  }

  /// Polls `getJobStatus` until the job finishes, fails, or the deadline passes.
  ///
  /// - Parameter deadlineSeconds: an overall budget; `nil` polls indefinitely.
  /// - Parameter onStatus: invoked with every status received, so the caller can
  ///   feed ``VideoAction/updateJobStatus(jobStatus:token:)`` into the reducer.
  public func poll(
    jobId: String,
    deadlineSeconds: Double? = nil,
    onStatus: @Sendable @escaping (App.Bsky.VideoDefs_JobStatus) -> Void = { _ in }
  ) async -> VideoPollOutcome {
    let startedAt = clock.now()
    var pollFailures = 0

    while true {
      if let deadlineSeconds, clock.now().timeIntervalSince(startedAt) >= deadlineSeconds {
        return .timedOut
      }

      let attempt = await pollOnce(jobId: jobId)
      switch attempt {
      case .completed(let blob):
        return .completed(blob: blob)
      case .failed(let message):
        return .failed(message: message)
      case .transportFailure(let retryable):
        pollFailures += 1
        guard retryable, pollFailures < maxPollFailures else {
          return .gaveUp(message: VideoPipelineMessageID.genericFailure.rawValue)
        }
        try? await clock.sleep(seconds: ComposerConstants.videoPollRetryIntervalSeconds)
      case .inProgress(let status):
        pollFailures = 0
        onStatus(status)
        try? await clock.sleep(seconds: ComposerConstants.videoPollIntervalSeconds)
      }
    }
  }

  /// The result of a single `getJobStatus` call.
  enum PollAttempt {
    /// The job finished with a blob.
    case completed(blob: LexBlob)
    /// The job failed definitively; no retry will help.
    case failed(message: String)
    /// The request failed at the transport level. `retryable` is false when the
    /// job reported a specific failure, which is also terminal.
    case transportFailure(retryable: Bool)
    /// The job is still running.
    case inProgress(status: App.Bsky.VideoDefs_JobStatus)
  }

  /// Performs one poll and classifies the outcome.
  func pollOnce(jobId: String) async -> PollAttempt {
    let response: App.Bsky.VideoDefs_JobStatus
    do {
      response = try await service.jobStatus(jobId: jobId)
    } catch {
      return .transportFailure(retryable: true)
    }

    switch response.state {
    case .jobStateCompleted:
      guard let blob = response.blob else {
        // A completed job without a blob is a hard failure; RN throws here.
        return .failed(message: VideoPipelineMessageID.jobFailedToProcess.rawValue)
      }
      return .completed(blob: blob)
    case .jobStateFailed:
      return .failed(
        message: processingMessage(failureCode: response.failureCode, error: response.error)
          .rawValue)
    default:
      return .inProgress(status: response)
    }
  }
}

/// Internal signals the orchestrator uses to distinguish a job failure from a
/// transport failure.
enum VideoOrchestrationError: Error, Sendable, Equatable {
  case completedWithoutBlob
  case jobFailed
}
