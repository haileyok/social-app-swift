import Foundation
import Lexicons
import SwiftAtproto
import Synchronization
import Testing

@testable import ComposerLogic

/// Video progress mapping and the video state reducer.
///
/// Ported from `state/videoProgress.ts` (+ `videoProgress.test.ts`) and the
/// `videoReducer` in `state/video.ts`.
@Suite("VideoProgressAndReducer")
struct VideoReducerTests {

  // MARK: - Progress phases

  @Test("didSkipVideoCompression distinguishes a real skip from a fallback")
  func skipDetection() {
    #expect(!didSkipVideoCompression(nil))
    #expect(didSkipVideoCompression(.belowByteThreshold))
    #expect(didSkipVideoCompression(.noWebCodecs))
    #expect(didSkipVideoCompression(.gif))
    #expect(!didSkipVideoCompression(.compressErrorFallback))
  }

  @Test("each phase maps onto one continuous timeline")
  func phaseMapping() {
    #expect(VideoProgressPhase.compressing.progress(for: 0) == 0)
    #expect(VideoProgressPhase.compressing.progress(for: 1) == 0.3)
    #expect(VideoProgressPhase.uploading.progress(for: 0) == 0.3)
    #expect(VideoProgressPhase.uploading.progress(for: 1) == 0.5)
    #expect(VideoProgressPhase.uploadingWithoutCompression.progress(for: 0) == 0)
    #expect(VideoProgressPhase.uploadingWithoutCompression.progress(for: 1) == 0.5)
    #expect(VideoProgressPhase.processing.progress(for: 0) == 0.5)
    #expect(VideoProgressPhase.processing.progress(for: 0.5) == 0.75)
    #expect(VideoProgressPhase.processing.progress(for: 1) == 1)
  }

  @Test("invalid phase progress is clamped")
  func phaseClamping() {
    #expect(VideoProgressPhase.uploading.progress(for: -1) == 0.3)
    #expect(VideoProgressPhase.uploading.progress(for: 2) == 0.5)
  }

  @Test("progress maps back to phase-local values")
  func withinPhase() {
    #expect(VideoProgressPhase.compressing.progressWithinPhase(0) == 0)
    #expect(VideoProgressPhase.compressing.progressWithinPhase(0.15) == 0.5)
    #expect(VideoProgressPhase.compressing.progressWithinPhase(0.3) == 1)
    #expect(VideoProgressPhase.compressing.progressWithinPhase(-1) == 0)
    #expect(VideoProgressPhase.compressing.progressWithinPhase(1) == 1)
  }

  @Test("advance never moves backwards")
  func advanceIsMonotonic() {
    let progressed = VideoProgressPhase.uploading.advance(0.5, to: 0.8)
    #expect(VideoProgressPhase.uploading.advance(progressed, to: 0) == progressed)
  }

  // MARK: - Reducer transitions

  @Test("a fresh video starts compressing with zero progress")
  func freshVideo() {
    let video = ComposerVideo.created(asset: asset())
    #expect(video.status == "compressing")
    #expect(video.progress == 0)
    #expect(video.altText.isEmpty)
    #expect(!video.isCancelled)
  }

  @Test("compressing advances to uploading and lands on the upload band")
  func compressingToUploading() {
    let video = ComposerVideo.created(asset: asset())
    let next = VideoReducer.reduce(
      video,
      .compressingToUploading(
        video: CompressedVideo(uri: "file:///out.mp4", mimeType: "video/mp4", size: 500),
        compressionSkipped: false,
        token: video.token))
    #expect(next.status == "uploading")
    #expect(next.progress == 0.3)
  }

  @Test("a skipped compression starts the upload on the no-compression band")
  func skippedCompressionBand() {
    let video = ComposerVideo.created(asset: asset())
    let next = VideoReducer.reduce(
      video,
      .compressingToUploading(
        video: CompressedVideo(
          uri: "file:///out.mp4", mimeType: "video/mp4", size: 500,
          passthroughReason: .belowByteThreshold),
        compressionSkipped: true,
        token: video.token))
    #expect(next.progress == 0)
  }

  @Test("uploading advances to processing and records the job id")
  func uploadingToProcessing() {
    let video = uploadingState()
    let next = VideoReducer.reduce(
      video, .uploadingToProcessing(jobId: "job-9", token: video.token))
    #expect(next.status == "processing")
    #expect(next.jobId == "job-9")
    #expect(next.progress == 0.5)
    #expect(next.jobStatus == nil)
  }

  @Test("update_job_status advances progress from the server percentage")
  func jobStatusProgress() {
    let video = processingState()
    let next = VideoReducer.reduce(
      video,
      .updateJobStatus(jobStatus: Fixtures.jobStatus(state: .jobStateEncoding, progress: 50), token: video.token))
    #expect(next.progress == 0.75)
    #expect(next.jobStatus?.progress == 50)
  }

  @Test("a job status without progress leaves progress alone")
  func jobStatusWithoutProgress() {
    let video = processingState()
    let next = VideoReducer.reduce(
      video,
      .updateJobStatus(jobStatus: Fixtures.jobStatus(state: .jobStateScanning), token: video.token))
    #expect(next.progress == 0.5)
  }

  @Test("a completed job moves to done with the blob and full progress")
  func toDone() {
    let video = processingState()
    let blob = Fixtures.blob(mimeType: "video/mp4")
    let next = VideoReducer.reduce(video, .toDone(blobRef: blob, token: video.token))
    #expect(next.status == "done")
    #expect(next.progress == 1)
    #expect(next.pendingBlob == blob)
  }

  @Test("to_done only applies from processing")
  func toDoneOnlyFromProcessing() {
    let video = ComposerVideo.created(asset: asset())
    let next = VideoReducer.reduce(
      video, .toDone(blobRef: Fixtures.blob(), token: video.token))
    #expect(next.status == "compressing")
  }

  @Test("to_error applies from any state and preserves what it knows")
  func toErrorFromAnyState() {
    let video = processingState()
    let next = VideoReducer.reduce(video, .toError(error: "boom", token: video.token))
    #expect(next.status == "error")
    #expect(next.asset != nil)
    #expect(next.jobId == "job-1")
    #expect(next.progress == 0.5)
  }

  @Test("alt text and captions can be edited in any state")
  func altAndCaptionsEditable() {
    var video = ComposerVideo.created(asset: asset())
    video = VideoReducer.reduce(video, .updateAltText(altText: "a clip", token: video.token))
    #expect(video.altText == "a clip")
    video = VideoReducer.reduce(
      video,
      .updateCaptions(
        captions: [VideoCaptionTrack(lang: "en", content: "WEBVTT")], token: video.token))
    #expect(video.captions.first?.content == "WEBVTT")
    let failed = VideoReducer.reduce(video, .toError(error: "x", token: video.token))
    #expect(failed.altText == "a clip")
    #expect(failed.captions.count == 1)
  }

  @Test("an action from a superseded token is dropped")
  func staleTokenDropped() {
    let video = ComposerVideo.created(asset: asset())
    let stale = VideoJobToken()
    let next = VideoReducer.reduce(
      video,
      .compressingToUploading(
        video: CompressedVideo(uri: "file:///out.mp4", mimeType: "video/mp4", size: 1),
        compressionSkipped: false,
        token: stale))
    #expect(next == video)
  }

  @Test("even a to_error from a stale token is dropped")
  func staleToErrorDropped() {
    let video = ComposerVideo.created(asset: asset())
    let next = VideoReducer.reduce(
      video, .toError(error: "late", token: VideoJobToken()))
    #expect(next.status == "compressing")
  }

  @Test("a cancelled video drops every later action")
  func cancelledDropsActions() {
    let video = ComposerVideo.created(asset: asset())
    let cancelled = VideoReducer.reduce(video, .cancel(token: video.token))
    #expect(cancelled.isCancelled)
    let next = VideoReducer.reduce(
      cancelled, .updateAltText(altText: "too late", token: video.token))
    #expect(next.altText.isEmpty)
  }

  @Test("the reduction outcome reports what happened")
  func reductionOutcomes() {
    let video = ComposerVideo.created(asset: asset())
    let stale = VideoReducer.reduceReporting(video, .cancel(token: VideoJobToken()))
    #expect(stale.outcome == .stale)
    let unexpected = VideoReducer.reduceReporting(
      video, .toDone(blobRef: Fixtures.blob(), token: video.token))
    #expect(unexpected.outcome == .unexpected(action: "to_done", state: "compressing"))
    let applied = VideoReducer.reduceReporting(video, .cancel(token: video.token))
    #expect(applied.outcome == .applied)
  }

  // MARK: - Helpers

  private func asset() -> ComposerVideoAsset {
    ComposerVideoAsset(uri: "file:///v.mp4", size: 1000, width: 1920, height: 1080)
  }

  private func uploadingState() -> ComposerVideo {
    let video = ComposerVideo.created(asset: asset())
    return VideoReducer.reduce(
      video,
      .compressingToUploading(
        video: CompressedVideo(uri: "file:///out.mp4", mimeType: "video/mp4", size: 500),
        compressionSkipped: false,
        token: video.token))
  }

  private func processingState() -> ComposerVideo {
    let uploading = uploadingState()
    return VideoReducer.reduce(
      uploading, .uploadingToProcessing(jobId: "job-1", token: uploading.token))
  }
}

/// The video upload orchestration and its poll policy.
///
/// Ported from `processVideo` in `src/view/composer/composer/state/video.ts`.
@Suite("VideoUploadOrchestrator")
struct VideoUploadOrchestratorTests {

  @Test("a job that completes on the first poll returns the blob")
  func completesImmediately() async {
    let blob = Fixtures.blob(mimeType: "video/mp4")
    let service = FakeVideoUploadService(
      statuses: [Fixtures.jobStatus(state: .jobStateCompleted, blob: blob)])
    let clock = FakeVideoPollClock()
    let orchestrator = VideoUploadOrchestrator(service: service, clock: clock)

    let outcome = await orchestrator.poll(jobId: "job-1")
    #expect(outcome == .completed(blob: blob))
  }

  @Test("a job that transitions through states polls until completion")
  func pollsThroughStates() async {
    let blob = Fixtures.blob(mimeType: "video/mp4")
    let service = FakeVideoUploadService(statuses: [
      Fixtures.jobStatus(state: .jobStateEncoding),
      Fixtures.jobStatus(state: .jobStateScanning),
      Fixtures.jobStatus(state: .jobStateCompleted, blob: blob),
    ])
    let clock = FakeVideoPollClock()
    let orchestrator = VideoUploadOrchestrator(service: service, clock: clock)

    let recorder = StatusRecorder()
    let outcome = await orchestrator.poll(jobId: "job-1") { status in
      recorder.record(status.state.rawValue)
    }
    #expect(outcome == .completed(blob: blob))
    #expect(recorder.values == ["JOB_STATE_ENCODING", "JOB_STATE_SCANNING"])
    #expect(clock.slept == [
      ComposerConstants.videoPollIntervalSeconds,
      ComposerConstants.videoPollIntervalSeconds,
    ])
  }

  @Test("a failed job reports the mapped message and stops polling")
  func failsImmediately() async {
    let service = FakeVideoUploadService(statuses: [
      Fixtures.jobStatus(state: .jobStateFailed, failureCode: .encodingFailure)
    ])
    let orchestrator = VideoUploadOrchestrator(
      service: service, clock: FakeVideoPollClock())
    let outcome = await orchestrator.poll(jobId: "job-1")
    #expect(outcome == .failed(message: VideoPipelineMessageID.couldNotBeEncoded.rawValue))
    #expect(service.jobStatusCallCount == 1)
  }

  @Test("a validation failure without a code still uses the error string")
  func legacyValidationFailure() async {
    let service = FakeVideoUploadService(statuses: [
      Fixtures.jobStatus(state: .jobStateFailed, error: "video_too_long", failureCode: nil)
    ])
    let orchestrator = VideoUploadOrchestrator(
      service: service, clock: FakeVideoPollClock())
    let outcome = await orchestrator.poll(jobId: "job-1")
    #expect(outcome == .failed(message: VideoPipelineMessageID.videoTooLong.rawValue))
  }

  @Test("a completed job with no blob is a failure")
  func completedWithoutBlob() async {
    let service = FakeVideoUploadService(statuses: [
      Fixtures.jobStatus(state: .jobStateCompleted, blob: nil)
    ])
    let orchestrator = VideoUploadOrchestrator(
      service: service, clock: FakeVideoPollClock())
    let outcome = await orchestrator.poll(jobId: "job-1")
    #expect(
      outcome
        == .failed(message: VideoPipelineMessageID.jobFailedToProcess.rawValue))
  }

  @Test("transport failures retry, then give up after the failure budget")
  func retriesThenGivesUp() async {
    let service = FakeVideoUploadService(
      statuses: [],
      errors: Array(repeating: FakeError.transport, count: 100))
    let clock = FakeVideoPollClock()
    let orchestrator = VideoUploadOrchestrator(
      service: service, clock: clock, maxPollFailures: 3)

    let outcome = await orchestrator.poll(jobId: "job-1")
    #expect(
      outcome == .gaveUp(message: VideoPipelineMessageID.genericFailure.rawValue))
    #expect(service.jobStatusCallCount == 3)
    // Each retry waits the longer retry interval, not the poll interval.
    #expect(clock.slept == Array(repeating: ComposerConstants.videoPollRetryIntervalSeconds, count: 2))
  }

  @Test("a transport failure followed by success resumes normally")
  func recoversAfterTransportFailure() async {
    let blob = Fixtures.blob(mimeType: "video/mp4")
    let service = FakeVideoUploadService(
      statuses: [
        Fixtures.jobStatus(state: .jobStateEncoding),
        Fixtures.jobStatus(state: .jobStateCompleted, blob: blob),
      ],
      errors: [FakeError.transport])
    let clock = FakeVideoPollClock()
    let orchestrator = VideoUploadOrchestrator(service: service, clock: clock)
    let outcome = await orchestrator.poll(jobId: "job-1")
    #expect(outcome == .completed(blob: blob))
  }

  @Test("an overall deadline produces a timeout")
  func deadlineTimesOut() async {
    let service = FakeVideoUploadService(statuses: [
      Fixtures.jobStatus(state: .jobStateEncoding)
    ])
    let clock = FakeVideoPollClock()
    let orchestrator = VideoUploadOrchestrator(service: service, clock: clock)
    let outcome = await orchestrator.poll(jobId: "job-1", deadlineSeconds: 3)
    #expect(outcome == .timedOut)
  }

  @Test("the full upload path runs start, parts and finish")
  func uploadPath() async throws {
    let service = FakeVideoUploadService(reportedProgress: [0.25, 0.5, 1.0])
    let orchestrator = VideoUploadOrchestrator(
      service: service, clock: FakeVideoPollClock())
    let recorder = StatusRecorder()
    let jobId = try await orchestrator.upload(
      fileURL: "file:///v.mp4",
      mimeType: "video/mp4",
      sizeBytes: 1000,
      onProgress: { recorder.record(String($0)) })
    #expect(jobId == "job-1")
    #expect(recorder.values == ["0.25", "0.5", "1.0"])
  }

  @Test("a startUpload failure propagates")
  func startUploadFailurePropagates() async {
    let service = FakeVideoUploadService()
    service.setStartUploadError(FakeError.transport)
    let orchestrator = VideoUploadOrchestrator(
      service: service, clock: FakeVideoPollClock())
    await #expect(throws: FakeError.transport) {
      try await orchestrator.upload(fileURL: "file:///v.mp4", mimeType: "video/mp4", sizeBytes: 1)
    }
  }

  @Test("the processing message mapper covers every failure code")
  func processingMessageMapping() {
    #expect(processingMessage(failureCode: .validationFailure, error: nil) == .couldNotBeProcessed)
    #expect(processingMessage(failureCode: .encodingFailure, error: nil) == .couldNotBeEncoded)
    #expect(processingMessage(failureCode: .pdsUploadFailure, error: nil) == .pdsUploadFailed)
    #expect(
      processingMessage(failureCode: .pdsUploadUnsupportedBlobSize, error: nil)
        == .pdsUnsupportedBlobSize)
    #expect(processingMessage(failureCode: .genericFailure, error: nil) == .genericFailure)
    #expect(processingMessage(failureCode: .validationFailure, error: "unsupported_codec") == .unsupportedCodec)
    #expect(processingMessage(failureCode: nil, error: "bad_aspect_ratio") == .badAspectRatio)
    #expect(processingMessage(failureCode: nil, error: "encoded_video_too_large") == .encodedVideoTooLarge)
    #expect(processingMessage(failureCode: nil, error: nil) == .genericFailure)
  }
}

/// A thread-safe recorder for values observed from `@Sendable` callbacks.
final class StatusRecorder: Sendable {
  private let storage = Mutex<[String]>([])

  func record(_ value: String) {
    storage.withLock { $0.append(value) }
  }

  var values: [String] { storage.withLock { $0 } }
}
