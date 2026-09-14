import ATProtoClient
import Foundation
import Lexicons
import Moderation
import SwiftAtproto

@testable import ProfileLogic

/// A transport that plays a scripted sequence of responses and records every
/// request, so tests can assert both the feature's behaviour and the bytes it
/// sent.
///
/// The profile package deliberately does not reach into `TestSupport` (which is
/// a placeholder), so this is a package-local fake - the same shape the Login
/// package uses.
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

    /// The request path, without the query string.
    var path: String {
      String(url.split(separator: "?").first ?? "")
    }

    /// The query parameters, decoded.
    var query: [String: String] {
      guard let questionMark = url.firstIndex(of: "?") else { return [:] }
      let queryString = url[url.index(after: questionMark)...]
      var result: [String: String] = [:]
      for pair in queryString.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let name = parts.first else { continue }
        let value = parts.count > 1 ? String(parts[1]) : ""
        let decodedName = name.removingPercentEncoding ?? String(name)
        result[decodedName] = value.removingPercentEncoding ?? value
      }
      return result
    }
  }

  private let lock = NSLock()
  private var _received: [Received] = []
  private var responses: [HTTPResponse?]
  private var index = 0
  private var error: (any Error)?
  private var sticky: HTTPResponse?
  /// Artificial latency per response, so a test can observe an in-flight
  /// request instead of racing it.
  var responseDelay: Duration?

  init(script: [(HTTPResponse)?] = []) {
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

  var received: [Received] { withLock { _received } }
  var lastRequest: Received? { received.last }
  var requestCount: Int { received.count }

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
    json(["error": code, "message": message], status: status)
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
    if let delay = withLock({ self.responseDelay }) {
      try? await Task.sleep(for: delay)
    }
    if let error { throw error }
    if let sticky { return sticky }
    if let next { return next }
    throw XrpcError(
      rawCode: nil, message: "no scripted response for \(method) \(url)", status: -1)
  }
}

/// Builds a `ProfileClient` over a scripted transport.
func makeClient(_ transport: ScriptedTransport) -> ProfileClient {
  ProfileClient(
    client: XrpcClient(baseURL: "https://api.example.com", labelers: nil, transport: transport))
}

/// Builds a raw `XrpcClient` over a scripted transport, for the write paths.
func makeXrpcClient(_ transport: ScriptedTransport) -> XrpcClient {
  XrpcClient(baseURL: "https://pds.example.com", labelers: nil, transport: transport)
}

// MARK: - Profile fixtures

/// A viewer state with the fields the header reads.
func makeViewerState(
  following: String? = nil,
  followedBy: String? = nil,
  muted: Bool? = nil,
  mutedOnlyReposts: Bool? = nil,
  mutedByList: Bool? = nil,
  blocking: String? = nil,
  blockedBy: Bool? = nil,
  blockedByList: Bool? = nil
) -> App.Bsky.ActorDefs_ViewerState {
  App.Bsky.ActorDefs_ViewerState(
    blockedBy: blockedBy,
    blocking: blocking.map { FormatString<ATURI>(rawValue: $0) },
    blockingByList: blockedByList == true ? makeListViewBasic() : nil,
    followedBy: followedBy.map { FormatString<ATURI>(rawValue: $0) },
    following: following.map { FormatString<ATURI>(rawValue: $0) },
    muted: muted,
    mutedByList: mutedByList == true ? makeListViewBasic() : nil,
    mutedOnlyReposts: mutedOnlyReposts)
}

/// A minimal list view, for the mute-by-list viewer state.
func makeListViewBasic() -> App.Bsky.GraphDefs_ListViewBasic {
  App.Bsky.GraphDefs_ListViewBasic(
    cid: FormatString<LexLink>(rawValue: "bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    name: "list",
    purpose: .appBskyGraphDefsCuratelist,
    uri: FormatString<ATURI>(rawValue: "at://did:plc:me/app.bsky.graph.list/1"))
}

/// A detailed profile with sensible defaults, so each test states only what it
/// cares about.
func makeProfile(
  did: String = "did:plc:alice",
  handle: String = "alice.example.com",
  displayName: String? = "Alice",
  description: String? = "Hello",
  avatar: String? = "https://cdn.example.com/alice/avatar.jpg",
  banner: String? = "https://cdn.example.com/alice/banner.jpg",
  followersCount: Int? = 100,
  followsCount: Int? = 50,
  postsCount: Int? = 25,
  viewer: App.Bsky.ActorDefs_ViewerState? = nil,
  labels: [Com.Atproto.LabelDefs_Label]? = nil,
  feedgens: Int? = nil,
  starterPacks: Int? = nil,
  lists: Int? = nil,
  labeler: Bool? = nil
) -> App.Bsky.ActorDefs_ProfileViewDetailed {
  App.Bsky.ActorDefs_ProfileViewDetailed(
    associated: App.Bsky.ActorDefs_ProfileAssociated(
      feedgens: feedgens, labeler: labeler, lists: lists, starterPacks: starterPacks),
    avatar: avatar.map { FormatString<URI>(rawValue: $0) },
    banner: banner.map { FormatString<URI>(rawValue: $0) },
    description: description,
    did: FormatString<DID>(rawValue: did),
    displayName: displayName,
    followersCount: followersCount,
    followsCount: followsCount,
    handle: FormatString<Handle>(rawValue: handle),
    labels: labels,
    postsCount: postsCount,
    viewer: viewer)
}

/// A minimal profile view, as the list queries return.
func makeBasicProfile(
  did: String, handle: String = "someone.example.com", viewer: App.Bsky.ActorDefs_ViewerState? = nil
) -> App.Bsky.ActorDefs_ProfileView {
  App.Bsky.ActorDefs_ProfileView(
    did: FormatString<DID>(rawValue: did),
    handle: FormatString<Handle>(rawValue: handle),
    viewer: viewer)
}

/// A `getProfile` JSON payload.
func profileJSON(
  did: String = "did:plc:alice",
  handle: String = "alice.example.com",
  displayName: String? = "Alice",
  description: String? = "Hello",
  followersCount: Int = 100,
  followsCount: Int = 50,
  postsCount: Int = 25,
  extra: [String: Any] = [:]
) -> [String: Any] {
  var payload: [String: Any] = [
    "did": did,
    "handle": handle,
    "followersCount": followersCount,
    "followsCount": followsCount,
    "postsCount": postsCount,
  ]
  if let displayName { payload["displayName"] = displayName }
  if let description { payload["description"] = description }
  for (key, value) in extra { payload[key] = value }
  return payload
}

/// A label definition fixture, so a labeled profile produces a real decision.
func makeLabel(_ value: String, uri: String = "at://did:plc:alice")
  -> Com.Atproto.LabelDefs_Label
{
  Com.Atproto.LabelDefs_Label(
    cts: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
    src: FormatString<DID>(rawValue: "did:plc:labeler"),
    uri: FormatString<URI>(rawValue: uri),
    val: value)
}

/// Moderation options with an empty preference set.
func makeModerationOpts(userDid: String = "did:plc:me", labelDefs: [String: [LabelValueDefinition]] = [:])
  -> ModerationOpts
{
  ModerationOpts(
    userDid: userDid,
    prefs: ModerationPrefs(),
    labelDefs: labelDefs)
}
