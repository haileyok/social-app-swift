import ATProtoClient
import Foundation
import Lexicons
import Preferences
import SwiftAtproto

@testable import OnboardingLogic

/// A transport that plays a scripted sequence of responses and records every
/// request, so tests can assert both behaviour and the exact bytes sent.
///
/// The onboarding package deliberately does not reach into `TestSupport`, so
/// this is a package-local fake. It is the same shape Login uses.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
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

    /// The XRPC method path, e.g. `app.bsky.unspecced.getSuggestedOnboardingUsers`.
    var xrpcMethod: String {
      guard let range = url.range(of: "/xrpc/") else { return url }
      let tail = url[range.upperBound...]
      return tail.split(separator: "?").first.map(String.init) ?? String(tail)
    }

    /// The query parameters, decoded.
    var query: [String: String] {
      guard let components = URLComponents(string: url) else { return [:] }
      var out: [String: String] = [:]
      for item in components.queryItems ?? [] {
        out[item.name] = item.value ?? ""
      }
      return out
    }
  }

  private let lock = NSLock()
  private var _received: [Received] = []
  private var responses: [HTTPResponse?]
  private var index = 0
  private var error: (any Error)?
  private var sticky: HTTPResponse?

  init(_ responses: (HTTPResponse)?...) {
    self.responses = responses
  }

  init(script: [(HTTPResponse)?]) {
    self.responses = script
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

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var received: [Received] {
    withLock { _received }
  }

  var lastRequest: Received? { received.last }

  /// The XRPC methods called, in order.
  var methods: [String] { received.map(\.xrpcMethod) }

  static func json(
    _ payload: [String: Any],
    status: Int = 200,
    headers: [String: String] = ["Content-Type": "application/json"]
  ) -> HTTPResponse {
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return HTTPResponse(status: status, headers: headers, body: data)
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

/// A transport that serves the preferences endpoints from memory, so a test
/// can drive a real ``PreferencesEngine`` without scripting individual calls.
final class InMemoryPreferencesServer: @unchecked Sendable {
  struct Request: Sendable {
    let method: String
    let url: String
    let body: Data?
    let xrpcMethod: String
  }

  private let lock = NSLock()
  private var _preferences: [JSONValue]
  private var _requests: [Request] = []
  private var error: (any Error)?

  init(preferences: [JSONValue] = []) {
    self._preferences = preferences
  }

  /// A server whose every call fails.
  static func failing(with error: any Error) -> InMemoryPreferencesServer {
    let server = InMemoryPreferencesServer()
    server.error = error
    return server
  }

  var preferences: [JSONValue] {
    lock.lock()
    defer { lock.unlock() }
    return _preferences
  }

  var requests: [Request] {
    lock.lock()
    defer { lock.unlock() }
    return _requests
  }

  /// The XRPC methods the engine called, in order.
  var methods: [String] { requests.map(\.xrpcMethod) }

  /// The last `putPreferences` body's preference array.
  var lastWrittenPreferences: [JSONValue] {
    guard
      let request = requests.last(where: { $0.xrpcMethod == "app.bsky.actor.putPreferences" }),
      let body = request.body,
      let object = try? JSONDecoder().decode([String: JSONValue].self, from: body),
      case .array(let values) = object["preferences"] ?? .null
    else { return [] }
    return values
  }

  func transport() -> HTTPTransport {
    ServerTransport(server: self)
  }

  func engine(tids: any TidGenerator = SequentialTidGenerator()) -> PreferencesEngine {
    PreferencesEngine(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport()), tids: tids)
  }

  func handle(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    let xrpcMethod =
      url.range(of: "/xrpc/").map {
        String(url[$0.upperBound...].split(separator: "?").first ?? "")
      }
      ?? url
    let thrown: (any Error)? = lock.withLock {
      _requests.append(Request(method: method, url: url, body: body, xrpcMethod: xrpcMethod))
      return error
    }
    if let thrown { throw thrown }

    if xrpcMethod == "app.bsky.actor.getPreferences" {
      let current = preferences
      let data = try JSONEncoder().encode(["preferences": JSONValue.array(current)])
      return HTTPResponse(
        status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    guard let body,
      let object = try? JSONDecoder().decode([String: JSONValue].self, from: body),
      case .array(let values) = object["preferences"] ?? .null
    else {
      return HTTPResponse(
        status: 400, headers: [:], body: Data(#"{"error":"InvalidRequest"}"#.utf8))
    }
    lock.withLock { _preferences = values }
    return ScriptedTransport.json([:])
  }
}

/// Routes requests into an ``InMemoryPreferencesServer``.
struct ServerTransport: HTTPTransport {
  let server: InMemoryPreferencesServer

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    try await server.handle(method: method, url: url, headers: headers, body: body)
  }
}

/// Records every write an onboarding step makes.
///
/// The service is driven directly by the step runner in tests, so it is the
/// place the "exact XRPC calls and params" assertions land.
final class FakeOnboardingActionService: OnboardingActionService, @unchecked Sendable {
  enum Call: Sendable, Equatable {
    case currentDID
    case uploadAvatar(mimeType: String, byteCount: Int)
    case upsertProfile(displayName: String, avatarRef: String?, viaURI: String?)
    case createFollows(dids: [String], viaURI: String?)
    case setInterests(tags: [String])
    case setAdultContentEnabled(Bool)
    case overwriteSavedFeeds([SavedFeed])
    case upsertNux(id: String, completed: Bool, data: String?)
    case getStarterPack(uri: String)
    case getListMemberDIDs(listURI: String)
  }

  private let lock = NSLock()
  private var _calls: [Call] = []
  private var did: String
  private var uploadError: (any Error)?
  private var profileError: (any Error)?
  private var followError: (any Error)?
  private var interestsError: (any Error)?
  private var adultContentError: (any Error)?
  private var savedFeedsError: (any Error)?
  private var nuxError: (any Error)?
  private var starterPack: StarterPackDetail?
  private var starterPackError: (any Error)?
  private var listMembers: [String] = []
  private var listError: (any Error)?

  init(did: String = "did:plc:testaccount") {
    self.did = did
  }

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return _calls
  }

  /// The single upload call, when one was made.
  var uploadedAvatar: Call? {
    calls.first { if case .uploadAvatar = $0 { return true } else { return false } }
  }

  /// The profile write calls, in order.
  var profileWrites: [Call] {
    calls.filter { if case .upsertProfile = $0 { return true } else { return false } }
  }

  /// The follow calls, in order.
  var followCalls: [Call] {
    calls.filter { if case .createFollows = $0 { return true } else { return false } }
  }

  /// The interests writes, in order.
  var interestsWrites: [Call] {
    calls.filter { if case .setInterests = $0 { return true } else { return false } }
  }

  /// The saved-feeds writes, in order.
  var savedFeedsWrites: [Call] {
    calls.filter { if case .overwriteSavedFeeds = $0 { return true } else { return false } }
  }

  /// The NUX writes, in order.
  var nuxWrites: [Call] {
    calls.filter { if case .upsertNux = $0 { return true } else { return false } }
  }

  func configure(
    uploadError: (any Error)? = nil,
    profileError: (any Error)? = nil,
    followError: (any Error)? = nil,
    interestsError: (any Error)? = nil,
    adultContentError: (any Error)? = nil,
    savedFeedsError: (any Error)? = nil,
    nuxError: (any Error)? = nil,
    starterPack: StarterPackDetail? = nil,
    starterPackError: (any Error)? = nil,
    listMembers: [String] = [],
    listError: (any Error)? = nil
  ) {
    lock.lock()
    self.uploadError = uploadError
    self.profileError = profileError
    self.followError = followError
    self.interestsError = interestsError
    self.adultContentError = adultContentError
    self.savedFeedsError = savedFeedsError
    self.nuxError = nuxError
    self.starterPack = starterPack
    self.starterPackError = starterPackError
    self.listMembers = listMembers
    self.listError = listError
    lock.unlock()
  }

  private func record(_ call: Call) {
    lock.lock()
    _calls.append(call)
    lock.unlock()
  }

  func currentDID() async throws -> String {
    record(.currentDID)
    return did
  }

  func uploadAvatar(data: Data, mimeType: String) async throws -> OnboardingBlobRef {
    record(.uploadAvatar(mimeType: mimeType, byteCount: data.count))
    let error = lock.withLock { uploadError }
    if let error { throw error }
    return OnboardingBlobRef(
      ref: "bafkreifakeblobref", mimeType: mimeType, size: data.count)
  }

  func upsertProfile(
    avatar: OnboardingBlobRef?, displayName: String, joinedViaStarterPack: StarterPackRef?
  ) async throws {
    record(
      .upsertProfile(
        displayName: displayName, avatarRef: avatar?.ref,
        viaURI: joinedViaStarterPack?.uri))
    let error = lock.withLock { profileError }
    if let error { throw error }
  }

  func createFollows(dids: [String], via: StarterPackRef?) async throws -> [String: String] {
    record(.createFollows(dids: dids, viaURI: via?.uri))
    let error = lock.withLock { followError }
    if let error { throw error }
    var out: [String: String] = [:]
    for (index, subject) in dids.enumerated() {
      out[subject] = "at://\(did)/app.bsky.graph.follow/rkey\(index)"
    }
    return out
  }

  func setInterests(tags: [String]) async throws {
    record(.setInterests(tags: tags))
    let error = lock.withLock { interestsError }
    if let error { throw error }
  }

  func setAdultContentEnabled(_ enabled: Bool) async throws {
    record(.setAdultContentEnabled(enabled))
    let error = lock.withLock { adultContentError }
    if let error { throw error }
  }

  func overwriteSavedFeeds(_ feeds: [SavedFeed]) async throws {
    record(.overwriteSavedFeeds(feeds))
    let error = lock.withLock { savedFeedsError }
    if let error { throw error }
  }

  func upsertNux(id: String, completed: Bool, data: String?) async throws {
    record(.upsertNux(id: id, completed: completed, data: data))
    let error = lock.withLock { nuxError }
    if let error { throw error }
  }

  func getStarterPack(uri: String) async throws -> StarterPackDetail {
    record(.getStarterPack(uri: uri))
    let (error, detail) = lock.withLock { (starterPackError, starterPack) }
    if let error { throw error }
    guard let detail else { throw OnboardingError.unexpected(message: "no pack", underlying: nil) }
    return detail
  }

  func getListMemberDIDs(listURI: String) async throws -> [String] {
    record(.getListMemberDIDs(listURI: listURI))
    let (error, members) = lock.withLock { (listError, listMembers) }
    if let error { throw error }
    return members
  }
}

/// A fake suggestion service.
struct FakeOnboardingSuggestionService: OnboardingSuggestionService {
  var users: SuggestedUsersPage = SuggestedUsersPage(actors: [])
  var starterPacks: [SuggestedStarterPack] = []
  var usersError: (any Error)?
  var starterPacksError: (any Error)?

  func suggestedUsers(
    category: String?, limit: Int, interests: [String]
  ) async throws -> SuggestedUsersPage {
    if let usersError { throw usersError }
    return users
  }

  func suggestedStarterPacks(
    limit: Int, interests: [String]
  ) async throws -> [SuggestedStarterPack] {
    if let starterPacksError { throw starterPacksError }
    return starterPacks
  }
}

/// A fake handle-availability service.
struct FakeHandleAvailabilityService: HandleAvailabilityService {
  var result: HandleAvailability = .available
  var error: (any Error)?

  func checkHandleAvailability(handle: String) async throws -> HandleAvailability {
    if let error { throw error }
    return result
  }
}

/// Helpers for building fixtures.
enum Fixtures {
  /// A network-shaped failure Domain's classifier recognizes.
  static func networkError() -> XrpcError {
    XrpcError(rawCode: nil, message: "fetch failed", status: -1)
  }

  /// An XRPC error with a code.
  static func xrpcError(_ code: String, message: String = "", status: Int = 400) -> XrpcError {
    XrpcError(rawCode: code, message: message, status: status)
  }

  /// A suggested user.
  static func user(
    did: String, handle: String? = nil, following: String? = nil,
    blockedOrBlocking: Bool = false, muted: Bool = false
  ) -> SuggestedUser {
    SuggestedUser(
      did: did, handle: handle ?? "\(did).test", displayName: nil,
      viewerFollowing: following, isBlockedOrBlocking: blockedOrBlocking, isMuted: muted)
  }

  /// A starter pack detail.
  static func starterPack(
    uri: String = "at://did:plc:test/app.bsky.graph.starterpack/1",
    cid: String = "bafkreipack",
    listURI: String? = "at://did:plc:test/app.bsky.graph.list/1",
    feedURIs: [String] = []
  ) -> StarterPackDetail {
    StarterPackDetail(
      ref: StarterPackRef(uri: uri, cid: cid), listURI: listURI, feedURIs: feedURIs)
  }
}
