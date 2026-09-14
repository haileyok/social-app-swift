import Foundation
import QueryStore
import Synchronization

/// A deterministic fetcher whose delay, failures and results are scripted.
///
/// Tests configure the script before running a fetch and assert against the
/// recorded call count afterwards, so "was the request de-duplicated?" and
/// "was it refetched after the clock advanced?" become plain assertions.
final class ScriptedFetcher<Value: Sendable>: @unchecked Sendable {
  /// How one call should behave.
  enum Outcome: Sendable {
    /// Return this value.
    case value(Value)
    /// Throw this error.
    case failure(any Error)
    /// Wait for `milliseconds`, then return this value.
    case delayed(Value, milliseconds: Int)
    /// Wait for `milliseconds`, then throw.
    case delayedFailure(any Error, milliseconds: Int)
  }

  private let state = Mutex<State>(State())

  private struct State {
    var script: [Outcome] = []
    var fallback: Value?
    var calls: [QueryFetchRequest] = []
  }

  init(_ script: [Outcome] = [], fallback: Value? = nil) {
    state.withLock {
      $0.script = script
      $0.fallback = fallback
    }
  }

  /// Number of times the fetcher has been called.
  var callCount: Int { state.withLock { $0.calls.count } }

  /// The requests the fetcher received, in order.
  var requests: [QueryFetchRequest] { state.withLock { $0.calls } }

  /// The cursors the fetcher received, in order.
  var cursors: [String?] { state.withLock { $0.calls.map(\.cursor) } }

  /// Appends outcomes to the script.
  func enqueue(_ outcomes: Outcome...) {
    state.withLock { $0.script.append(contentsOf: outcomes) }
  }

  /// Sets the value returned once the script is exhausted.
  func setFallback(_ value: Value?) {
    state.withLock { $0.fallback = value }
  }

  /// Performs one call: records the request and plays the next script entry.
  func call(_ request: QueryFetchRequest) async throws -> Value {
    let outcome: Outcome? = state.withLock { state in
      state.calls.append(request)
      return state.script.isEmpty ? nil : state.script.removeFirst()
    }
    guard let outcome else {
      guard let fallback = state.withLock({ $0.fallback }) else {
        throw QueryStoreTestError.scriptExhausted
      }
      return fallback
    }
    switch outcome {
    case .value(let value):
      return value
    case .failure(let error):
      throw error
    case .delayed(let value, let milliseconds):
      try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
      return value
    case .delayedFailure(let error, let milliseconds):
      try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
      throw error
    }
  }

  /// A closure suitable for the `fetcher:` parameter.
  var closure: @Sendable (QueryFetchRequest) async throws -> Value {
    { [self] request in try await call(request) }
  }
}

/// An error with a stable description, for asserting on thrown values.
struct TestError: Error, Equatable, CustomStringConvertible, Sendable {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var description: String { message }
}

enum QueryStoreTestError: Error {
  case scriptExhausted
  case timedOut
}

/// Records values from a `@Sendable` closure, following the repo's
/// `@unchecked Sendable` recorder idiom from the ATProtoClient tests.
final class Recorder<Value: Sendable>: @unchecked Sendable {
  private let state = Mutex<[Value]>([])

  func record(_ value: Value) {
    state.withLock { $0.append(value) }
  }

  var values: [Value] { state.withLock { $0 } }
  var count: Int { state.withLock { $0.count } }
  var last: Value? { state.withLock { $0.last } }
  var isEmpty: Bool { state.withLock { $0.isEmpty } }
}

/// Records `QueryEvent` values. `QueryEvent` is not `Equatable`, so helpers here
/// assert on its shape.
final class EventRecorder: @unchecked Sendable {
  private let state = Mutex<[String]>([])

  func record(_ event: QueryEvent) {
    state.withLock { $0.append(EventRecorder.describe(event)) }
  }

  var descriptions: [String] { state.withLock { $0 } }

  func count(of description: String) -> Int {
    state.withLock { events in events.filter { $0 == description }.count }
  }

  var closure: @Sendable (QueryEvent) -> Void {
    { [self] event in record(event) }
  }

  /// A stable, assertion-friendly name for an event.
  static func describe(_ event: QueryEvent) -> String {
    switch event {
    case .fetchStarted(let key, let reason): return "started:\(key.description):\(reason.rawValue)"
    case .fetchSucceeded(let key, _): return "succeeded:\(key.description)"
    case .fetchFailed(let key, _, let hadData): return "failed:\(key.description):hadData=\(hadData)"
    case .dataSet(let key, _): return "dataSet:\(key.description)"
    case .removed(let key): return "removed:\(key.description)"
    case .removedAll: return "removedAll"
    case .restored(let count): return "restored:\(count)"
    }
  }
}

/// An in-memory persistence sink that counts its traffic.
final class InMemoryPersistSink: QueryPersistSink, @unchecked Sendable {
  private let state = Mutex<State>(State())

  private struct State {
    var snapshots: [String: PersistedSnapshot] = [:]
    var saves = 0
    var loads = 0
    var removes = 0
  }

  func save(_ snapshot: PersistedSnapshot) async throws {
    state.withLock {
      $0.snapshots[snapshot.scope] = snapshot
      $0.saves += 1
    }
  }

  func load(scope: String) async throws -> PersistedSnapshot? {
    state.withLock {
      $0.loads += 1
      return $0.snapshots[scope]
    }
  }

  func remove(scope: String) async throws {
    state.withLock {
      $0.snapshots[scope] = nil
      $0.removes += 1
    }
  }

  var saveCount: Int { state.withLock { $0.saves } }
  var loadCount: Int { state.withLock { $0.loads } }
  var removeCount: Int { state.withLock { $0.removes } }

  func snapshot(scope: String) -> PersistedSnapshot? {
    state.withLock { $0.snapshots[scope] }
  }

  /// Seeds a snapshot directly, to stage a restore.
  func seed(_ snapshot: PersistedSnapshot) {
    state.withLock { $0.snapshots[snapshot.scope] = snapshot }
  }
}

/// A payload used across the tests: a paginated list of post ids.
struct FeedPagePayload: QueryPayload, Equatable {
  static let payloadVersion = 1

  var postIds: [String]
  var cursor: String?

  /// Builds the store's page form of this payload.
  func page(requestCursor: String? = nil) -> QueryPage<String> {
    QueryPage(items: postIds, cursor: cursor, requestCursor: requestCursor)
  }

  /// Builds infinite data holding this payload as its single page.
  func infiniteData(requestCursor: String? = nil) -> InfiniteQueryData<String> {
    InfiniteQueryData(pages: [page(requestCursor: requestCursor)])
  }
}

/// A non-paginated payload for single-shot query tests.
struct ProfilePayload: QueryPayload, Equatable {
  var did: String
  var displayName: String
}

/// Key roots used by the tests.
enum TestRoot {
  static let feed = "feed"
  static let profile = "profile"
  static let persistedFeed = "persisted-feed"
}

/// Builds a key for a feed with a given limit and scope.
func feedKey(limit: Int, scope: String? = nil, version: Int? = nil) -> QueryKey {
  QueryKey(
    TestRoot.feed,
    FeedArgs(limit: limit),
    options: QueryOptions(scope: scope, persistedVersion: version)
  )
}

/// Arguments for the feed key.
struct FeedArgs: QueryArgs {
  let limit: Int
}
