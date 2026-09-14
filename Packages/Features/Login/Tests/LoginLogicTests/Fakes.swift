import ATProtoClient
import Foundation
import Persistence

@testable import LoginLogic

/// A transport that plays a scripted sequence of responses and records every
/// request, so tests can assert both the flow's behaviour and the bytes it
/// sent.
///
/// The login package deliberately does not reach into `TestSupport` (which is
/// a placeholder), so this is a package-local fake.
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

  /// The array form, so a caller holding a script can pass it through.
  init(script: [(HTTPResponse)?]) {
    self.responses = script
  }

  /// A synchronous critical section.
  ///
  /// `NSLock.lock()` is annotated `noasync`, so it cannot be called directly
  /// from an async context; funnelling every use through this helper keeps the
  /// fakes' `send` methods async and the locking correct.
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
    status: Int = 400,
    headers: [String: String] = [:]
  ) -> HTTPResponse {
    json(
      ["error": code, "message": message],
      status: status,
      headers: headers.merging(["Content-Type": "application/json"]) { _, new in new })
  }

  /// The `createSession` success payload for an account.
  static func createSession(
    did: String = "did:plc:testaccount",
    handle: String = "alice.example.com",
    accessJwt: String? = nil,
    refreshJwt: String = "refresh-jwt",
    email: String? = "alice@example.com"
  ) -> HTTPResponse {
    var payload: [String: Any] = [
      "did": did,
      "handle": handle,
      "accessJwt": accessJwt ?? makeAccessToken(did: did),
      "refreshJwt": refreshJwt,
    ]
    if let email { payload["email"] = email }
    return json(payload)
  }

  /// The `describeServer` success payload.
  static func describeServer(
    domains: [String] = ["example.com"],
    did: String = "did:web:example.com"
  ) -> HTTPResponse {
    json(["availableUserDomains": domains, "did": did])
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

/// A `PasswordResetService` fake recording every call.
final class FakePasswordResetService: PasswordResetService, @unchecked Sendable {
  struct Call: Sendable, Equatable {
    let service: String
    let email: String?
    let token: String?
    let password: String?
  }

  private let lock = NSLock()
  private var _calls: [Call] = []
  private var requestError: (any Error)?
  private var resetError: (any Error)?

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  init(requestError: (any Error)? = nil, resetError: (any Error)? = nil) {
    self.requestError = requestError
    self.resetError = resetError
  }

  var calls: [Call] {
    withLock { _calls }
  }

  func requestPasswordReset(service: String, email: String) async throws {
    let error: (any Error)? = withLock {
      _calls.append(Call(service: service, email: email, token: nil, password: nil))
      return requestError
    }
    if let error { throw error }
  }

  func resetPassword(service: String, token: String, password: String) async throws {
    let error: (any Error)? = withLock {
      _calls.append(Call(service: service, email: nil, token: token, password: password))
      return resetError
    }
    if let error { throw error }
  }
}

/// A `SessionStore` over a fresh temp directory with an in-memory token store.
struct SessionStoreHarness {
  let directory: URL
  let persisted: PersistedStore
  let tokens: InMemoryTokenStore
  let store: SessionStore

  init(transport: HTTPTransport = ScriptedTransport()) async {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("login-flow-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    persisted = PersistedStore(directory: directory)
    tokens = InMemoryTokenStore()
    store = SessionStore(persisted: persisted, tokenStore: tokens, transport: transport)
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: directory)
  }
}

/// A long-lived access token, so a resume takes the no-network fast path.
func makeAccessToken(
  did: String = "did:plc:testaccount",
  exp: Int = 4_000_000_000,
  scope: String = "com.atproto.access"
) -> String {
  JWT.unsignedToken(payload: ["sub": did, "exp": exp, "scope": scope])
    ?? "header.payload.signature"
}

/// A stored account fixture.
func makeStoredAccount(
  did: String = "did:plc:testaccount",
  handle: String = "alice.example.com",
  service: String = "https://bsky.social",
  accessJwt: String?? = nil,
  refreshJwt: String? = "refresh-jwt"
) -> PersistedAccount {
  PersistedAccount(
    service: service,
    did: did,
    handle: handle,
    email: "\(handle)@example.com",
    emailConfirmed: true,
    refreshJwt: refreshJwt,
    accessJwt: accessJwt ?? makeAccessToken(did: did))
}

/// A transport error shaped like a genuine connectivity failure, so the Domain
/// network classifier recognises it.
func makeNetworkError() -> XrpcError {
  XrpcError(rawCode: nil, message: "fetch failed", status: -1)
}
