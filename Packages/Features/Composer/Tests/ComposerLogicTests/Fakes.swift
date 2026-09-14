import Foundation
import Lexicons
import RichText
import Synchronization
import SwiftAtproto

@testable import ComposerLogic

// MARK: - Video service

/// A scripted ``VideoUploadService``: a queue of job-status responses, plus
/// optional errors to inject, so the poll loop's success, failure, retry and
/// timeout paths can each be driven deterministically.
final class FakeVideoUploadService: VideoUploadService, @unchecked Sendable {

  struct State {
    /// The statuses to return from `jobStatus`, consumed in order. The last one
    /// repeats once the script is exhausted.
    var statuses: [App.Bsky.VideoDefs_JobStatus]
    var statusIndex = 0
    /// Per-call errors: entry `i` is thrown on call `i` when non-nil.
    var thrownErrors: [Error?]
    var errorIndex = 0
    /// How many times `jobStatus` was called.
    var jobStatusCallCount = 0
  }

  private let state: Mutex<State>
  /// The job id `startUpload` reserves and `finishUpload` returns.
  private let finishedJobId: Mutex<String>
  /// When set, `startUpload` throws this.
  private let startError = Mutex<Error?>(nil)
  /// When set, `uploadParts` throws this.
  private let partsError = Mutex<Error?>(nil)
  /// Progress values `uploadParts` reports.
  let reportedProgress: [Double]

  init(
    statuses: [App.Bsky.VideoDefs_JobStatus] = [],
    errors: [Error?] = [],
    finishedJobId: String = "job-1",
    reportedProgress: [Double] = []
  ) {
    self.state = Mutex(State(statuses: statuses, thrownErrors: errors))
    self.finishedJobId = Mutex(finishedJobId)
    self.reportedProgress = reportedProgress
  }

  /// How many times `jobStatus` was called.
  var jobStatusCallCount: Int {
    state.withLock { $0.jobStatusCallCount }
  }

  func setStartUploadError(_ error: Error?) { startError.withLock { $0 = error } }
  func setUploadPartsError(_ error: Error?) { partsError.withLock { $0 = error } }

  func startUpload(
    mimeType: String,
    sizeBytes: Int,
    hints: VideoUploadHints
  ) async throws -> VideoUploadHandle {
    if let error = startError.withLock({ $0 }) { throw error }
    return VideoUploadHandle(
      jobId: finishedJobId.withLock { $0 },
      partCount: 1,
      partSizeBytes: max(sizeBytes, 1),
      expiresAt: "2026-01-01T00:00:00.000Z")
  }

  func uploadParts(
    _ handle: VideoUploadHandle,
    fileURL: String,
    onProgress: @Sendable (Double) -> Void
  ) async throws {
    if let error = partsError.withLock({ $0 }) { throw error }
    for value in reportedProgress { onProgress(value) }
  }

  func finishUpload(_ handle: VideoUploadHandle) async throws -> String {
    finishedJobId.withLock { $0 }
  }

  func jobStatus(jobId: String) async throws -> App.Bsky.VideoDefs_JobStatus {
    let scripted = state.withLock { state -> ScriptedStatus in
      state.jobStatusCallCount += 1
      if state.errorIndex < state.thrownErrors.count {
        let error = state.thrownErrors[state.errorIndex]
        state.errorIndex += 1
        if let error { return .failure(error) }
      }
      guard !state.statuses.isEmpty else { return .failure(FakeError.noScript) }
      let status = state.statuses[min(state.statusIndex, state.statuses.count - 1)]
      state.statusIndex += 1
      return .status(status)
    }
    switch scripted {
    case .failure(let error): throw error
    case .status(let status): return status
    }
  }

  private enum ScriptedStatus {
    case status(App.Bsky.VideoDefs_JobStatus)
    case failure(Error)
  }
}

enum FakeError: Error, Sendable, Equatable {
  case noScript
  case transport
}

// MARK: - Clock

/// A clock whose `sleep` does not actually wait, and which records how long the
/// poller asked to sleep. `now()` advances by the total slept time, so an
/// overall deadline is reached in a bounded number of iterations.
final class FakeVideoPollClock: VideoPollClock, @unchecked Sendable {
  private let state: Mutex<State>

  struct State {
    var current: Date
    var slept: [Double] = []
  }

  init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
    self.state = Mutex(State(current: start))
  }

  /// Every duration passed to ``sleep(seconds:)``, in order.
  var slept: [Double] { state.withLock { $0.slept } }

  func now() -> Date { state.withLock { $0.current } }

  func sleep(seconds: Double) async throws {
    state.withLock {
      $0.slept.append(seconds)
      $0.current = $0.current.addingTimeInterval(seconds)
    }
  }
}

// MARK: - Drafts service

/// An in-memory ``ComposerDraftsService``, with hooks for injecting failures at
/// each of the four calls.
final class FakeDraftsService: ComposerDraftsService, @unchecked Sendable {
  struct State {
    var stored: [String: App.Bsky.DraftDefs_Draft] = [:]
    var order: [String] = []
    var calls: [String] = []
    var cursors: [String?] = []
    var cursorIndex = 0
    var createError: Error?
    var getDraftsError: Error?
    var deleteError: Error?
  }

  private let state: Mutex<State>
  /// An optional shared log, for asserting cross-fake ordering.
  let log: OperationLog?

  init(cursors: [String?] = [], log: OperationLog? = nil) {
    var initial = State()
    initial.cursors = cursors
    self.state = Mutex(initial)
    self.log = log
  }

  /// Every call made, for assertion.
  var calls: [String] { state.withLock { $0.calls } }

  func setCreateError(_ error: Error?) { state.withLock { $0.createError = error } }
  func setGetDraftsError(_ error: Error?) { state.withLock { $0.getDraftsError = error } }
  func setDeleteError(_ error: Error?) { state.withLock { $0.deleteError = error } }

  func getDrafts(cursor: String?) async throws -> App.Bsky.DraftGetDrafts_Output {
    log?.append("getDrafts")
    let result = state.withLock { state -> (views: [App.Bsky.DraftDefs_DraftView], next: String?, error: Error?) in
      state.calls.append("getDrafts(cursor: \(cursor ?? "nil"))")
      let views = state.order.compactMap { id -> App.Bsky.DraftDefs_DraftView? in
        guard let draft = state.stored[id] else { return nil }
        return App.Bsky.DraftDefs_DraftView(
          createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
          draft: draft,
          id: FormatString<TID>(rawValue: id),
          updatedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"))
      }
      let next = state.cursorIndex < state.cursors.count ? state.cursors[state.cursorIndex] : nil
      state.cursorIndex += 1
      return (views, next, state.getDraftsError)
    }
    if let error = result.error { throw error }
    return App.Bsky.DraftGetDrafts_Output(cursor: result.next, drafts: result.views)
  }

  func createDraft(_ draft: App.Bsky.DraftDefs_Draft) async throws -> String {
    log?.append("createDraft")
    let outcome = state.withLock { state -> (id: String?, error: Error?) in
      state.calls.append("createDraft")
      if let error = state.createError { return (nil, error) }
      let id = "draft-\(state.order.count + 1)"
      state.stored[id] = draft
      state.order.append(id)
      return (id, nil)
    }
    if let error = outcome.error { throw error }
    return outcome.id ?? ""
  }

  func updateDraft(id: String, draft: App.Bsky.DraftDefs_Draft) async throws {
    log?.append("updateDraft")
    state.withLock { state in
      state.calls.append("updateDraft(\(id))")
      // The server silently ignores unknown ids.
      if state.stored[id] != nil { state.stored[id] = draft }
    }
  }

  func deleteDraft(id: String) async throws {
    log?.append("deleteDraft")
    let error = state.withLock { state -> Error? in
      state.calls.append("deleteDraft(\(id))")
      if let error = state.deleteError { return error }
      state.stored.removeValue(forKey: id)
      state.order.removeAll { $0 == id }
      return nil
    }
    if let error { throw error }
  }

  /// The stored draft, for assertion.
  func draft(_ id: String) -> App.Bsky.DraftDefs_Draft? {
    state.withLock { $0.stored[id] }
  }

  func seed(_ id: String, _ draft: App.Bsky.DraftDefs_Draft) {
    state.withLock { state in
      state.stored[id] = draft
      state.order.append(id)
    }
  }
}

/// An in-memory ``ComposerDraftMediaStorage`` that records every operation, so
/// the "network first, local media second" ordering can be asserted.
final class FakeDraftMediaStorage: ComposerDraftMediaStorage, @unchecked Sendable {
  struct State {
    var files: [String: String] = [:]
    var operations: [String] = []
    var saveError: Error?
    var deleteError: Error?
  }

  private let state: Mutex<State>
  /// A shared log, so the test can interleave this fake's operations with the
  /// service's and assert the order.
  let log: OperationLog?

  init(existing: [String] = [], log: OperationLog? = nil) {
    var initial = State()
    for path in existing { initial.files[path] = "seed" }
    self.state = Mutex(initial)
    self.log = log
  }

  var operations: [String] { state.withLock { $0.operations } }

  func setSaveError(_ error: Error?) { state.withLock { $0.saveError = error } }
  func setDeleteError(_ error: Error?) { state.withLock { $0.deleteError = error } }

  func mediaExists(_ localRefPath: String) -> Bool {
    state.withLock { $0.files[localRefPath] != nil }
  }

  func saveMedia(localRefPath: String, sourcePath: String) async throws {
    log?.append("save(\(localRefPath))")
    let error = state.withLock { state -> Error? in
      state.operations.append("save(\(localRefPath))")
      if let error = state.saveError { return error }
      state.files[localRefPath] = sourcePath
      return nil
    }
    if let error { throw error }
  }

  func deleteMedia(localRefPath: String) async throws {
    log?.append("delete(\(localRefPath))")
    let error = state.withLock { state -> Error? in
      state.operations.append("delete(\(localRefPath))")
      if let error = state.deleteError { return error }
      state.files.removeValue(forKey: localRefPath)
      return nil
    }
    if let error { throw error }
  }
}

/// A shared, ordered log two fakes append to, so a test can assert that a server
/// call happened before a local media write.
final class OperationLog: Sendable {
  private let entries = Mutex<[String]>([])

  func append(_ entry: String) {
    entries.withLock { $0.append(entry) }
  }

  var all: [String] { entries.withLock { $0 } }
}

// MARK: - Fixtures

enum Fixtures {
  static let did = "did:plc:testuser"

  /// A blob with the given CID, built by decoding the wire shape.
  ///
  /// ``LexBlob`` exposes no public memberwise initializer (only an
  /// `init(original:mimeType:)`), so the fixture goes through the decoder, which
  /// is also a useful check that its `$type: "blob"` shape is right.
  static func blob(cid: String = "bafkreieq5jui4j25lacwomsqgvn7mq6bqjssdtj7t2amedkybi5bnljc5a", mimeType: String = "image/jpeg") -> LexBlob {
    let json = """
      {"$type":"blob","ref":{"$link":"\(cid)"},"mimeType":"\(mimeType)","size":1024}
      """
    do {
      return try JSONDecoder().decode(LexBlob.self, from: Data(json.utf8))
    } catch {
      fatalError("fixture blob failed to decode: \(error)")
    }
  }

  /// A job status in the given state.
  static func jobStatus(
    state: App.Bsky.VideoDefs_JobStatus_State,
    jobId: String = "job-1",
    progress: Int? = nil,
    error: String? = nil,
    failureCode: App.Bsky.VideoDefs_JobStatus_FailureCode? = nil,
    blob: LexBlob? = nil
  ) -> App.Bsky.VideoDefs_JobStatus {
    App.Bsky.VideoDefs_JobStatus(
      blob: blob,
      did: FormatString<DID>(rawValue: did),
      error: error,
      failureCode: failureCode,
      jobId: jobId,
      progress: progress,
      state: state)
  }

  /// A post draft with the given text.
  static func post(
    id: String = "post-0",
    text: String = "",
    labels: SelfLabelSet = SelfLabelSet(),
    embed: EmbedDraft = EmbedDraft()
  ) -> PostDraft {
    PostDraft(id: id, richText: RichTextValue(text: text), labels: labels, embed: embed)
  }

  /// A thread with the given posts and default gates.
  static func thread(
    posts: [PostDraft],
    threadgate: [ThreadgateAllowUISetting] = [.everybody],
    embeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem] = [],
    detachedEmbeddingUris: [String] = []
  ) -> ThreadDraft {
    ThreadDraft(
      posts: posts,
      postgate: App.Bsky.FeedPostgate(
        createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
        detachedEmbeddingUris: detachedEmbeddingUris.map {
          FormatString<ATURI>(rawValue: $0)
        },
        embeddingRules: embeddingRules,
        post: FormatString<ATURI>(rawValue: "")),
      threadgate: threadgate)
  }

  /// A composer state around a thread.
  static func state(_ thread: ThreadDraft) -> ComposerState {
    ComposerState(thread: thread)
  }

  /// A deterministic CID provider for the record builder: a fake CID derived
  /// from the record's text, so reply refs are assertable without a DAG-CBOR
  /// encoder.
  static func fakeCID(_ record: App.Bsky.FeedPost) -> String {
    "bafyfake\(abs(record.text.hashValue))"
  }

  /// A fixed instant, so record payloads are byte-stable.
  static let fixedDate = Date(timeIntervalSince1970: 1_767_225_600)

  /// The canonical JSON of a record, with sorted keys, for exact-payload
  /// comparison.
  static func canonicalJSON(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
      let text = String(bytes: data, encoding: .utf8)
    else { return "<unencodable>" }
    return text
  }

  /// The JSON object of a record, for field-level assertions.
  static func json(_ value: some Encodable) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(value),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
  }
}
