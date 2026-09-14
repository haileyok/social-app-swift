import Foundation

import ATProtoClient
import Lexicons
import SwiftAtproto

/// The raw preference array, as a list of JSON objects.
///
/// The SDK's `Preferences` type is a plain `defs.Preferences[]`; this wrapper
/// gives the engine typed accessors for the common lookups (find-by-type,
/// replace-by-type, append) without losing members it does not model.
public struct PreferencesArray: Sendable {
  public var elements: [PrefObject]

  public init(elements: [PrefObject] = []) {
    self.elements = elements
  }

  public init(_ generated: [App.Bsky.ActorDefs_Preferences_Elem]) throws {
    self.elements = try generated.map(PrefObject.init)
  }

  /// Decodes the raw array from a `getPreferences` response body.
  public init(output: App.Bsky.ActorGetPreferences_Output) throws {
    try self.init(output.preferences)
  }

  /// Encodes the raw array for a `putPreferences` request body.
  public func encoded() throws -> [App.Bsky.ActorDefs_Preferences_Elem] {
    try elements.map { try $0.encoded() }
  }

  /// The first record with the given `$type`, or nil.
  public func first(_ type: String) -> PrefObject? {
    elements.first { $0.type == type }
  }

  /// Every record with the given `$type`.
  public func all(_ type: String) -> [PrefObject] {
    elements.filter { $0.type == type }
  }

  /// Index of the first record with the given `$type`, or nil.
  public func index(of type: String) -> Int? {
    elements.firstIndex { $0.type == type }
  }

  /// True when any record has the given `$type`.
  public func contains(_ type: String) -> Bool {
    index(of: type) != nil
  }

  /// Maps every record with the given `$type`, leaving the rest untouched.
  /// Returns a new array; the receiver is unchanged.
  public func mapping(_ type: String, _ transform: (PrefObject) -> PrefObject) -> PreferencesArray {
    var copy = self
    copy.elements = elements.map { $0.type == type ? transform($0) : $0 }
    return copy
  }

  /// Replaces every record with the given `$type` by a single record.
  public func replacing(_ type: String, with record: PrefObject) -> PreferencesArray {
    var copy = self
    copy.elements = elements.filter { $0.type != type }
    copy.elements.append(record)
    return copy
  }

  /// Removes every record with the given `$type`.
  public func removing(_ type: String) -> PreferencesArray {
    var copy = self
    copy.elements = elements.filter { $0.type != type }
    return copy
  }

  /// Appends a record.
  public func appending(_ record: PrefObject) -> PreferencesArray {
    var copy = self
    copy.elements.append(record)
    return copy
  }
}

/// The outcome of a read-modify-write cycle.
public enum UpdateResult: Sendable {
  /// The callback declined to change anything (the SDK's `return false`), so
  /// no `putPreferences` call was made.
  case skipped
  /// The callback returned a new array, which was written.
  case wrote([PrefObject])
}

/// Applies a patch to a preferences array. Returning nil skips the write,
/// mirroring the SDK's `update: (prefs) => Preferences | false`.
public typealias PreferencesUpdate = @Sendable (PreferencesArray) throws -> PreferencesArray?

/// Reads and writes `app.bsky.actor.getPreferences` / `putPreferences` against
/// a PDS.
///
/// `getPreferences`/`putPreferences` are PDS endpoints: the client must be the
/// account-host client (no `atproto-proxy`, no labeler header). Construct with
/// a plain `XrpcClient`.
///
/// Read-modify-write cycles are serialized: concurrent action submissions
/// queue behind one another and each observes the previous write's result.
public actor PreferencesEngine {
  let client: XrpcClient
  let authorization: @Sendable () async throws -> String?
  private let tids: TidGenerator

  /// Tail of the serialization chain. Each submitted cycle awaits `tail`
  /// before reading, then becomes the new tail.
  private var tail: Task<Void, Never>?

  public init(
    client: XrpcClient,
    tids: TidGenerator = SystemTidGenerator(),
    authorization: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    self.client = client
    self.tids = tids
    self.authorization = authorization
  }

  // MARK: - Reads

  /// Fetches the raw preference array.
  public func fetchPreferences() async throws -> PreferencesArray {
    try await Self.readPreferences(client, authorization: authorization)
  }

  /// Fetches and interprets preferences into the structured view the app
  /// consumes, migrating v1 saved feeds to v2 on first read.
  public func getPreferences() async throws -> Preferences {
    let raw = try await fetchPreferences()
    return try await hydrate(raw)
  }

  // MARK: - Serialized read-modify-write

  /// Runs one serialized read-modify-write cycle.
  ///
  /// The read, the patch, and the `putPreferences` write all happen inside the
  /// exclusive section, so two concurrent submissions cannot interleave their
  /// reads and lose a write.
  ///
  /// `tail` is advanced before the first suspension point, so a caller that
  /// arrives mid-cycle always observes the in-flight chain and queues behind
  /// it.
  public func update(_ patch: @escaping PreferencesUpdate) async throws -> UpdateResult {
    let previous = tail
    let client = self.client
    let authorization = self.authorization
    let cycle = Task<UpdateResult, Error> {
      await previous?.value
      let current = try await Self.readPreferences(client, authorization: authorization)
      guard let updated = try patch(current) else { return .skipped }
      try await Self.writePreferences(
        client, authorization: authorization, preferences: updated)
      return .wrote(updated.elements)
    }
    tail = Task { _ = try? await cycle.value }
    return try await cycle.value
  }

  /// Convenience: run a patch and return the resulting array, or the unchanged
  /// array when the patch was skipped.
  @discardableResult
  public func apply(_ patch: @escaping PreferencesUpdate) async throws -> [PrefObject] {
    switch try await update(patch) {
    case .wrote(let elements):
      return elements
    case .skipped:
      return try await fetchPreferences().elements
    }
  }

  /// Overwrites the preference array wholesale (the RN app's clear-preferences
  /// path and the saved-feeds migration write).
  public func putPreferences(_ preferences: PreferencesArray) async throws {
    try await Self.writePreferences(
      client, authorization: authorization, preferences: preferences)
  }

  // MARK: - Internal

  /// Mints a new TID.
  func nextTid() -> String {
    tids.next()
  }

  /// The generator behind ``nextTid()``, for patches that need it.
  var currentTidGenerator: TidGenerator {
    tids
  }

  // MARK: - Wire

  /// Reads the preference array losslessly.
  ///
  /// The array is decoded as raw JSON rather than through the generated union.
  /// A preference record with a `$type` the generated types do not know is
  /// preserved either way, but a record whose `$type` is missing or malformed
  /// fails the generated union decode and would take the whole preferences
  /// fetch down with it. Preferences are a user-owned bag of records, so one
  /// unrecognized entry must not break the read.
  static func readPreferences(
    _ client: XrpcClient,
    authorization: @Sendable () async throws -> String?
  ) async throws -> PreferencesArray {
    let response = try await client.rawGet(
      "app.bsky.actor.getPreferences", authorization: try await authorization())
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers, data: response.body)
    }
    let payload = try JSONDecoder().decode([String: JSONValue].self, from: response.body)
    guard let preferences = payload["preferences"], case .array(let values) = preferences else {
      return PreferencesArray()
    }
    return PreferencesArray(
      elements: values.compactMap { $0.objectValue.map(PrefObject.init(fields:)) })
  }

  /// Writes the preference array losslessly.
  ///
  /// Encoded as raw JSON for the same reason as ``readPreferences``: records
  /// the generated union cannot represent must survive a write unchanged.
  static func writePreferences(
    _ client: XrpcClient,
    authorization: @Sendable () async throws -> String?,
    preferences: PreferencesArray
  ) async throws {
    let body = try JSONEncoder().encode([
      "preferences": JSONValue.array(preferences.elements.map { .object($0.fields) })
    ])
    let response = try await client.rawPost(
      "app.bsky.actor.putPreferences", body: body, contentType: "application/json",
      authorization: try await authorization())
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers, data: response.body)
    }
  }
}
