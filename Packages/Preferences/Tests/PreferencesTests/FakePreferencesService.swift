import Foundation
import Synchronization

import ATProtoClient
import Lexicons
import Preferences
import SwiftAtproto

/// An in-memory `app.bsky.actor.getPreferences` / `putPreferences` server.
///
/// Tests drive the engine against this instead of the network. It stores the
/// raw preference array, records every request, and can suspend a read so
/// write ordering can be observed.
final class FakePreferencesService: Sendable {
  /// One request the engine made.
  struct Request: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?
  }

  private struct State {
    var preferences: [JSONValue]
    var requests: [Request] = []
    var readGate: CheckedContinuation<Void, Never>?
    var isReadSuspended = false
    var errorToThrow: (any Error)?
  }

  private let state: Mutex<State>

  init(preferences: [JSONValue] = []) {
    self.state = Mutex(State(preferences: preferences))
  }

  /// Starts from a JSON string describing the preference array, so tests read
  /// like the wire payload they model.
  convenience init(rawJSON: String) {
    let data = Data(rawJSON.utf8)
    let decoded = (try? JSONDecoder().decode([JSONValue].self, from: data)) ?? []
    self.init(preferences: decoded)
  }

  var preferences: [JSONValue] {
    state.withLock { $0.preferences }
  }

  /// The preference array re-encoded as stable, sorted-key JSON.
  var preferencesJSON: String {
    Self.canonicalJSON(.array(preferences))
  }

  var getCount: Int {
    state.withLock { $0.requests.filter { $0.method == "GET" }.count }
  }

  var putCount: Int {
    state.withLock { $0.requests.filter { $0.method == "POST" }.count }
  }

  var isReadSuspended: Bool {
    state.withLock { $0.isReadSuspended }
  }

  /// Suspends the next read until ``releaseRead()`` is called.
  func suspendNextRead() {
    state.withLock { $0.isReadSuspended = true }
  }

  /// Releases a suspended read.
  func releaseRead() {
    let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
      let gate = state.readGate
      state.readGate = nil
      state.isReadSuspended = false
      return gate
    }
    continuation?.resume()
  }

  /// A transport backed by this service.
  func transport() -> HTTPTransport {
    ServiceTransport(service: self)
  }

  /// The engine wired to this service.
  func engine(tids: TidGenerator) -> PreferencesEngine {
    let client = XrpcClient(baseURL: "https://pds.test", transport: transport())
    return PreferencesEngine(client: client, tids: tids)
  }

  func engine() -> PreferencesEngine {
    engine(tids: SequentialTidGenerator())
  }

  // MARK: - Request handling

  fileprivate func handle(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    let (error, shouldSuspend): ((any Error)?, Bool) = state.withLock { state in
      state.requests.append(Request(method: method, url: url, headers: headers, body: body))
      let error = state.errorToThrow
      state.errorToThrow = nil
      return (error, method == "GET" && state.isReadSuspended)
    }

    if let error { throw error }
    if shouldSuspend {
      await withCheckedContinuation { continuation in
        state.withLock { $0.readGate = continuation }
      }
    }

    if method == "GET" {
      let current = state.withLock { $0.preferences }
      return try Self.json([:], preferences: .array(current))
    }

    guard let body,
      let object = try? JSONDecoder().decode([String: JSONValue].self, from: body),
      let preferences = object["preferences"],
      case .array(let values) = preferences
    else {
      return HTTPResponse(
        status: 400, headers: [:],
        body: Data(#"{"error":"InvalidRequest"}"#.utf8))
    }
    state.withLock { $0.preferences = values }
    return try Self.json([:], preferences: nil)
  }

  private static func json(
    _ extra: [String: JSONValue], preferences: JSONValue?
  ) throws -> HTTPResponse {
    var payload: [String: JSONValue] = ["preferences": preferences ?? .array([])]
    payload.merge(extra) { _, new in new }
    let data = try JSONEncoder().encode(payload)
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"], body: data)
  }

  /// Encodes a JSON value with object keys sorted, so comparisons are stable.
  static func canonicalJSON(_ value: JSONValue) -> String {
    switch value {
    case .object(let members):
      let inner = members.keys.sorted().map { key in
        quoted(key) + ":" + canonicalJSON(members[key]!)
      }
      return "{" + inner.joined(separator: ",") + "}"
    case .array(let values):
      return "[" + values.map(canonicalJSON).joined(separator: ",") + "]"
    case .null:
      return "null"
    case .bool(let value):
      return value ? "true" : "false"
    case .int(let value):
      return String(value)
    case .double(let value):
      return String(value)
    case .string(let value):
      return quoted(value)
    }
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

/// An `HTTPTransport` that routes every request to a `FakePreferencesService`.
struct ServiceTransport: HTTPTransport {
  let service: FakePreferencesService

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    try await service.handle(method: method, url: url, headers: headers, body: body)
  }
}

/// Test helpers for reading and writing JSON payloads.
enum TestJSON {
  /// Builds an object from a JSON string.
  static func object(_ raw: String) throws -> PrefObject {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    guard let members = value.objectValue else {
      throw PreferencesError(.missingType)
    }
    return PrefObject(fields: members)
  }

  /// Builds a `FormatString<Date>` from an ISO string.
  static func date(_ raw: String) throws -> FormatString<Date> {
    try FormatString<Date>(rawValue: raw)
  }
}
