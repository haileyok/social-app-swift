import Foundation
import Synchronization

import ATProtoClient
import Lexicons
import Persistence
import Preferences
import SwiftAtproto

@testable import SettingsLogic

/// A transport that plays a scripted sequence of responses and records every
/// request, so tests can assert both the flow's behaviour and the exact bytes
/// it sent.
///
/// Package-local, following the Login package's precedent: `TestSupport` is a
/// placeholder and the feature packages do not reach into it.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
  /// One request the transport saw.
  struct Received: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?

    /// The decoded JSON body, for assertion.
    var json: [String: Any] {
      guard let body,
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
      else { return [:] }
      return object
    }

    /// The URL's query, decoded into pairs.
    var query: [String: String] {
      guard let components = URLComponents(string: url) else { return [:] }
      var out: [String: String] = [:]
      for item in components.queryItems ?? [] {
        out[item.name] = item.value
      }
      return out
    }

    /// The XRPC method, i.e. the last path component.
    var methodName: String {
      URLComponents(string: url)?.path.split(separator: "/").last.map(String.init) ?? ""
    }
  }

  private let lock = NSLock()
  private var _received: [Received] = []
  private var responses: [HTTPResponse?]
  private var index = 0
  /// When set, the transport throws this instead of playing the script.
  private var error: (any Error)?
  /// When set, every response is this one (a sticky failure).
  private var sticky: HTTPResponse?

  init(_ responses: (HTTPResponse)?...) {
    self.responses = responses
  }

  init(script: [(HTTPResponse)?]) {
    self.responses = script
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// A transport whose every call fails with `error`.
  static func failing(with error: any Error) -> ScriptedTransport {
    let transport = ScriptedTransport()
    transport.error = error
    return transport
  }

  /// A transport whose every call returns `response`.
  static func sticky(_ response: HTTPResponse?) -> ScriptedTransport {
    let transport = ScriptedTransport()
    transport.sticky = response
    return transport
  }

  var received: [Received] {
    withLock { _received }
  }

  /// The last request seen, for the common single-call assertion.
  var lastRequest: Received? { received.last }

  static func json(
    _ payload: [String: Any],
    status: Int = 200,
    headers: [String: String] = ["Content-Type": "application/json"]
  ) -> HTTPResponse {
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return HTTPResponse(status: status, headers: headers, body: data)
  }

  /// An XRPC error response body.
  static func xrpcError(
    _ code: String,
    message: String = "",
    status: Int = 400
  ) -> HTTPResponse {
    HTTPResponse(
      status: status,
      headers: ["Content-Type": "application/json"],
      body: Data(#"{"error":"\#(code)","message":"\#(message)"}"#.utf8))
  }

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    let record = Received(method: method, url: url, headers: headers, body: body)
    let (next, error, sticky): (HTTPResponse?, (any Error)?, HTTPResponse?) = withLock {
      _received.append(record)
      var next: HTTPResponse?
      if index < responses.count {
        next = responses[index]
        index += 1
      }
      return (next, self.error, self.sticky)
    }

    if let error { throw error }
    if let sticky { return sticky }
    if let next { return next }
    throw XrpcError(
      rawCode: nil, message: "no scripted response for \(method) \(url)", status: -1)
  }
}

/// An in-memory `app.bsky.actor.getPreferences` / `putPreferences` server.
///
/// A package-local mirror of the Preferences package's fake: the prefs
/// mutations in ``SettingsStore`` are asserted through a *real*
/// `PreferencesEngine` over this, which is what makes the tests check the
/// actual patch the engine writes rather than a stand-in.
///
/// The array is held as JSON `Data` rather than as decoded values. Untyped
/// `[String: Any]` is not `Sendable`, and the engine's own `JSONValue` lives in
/// a module that also exports a type named `Preferences`, which would shadow
/// the interpreted-preferences type in every annotation. Holding the bytes and
/// decoding on demand keeps the fake `Sendable` and keeps call sites readable;
/// assertions run against the serialized JSON, which is the wire shape anyway.
final class FakePreferencesService: Sendable {
  struct Request: Sendable {
    let method: String
    let url: String
    let body: Data?
  }

  private struct State: Sendable {
    /// The stored preference array, as JSON bytes of a top-level array.
    var preferencesJSON: Data
    var requests: [Request] = []
    var errorToThrow: (any Error)?
  }

  private let state: Mutex<State>

  init(preferencesJSON: Data = Data("[]".utf8)) {
    self.state = Mutex(State(preferencesJSON: preferencesJSON))
  }

  /// Starts from a JSON string describing the preference array.
  convenience init(rawJSON: String) {
    self.init(preferencesJSON: Data(rawJSON.utf8))
  }

  /// The stored array, re-encoded with sorted keys for stable assertions.
  var preferencesJSON: String {
    let data = state.withLock { $0.preferencesJSON }
    guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
      let canonical = try? JSONSerialization.data(
        withJSONObject: array, options: [.sortedKeys]),
      let text = String(data: canonical, encoding: .utf8)
    else { return String(data: data, encoding: .utf8) ?? "" }
    return text
  }

  /// The stored array as JSON objects.
  var preferences: [[String: Any]] {
    let data = state.withLock { $0.preferencesJSON }
    return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
  }

  var putCount: Int {
    state.withLock { $0.requests.filter { $0.method == "POST" }.count }
  }

  var getCount: Int {
    state.withLock { $0.requests.filter { $0.method == "GET" }.count }
  }

  /// Every stored record of a given `$type`, as JSON objects.
  func records(ofType type: String) -> [[String: Any]] {
    preferences.filter { $0["$type"] as? String == type }
  }

  /// The first stored record of a given `$type`.
  func record(ofType type: String) -> [String: Any]? {
    records(ofType: type).first
  }

  /// Makes the next request fail with `error`.
  func failNext(with error: any Error) {
    state.withLock { $0.errorToThrow = error }
  }

  /// The engine wired to this service.
  func engine(tids: TidGenerator = SequentialTidGenerator()) -> PreferencesEngine {
    let client = XrpcClient(baseURL: "https://pds.test", transport: transport())
    return PreferencesEngine(client: client, tids: tids)
  }

  /// A transport backed by this service.
  func transport() -> HTTPTransport {
    ServiceTransport(service: self)
  }

  fileprivate func handle(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    let error: (any Error)? = state.withLock { state in
      state.requests.append(Request(method: method, url: url, body: body))
      let error = state.errorToThrow
      state.errorToThrow = nil
      return error
    }
    if let error { throw error }

    if method == "GET" {
      let current = state.withLock { $0.preferencesJSON }
      return try Self.json(preferencesJSON: current)
    }

    guard let body,
      let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let values = object["preferences"] as? [[String: Any]],
      let encoded = try? JSONSerialization.data(withJSONObject: values)
    else {
      return HTTPResponse(
        status: 400, headers: [:],
        body: Data(#"{"error":"InvalidRequest"}"#.utf8))
    }
    state.withLock { $0.preferencesJSON = encoded }
    return try Self.json(preferencesJSON: Data("[]".utf8))
  }

  /// Wraps a preference array into the response envelope.
  private static func json(preferencesJSON: Data) throws -> HTTPResponse {
    guard let array = try? JSONSerialization.jsonObject(with: preferencesJSON) else {
      throw XrpcError(rawCode: nil, message: "stored preferences are not JSON", status: -1)
    }
    let data = try JSONSerialization.data(withJSONObject: ["preferences": array])
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"], body: data)
  }
}

/// An `HTTPTransport` routing every request to a `FakePreferencesService`.
struct ServiceTransport: HTTPTransport {
  let service: FakePreferencesService

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    try await service.handle(method: method, url: url, headers: headers, body: body)
  }
}

/// A recording fake for the app-password endpoints.
final class FakeAppPasswordService: AppPasswordService, @unchecked Sendable {
  struct Call: Sendable, Equatable {
    let method: String
    let name: String?
    let privileged: Bool?
  }

  private let lock = NSLock()
  private var _calls: [Call] = []
  private var passwords: [SettingsAppPassword]
  private var listError: (any Error)?
  private var createError: (any Error)?
  private var revokeError: (any Error)?
  private var created: SettingsAppPassword

  init(
    passwords: [SettingsAppPassword] = [],
    created: SettingsAppPassword = SettingsAppPassword(
      name: "created", privileged: false, createdAt: "2024-01-01T00:00:00Z",
      password: "abcd-efgh-ijkl-mnop")
  ) {
    self.passwords = passwords
    self.created = created
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var calls: [Call] { withLock { _calls } }

  func setListError(_ error: (any Error)?) { withLock { listError = error } }
  func setCreateError(_ error: (any Error)?) { withLock { createError = error } }
  func setRevokeError(_ error: (any Error)?) { withLock { revokeError = error } }

  /// The name passed to the last create call, for the uniqueness assertion.
  var lastCreatedName: String? { calls.last { $0.method == "create" }?.name }

  func listAppPasswords() async throws -> [SettingsAppPassword] {
    let error: (any Error)? = withLock {
      _calls.append(Call(method: "list", name: nil, privileged: nil))
      return listError
    }
    if let error { throw error }
    return withLock { passwords }
  }

  func createAppPassword(
    name: String, privileged: Bool
  ) async throws -> SettingsAppPassword {
    let error: (any Error)? = withLock {
      _calls.append(Call(method: "create", name: name, privileged: privileged))
      return createError
    }
    if let error { throw error }
    return withLock {
      let result = SettingsAppPassword(
        name: name, privileged: privileged, createdAt: created.createdAt,
        password: created.password)
      passwords.append(result)
      return result
    }
  }

  func revokeAppPassword(name: String) async throws {
    let error: (any Error)? = withLock {
      _calls.append(Call(method: "revoke", name: name, privileged: nil))
      return revokeError
    }
    if let error { throw error }
    withLock { passwords.removeAll { $0.name == name } }
  }
}

/// A recording fake for the handle endpoints.
final class FakeHandleService: HandleService, @unchecked Sendable {
  private let lock = NSLock()
  private var _updated: [String] = []
  private var _resolved: [String] = []
  /// Handle -> DID, for `resolveHandle`.
  private var resolution: [String: String] = [:]
  private var updateError: (any Error)?
  private var resolveError: (any Error)?

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var updatedHandles: [String] { withLock { _updated } }
  var resolvedHandles: [String] { withLock { _resolved } }

  func setResolution(_ handle: String, did: String) {
    withLock { resolution[handle] = did }
  }

  func setUpdateError(_ error: (any Error)?) { withLock { updateError = error } }
  func setResolveError(_ error: (any Error)?) { withLock { resolveError = error } }

  func updateHandle(_ handle: String) async throws {
    let error: (any Error)? = withLock {
      _updated.append(handle)
      return updateError
    }
    if let error { throw error }
  }

  func resolveHandle(_ handle: String) async throws -> String {
    let (error, did): ((any Error)?, String?) = withLock {
      _resolved.append(handle)
      return (resolveError, resolution[handle])
    }
    if let error { throw error }
    guard let did else {
      throw XrpcError(rawCode: "NotFound", message: "Handle not found", status: 400)
    }
    return did
  }
}

/// A fake availability checker.
final class FakeHandleAvailability: HandleAvailabilityChecking, @unchecked Sendable {
  private let lock = NSLock()
  private var _checks: [(handle: String, serviceDID: String)] = []
  private var result: HandleAvailabilityResult = .available
  private var error: (any Error)?

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var checks: [(handle: String, serviceDID: String)] { withLock { _checks } }

  func setResult(_ result: HandleAvailabilityResult) { withLock { self.result = result } }
  func setError(_ error: (any Error)?) { withLock { self.error = error } }

  func checkHandleAvailability(
    handle: String, serviceDID: String
  ) async throws -> HandleAvailabilityResult {
    let (error, result): ((any Error)?, HandleAvailabilityResult) = withLock {
      _checks.append((handle, serviceDID))
      return (self.error, self.result)
    }
    if let error { throw error }
    return result
  }
}

/// A recording fake for the account-lifecycle endpoints.
final class FakeAccountLifecycleService: AccountLifecycleService, @unchecked Sendable {
  struct DeleteCall: Sendable, Equatable {
    let did: String
    let password: String
    let token: String
  }

  private let lock = NSLock()
  private var _deactivates = 0
  private var _deleteRequests = 0
  private var _deletes: [DeleteCall] = []
  private var deactivateError: (any Error)?
  private var requestError: (any Error)?
  private var deleteError: (any Error)?

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var deactivateCount: Int { withLock { _deactivates } }
  var deleteRequestCount: Int { withLock { _deleteRequests } }
  var deleteCalls: [DeleteCall] { withLock { _deletes } }

  func setDeactivateError(_ error: (any Error)?) { withLock { deactivateError = error } }
  func setRequestError(_ error: (any Error)?) { withLock { requestError = error } }
  func setDeleteError(_ error: (any Error)?) { withLock { deleteError = error } }

  func deactivateAccount() async throws {
    let error: (any Error)? = withLock {
      _deactivates += 1
      return deactivateError
    }
    if let error { throw error }
  }

  func requestAccountDelete() async throws {
    let error: (any Error)? = withLock {
      _deleteRequests += 1
      return requestError
    }
    if let error { throw error }
  }

  func deleteAccount(did: String, password: String, token: String) async throws {
    let error: (any Error)? = withLock {
      _deletes.append(DeleteCall(did: did, password: password, token: token))
      return deleteError
    }
    if let error { throw error }
  }
}

/// An appearance store over a temp directory, with both backing layers.
struct AppearanceHarness {
  let directory: URL
  let persisted: PersistedStore
  let device: Storage<DeviceSchemaMarker>
  let store: AppearancePreferencesStore

  init() async {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("settings-appearance-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    persisted = PersistedStore(directory: directory)
    device = ScopedStores(directory: directory).device
    store = AppearancePreferencesStore(persisted: persisted, device: device)
  }

  /// A second store over the same directory, simulating a restart.
  func reopened() -> AppearancePreferencesStore {
    AppearancePreferencesStore(
      persisted: PersistedStore(directory: directory),
      device: ScopedStores(directory: directory).device)
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: directory)
  }
}

/// Builds a saved-feed item.
func makeSavedFeed(
  id: String, type: String = "feed", value: String? = nil, pinned: Bool
) -> SavedFeedItem {
  SavedFeedItem(
    id: id,
    type: type,
    value: value ?? "at://did:plc:test/app.bsky.feed.generator/\(id)",
    isPinned: pinned)
}

/// Assembles a settings store over every fake, for the integration-level tests.
struct StoreHarness {
  let prefsService: FakePreferencesService
  let prefsEngine: PreferencesEngine
  let appPasswords: FakeAppPasswordService
  let handles: FakeHandleService
  let availability: FakeHandleAvailability
  let lifecycle: FakeAccountLifecycleService
  let appearance: AppearanceHarness
  let store: SettingsStore

  init(
    preferencesJSON: String = "[]",
    passwords: [SettingsAppPassword] = [],
    did: String? = "did:plc:testaccount",
    languagePrefs: LanguagePrefs = LanguagePrefs()
  ) async {
    prefsService = FakePreferencesService(rawJSON: preferencesJSON)
    prefsEngine = prefsService.engine()
    appPasswords = FakeAppPasswordService(passwords: passwords)
    handles = FakeHandleService()
    availability = FakeHandleAvailability()
    lifecycle = FakeAccountLifecycleService()
    appearance = await AppearanceHarness()
    store = SettingsStore(
      dependencies: SettingsStore.Dependencies(
        preferences: prefsEngine,
        appPasswords: appPasswords,
        handles: handles,
        availability: availability,
        accountLifecycle: lifecycle,
        appearance: appearance.store,
        currentDID: { did },
        languageSource: { languagePrefs }))
  }

  func cleanUp() {
    appearance.cleanUp()
  }
}

/// Test helpers for reading the fake service's JSON.
enum TestJSON {
  /// The `items` array of the saved-feeds v2 record.
  static func savedFeedItems(_ service: FakePreferencesService) -> [[String: Any]] {
    (service.record(ofType: "app.bsky.actor.defs#savedFeedsPrefV2")?["items"]
      as? [[String: Any]]) ?? []
  }

  /// The values of the saved-feed items, in stored order.
  static func savedFeedValues(_ service: FakePreferencesService) -> [String] {
    savedFeedItems(service).compactMap { $0["value"] as? String }
  }

  /// The pinned flags of the saved-feed items, in stored order.
  static func savedFeedPinned(_ service: FakePreferencesService) -> [Bool] {
    savedFeedItems(service).compactMap { $0["pinned"] as? Bool }
  }

  /// Every `contentLabelPref` record whose label matches.
  static func contentLabelPrefs(
    _ service: FakePreferencesService, label: String
  ) -> [[String: Any]] {
    service.records(ofType: "app.bsky.actor.defs#contentLabelPref")
      .filter { $0["label"] as? String == label }
  }
}
