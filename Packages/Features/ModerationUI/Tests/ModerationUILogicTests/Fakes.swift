import Foundation
import Synchronization

import ATProtoClient
import Lexicons
import Preferences
import SwiftAtproto

/// A scripted XRPC server: answers GET/POST by method name from a table and
/// records every request.
///
/// The package deliberately does not reach into `TestSupport` (a placeholder),
/// so this is a package-local fake, following the `ScriptedTransport` pattern
/// in LoginLogic and PostThreadLogic. It also doubles as the preferences
/// server, so the muted-word tests can drive the real `PreferencesEngine`.
final class ScriptedXRPC: Sendable {
  struct Request: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?

    /// The XRPC method name, i.e. the path segment after `/xrpc/`.
    var methodName: String {
      guard let range = url.range(of: "/xrpc/") else { return url }
      return String(url[range.upperBound...].prefix { $0 != "?" })
    }

    /// The query parameters, decoded.
    var params: [String: String] {
      guard let components = URLComponents(string: url) else { return [:] }
      var out: [String: String] = [:]
      for item in components.queryItems ?? [] {
        out[item.name] = item.value ?? ""
      }
      return out
    }

    /// The decoded JSON body, when present.
    var jsonBody: [String: JSONValue]? {
      guard let body else { return nil }
      return try? JSONDecoder().decode([String: JSONValue].self, from: body)
    }
  }

  private struct State {
    /// Encoded response bodies keyed by method name, consumed one per request.
    var responses: [String: [Data]] = [:]
    var requests: [Request] = []
    /// Preferences held for get/putPreferences round-tripping.
    var preferences: [JSONValue] = []
    /// The body of a failing response, keyed by method.
    var failures: [String: (status: Int, body: Data)] = [:]
  }

  private let state = Mutex(State())

  init() {}

  // MARK: - Scripting

  /// Queues one JSON response body for a method, given as a JSON string.
  /// Repeated calls append, so a paginated read consumes one per request; once
  /// the queue is empty the fake answers 404, which makes an over-fetch visible
  /// in a test rather than silently repeating.
  func respond(_ method: String, json: String) {
    state.withLock { $0.responses[method, default: []].append(Data(json.utf8)) }
  }

  /// Queues an error response for a method.
  func fail(_ method: String, status: Int, error: String, message: String) {
    let body = Data(#"{"error":"\#(error)","message":"\#(message)"}"#.utf8)
    state.withLock { $0.failures[method] = (status, body) }
  }

  /// Sets the preference array the fake serves.
  func setPreferences(_ json: String) {
    let decoded = (try? JSONDecoder().decode([JSONValue].self, from: Data(json.utf8))) ?? []
    state.withLock { $0.preferences = decoded }
  }

  /// The current preference array, re-encoded as stable JSON.
  var preferences: [JSONValue] {
    state.withLock { $0.preferences }
  }

  var preferencesJSON: String {
    TestJSON.canonical(.array(state.withLock { $0.preferences }))
  }

  var requests: [Request] {
    state.withLock { $0.requests }
  }

  /// The recorded requests for one method.
  func requests(_ method: String) -> [Request] {
    state.withLock { $0.requests.filter { $0.methodName == method } }
  }

  /// The engine wired to this server as its preferences host.
  func preferencesEngine(tids: TidGenerator = SequentialTidGenerator()) -> PreferencesEngine {
    let client = XrpcClient(baseURL: "https://pds.test", transport: FakeTransport(server: self))
    return PreferencesEngine(client: client, tids: tids)
  }

  /// An appview client wired to this server.
  func appviewClient() -> XrpcClient {
    XrpcClient(
      baseURL: "https://appview.test", proxyService: "did:web:api.bsky.app#bsky_appview",
      transport: FakeTransport(server: self))
  }

  /// A PDS client wired to this server.
  func pdsClient() -> XrpcClient {
    XrpcClient(baseURL: "https://pds.test", transport: FakeTransport(server: self))
  }

  // MARK: - Serving

  fileprivate func handle(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    let request = Request(method: method, url: url, headers: headers, body: body)
    let failure = state.withLock { state -> (status: Int, body: Data)? in
      state.requests.append(request)
      return state.failures[request.methodName]
    }
    if let failure {
      return HTTPResponse(status: failure.status, headers: [:], body: failure.body)
    }

    switch request.methodName {
    case "app.bsky.actor.getPreferences":
      let current = state.withLock { $0.preferences }
      return try Self.json(["preferences": .array(current)])
    case "app.bsky.actor.putPreferences":
      guard let object = request.jsonBody, let preferences = object["preferences"],
        case .array(let values) = preferences
      else {
        return HTTPResponse(
          status: 400, headers: [:], body: Data(#"{"error":"InvalidRequest"}"#.utf8))
      }
      state.withLock { $0.preferences = values }
      return try Self.json([:])
    default:
      break
    }

    let queued = state.withLock { state -> Data? in
      guard var list = state.responses[request.methodName], !list.isEmpty else { return nil }
      let value = list.removeFirst()
      state.responses[request.methodName] = list
      return value
    }
    guard let data = queued else {
      return HTTPResponse(
        status: 404, headers: [:],
        body: Data(#"{"error":"XRPCNotSupported","message":"no scripted response"}"#.utf8))
    }
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"], body: data)
  }

  private static func json(_ payload: [String: JSONValue]) throws -> HTTPResponse {
    // Preferences are normally written by the engine, so read them back as raw
    // JSON rather than round-tripping through JSONValue.
    let data = try JSONSerialization.data(withJSONObject: payload.mapValues(TestJSON.object(_:)))
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"], body: data)
  }
}

/// An `HTTPTransport` that routes every request to a ``ScriptedXRPC``.
struct FakeTransport: HTTPTransport {
  let server: ScriptedXRPC

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    try await server.handle(method: method, url: url, headers: headers, body: body)
  }
}

/// Helpers for moving between JSON values and test fixtures.
enum TestJSON {
  /// Builds a `PrefObject` from a JSON string.
  static func object(_ raw: String) throws -> PrefObject {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    guard let members = value.objectValue else {
      throw PreferencesError(.missingType)
    }
    return PrefObject(fields: members)
  }

  /// Converts a `JSONValue` into a `JSONSerialization`-friendly object.
  static func object(_ value: JSONValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let value): return value
    case .int(let value): return value
    case .double(let value): return value
    case .string(let value): return value
    case .array(let values): return values.map(object)
    case .object(let members): return members.mapValues(object)
    }
  }

  /// Re-encodes a JSON value with sorted object keys, so comparisons are stable.
  static func canonical(_ value: JSONValue) -> String {
    switch value {
    case .object(let members):
      let inner = members.keys.sorted().map { key in
        quoted(key) + ":" + canonical(members[key]!)
      }
      return "{" + inner.joined(separator: ",") + "}"
    case .array(let values):
      return "[" + values.map(canonical).joined(separator: ",") + "]"
    case .null: return "null"
    case .bool(let value): return value ? "true" : "false"
    case .int(let value): return String(value)
    case .double(let value): return String(value)
    case .string(let value): return quoted(value)
    }
  }

  /// Canonicalizes a raw JSON string (object keys sorted).
  static func canonical(_ raw: String) throws -> String {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    return canonical(value)
  }

  private static func quoted(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
    return out
  }
}

/// Builders for lexicon fixtures.
enum Fixtures {
  static let actor = "did:plc:actor"
  static let other = "did:plc:other"

  /// A minimal profile view.
  static func profileView(_ did: String) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      avatar: nil,
      did: FormatString<DID>(rawValue: did),
      displayName: nil,
      handle: FormatString<Handle>(rawValue: handle(did)),
      labels: nil)
  }

  /// A minimal post view with a controlled record and embed.
  static func postView(
    uri: String, cid: String = "bafypost", reply: Bool = false,
    embed: App.Bsky.FeedDefs_PostView_Embed? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: profileViewBasic(actor),
      cid: FormatString<LexLink>(rawValue: cid),
      embed: embed,
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      record: .record(postRecord(createdAt: "2026-01-01T00:00:00.000Z", reply: reply)),
      uri: FormatString<ATURI>(rawValue: uri))
  }

  /// A minimal profile view basic.
  static func profileViewBasic(_ did: String) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      avatar: nil,
      did: FormatString<DID>(rawValue: did),
      displayName: nil,
      handle: FormatString<Handle>(rawValue: handle(did)),
      labels: nil)
  }

  /// A post record, optionally a reply.
  static func postRecord(createdAt: String, reply: Bool) -> App.Bsky.FeedPost {
    App.Bsky.FeedPost(
      createdAt: FormatString<Date>(rawValue: createdAt),
      reply: reply
        ? App.Bsky.FeedPost_ReplyRef(
          parent: Com.Atproto.RepoStrongRef(
            cid: FormatString<LexLink>(rawValue: "bafyparent"),
            uri: FormatString<ATURI>(rawValue: "at://did:plc:other/app.bsky.feed.post/1")),
          root: Com.Atproto.RepoStrongRef(
            cid: FormatString<LexLink>(rawValue: "bafyroot"),
            uri: FormatString<ATURI>(rawValue: "at://did:plc:other/app.bsky.feed.post/1")))
        : nil,
      text: "hello")
  }

  /// A status view.
  static func statusView(
    uri: String? = "at://did:plc:actor/app.bsky.actor.status/self",
    cid: String? = "bafystatus"
  ) -> App.Bsky.ActorDefs_StatusView {
    App.Bsky.ActorDefs_StatusView(
      cid: cid.map { FormatString<LexLink>(rawValue: $0) },
      record: .record(postRecord(createdAt: "2026-01-01T00:00:00.000Z", reply: false)),
      status: .appBskyActorStatusLive,
      uri: uri.map { FormatString<ATURI>(rawValue: $0) })
  }

  /// A list view.
  static func listView(uri: String, cid: String = "bafylist") -> App.Bsky.GraphDefs_ListView {
    App.Bsky.GraphDefs_ListView(
      cid: FormatString<LexLink>(rawValue: cid),
      creator: profileView(actor),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      name: "list",
      purpose: .appBskyGraphDefsCuratelist,
      uri: FormatString<ATURI>(rawValue: uri))
  }

  /// A feed generator view.
  static func generatorView(
    uri: String, cid: String = "bafygen"
  ) -> App.Bsky.FeedDefs_GeneratorView {
    App.Bsky.FeedDefs_GeneratorView(
      cid: FormatString<LexLink>(rawValue: cid),
      creator: profileView(actor),
      did: FormatString<DID>(rawValue: actor),
      displayName: "feed",
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      uri: FormatString<ATURI>(rawValue: uri))
  }

  /// A starter pack view.
  static func starterPackView(
    uri: String, cid: String = "bafysp"
  ) -> App.Bsky.GraphDefs_StarterPackView {
    App.Bsky.GraphDefs_StarterPackView(
      cid: FormatString<LexLink>(rawValue: cid),
      creator: profileViewBasic(actor),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      record: .record(postRecord(createdAt: "2026-01-01T00:00:00.000Z", reply: false)),
      uri: FormatString<ATURI>(rawValue: uri))
  }

  /// A labeler detailed view with the given policies and capabilities.
  static func labelerDetailed(
    did: String, handle handleValue: String? = nil, displayName: String? = nil,
    labelValueDefinitions: [Com.Atproto.LabelDefs_LabelValueDefinition]? = nil,
    reasonTypes: [String]? = nil, subjectCollections: [String]? = nil,
    subjectTypes: [String]? = nil
  ) -> App.Bsky.LabelerDefs_LabelerViewDetailed {
    App.Bsky.LabelerDefs_LabelerViewDetailed(
      cid: FormatString<LexLink>(rawValue: "bafylabeler"),
      creator: App.Bsky.ActorDefs_ProfileView(
        avatar: nil,
        did: FormatString<DID>(rawValue: did),
        displayName: displayName,
        handle: FormatString<Handle>(rawValue: handleValue ?? handle(did)),
        labels: nil),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      policies: App.Bsky.LabelerDefs_LabelerPolicies(
        labelValueDefinitions: labelValueDefinitions,
        labelValues: []),
      reasonTypes: reasonTypes.map { values in
        values.map { Com.Atproto.ModerationDefs_ReasonType(rawValue: $0) }
      },
      subjectCollections: subjectCollections.map { values in
        values.map { FormatString<NSID>(rawValue: $0) }
      },
      subjectTypes: subjectTypes.map { values in
        values.map { Com.Atproto.ModerationDefs_SubjectType(rawValue: $0) }
      },
      uri: FormatString<ATURI>(rawValue: "at://\(did)/app.bsky.labeler.service/self"))
  }

  /// A generated label value definition.
  static func labelValueDefinition(
    identifier: String, severity: String = "none", blurs: String = "none",
    defaultSetting: String? = nil, adultOnly: Bool? = nil
  ) -> Com.Atproto.LabelDefs_LabelValueDefinition {
    Com.Atproto.LabelDefs_LabelValueDefinition(
      adultOnly: adultOnly,
      blurs: Com.Atproto.LabelDefs_LabelValueDefinition_Blurs(rawValue: blurs),
      defaultSetting: defaultSetting.map {
        Com.Atproto.LabelDefs_LabelValueDefinition_DefaultSetting(rawValue: $0)
      },
      identifier: identifier,
      locales: [
        Com.Atproto.LabelDefs_LabelValueDefinitionStrings(
          description: "does \(identifier)",
          lang: FormatString<Language>(rawValue: "en"), name: identifier)
      ],
      severity: Com.Atproto.LabelDefs_LabelValueDefinition_Severity(rawValue: severity))
  }

  static func handle(_ did: String) -> String {
    did.replacingOccurrences(of: "did:plc:", with: "") + ".test"
  }
}
