import Foundation

import Lexicons
import SwiftAtproto

/// Shared JSON coding for preference payloads.
///
/// Preference records are read back from servers that may have written a
/// value our generated lexicon constraints reject (for example an interests
/// tag list longer than the authoring limit). The TypeScript engine performs
/// no constraint validation on read, so decoding runs in `.permissive` mode to
/// match it.
public enum PreferencesJSON {
  public static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.userInfo[.atprotoLexiconDecodingMode] = LexiconDecodingMode.permissive
    return decoder
  }

  public static var encoder: JSONEncoder {
    JSONEncoder()
  }
}

/// A JSON value, or object, held losslessly.
///
/// `AnyCodable` from the vendored runtime can only be *constructed* by
/// decoding, so it cannot represent a value this module authors. `JSONValue`
/// covers both directions and keeps the distinction between integers and
/// fractional numbers, so a round-trip through it does not disturb a record
/// the server wrote.
public enum JSONValue: Sendable, Hashable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "value is not JSON")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}

extension JSONValue {
  /// Wraps any `Encodable` value as a `JSONValue` by encoding it and reading
  /// the result back. Values that are not representable (which none of this
  /// module's inputs are) degrade to JSON `null`.
  public init(_ value: some Encodable) {
    guard let data = try? PreferencesJSON.encoder.encode(value),
      let decoded = try? PreferencesJSON.decoder.decode(JSONValue.self, from: data)
    else {
      self = .null
      return
    }
    self = decoded
  }

  /// The string, when this value is a JSON string.
  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  /// The boolean, when this value is a JSON boolean.
  public var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  /// The integer, when this value is a JSON integer.
  public var intValue: Int? {
    guard case .int(let value) = self else { return nil }
    return value
  }

  /// The string array, when this value is a JSON array of strings.
  public var stringArrayValue: [String]? {
    guard case .array(let values) = self else { return nil }
    let strings = values.compactMap(\.stringValue)
    guard strings.count == values.count else { return nil }
    return strings
  }

  /// The object members, when this value is a JSON object.
  public var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  /// Re-encodes this value and decodes it as `T`, for members whose wire shape
  /// is a generated type (for example a datetime).
  public func decoded<T: Decodable>(as type: T.Type = T.self) -> T? {
    guard let data = try? PreferencesJSON.encoder.encode(self) else { return nil }
    return try? PreferencesJSON.decoder.decode(T.self, from: data)
  }
}

/// The `$type` discriminants under `app.bsky.actor.defs`, as they appear on
/// the wire.
public enum PrefType {
  public static let adultContentPref = "app.bsky.actor.defs#adultContentPref"
  public static let contentLabelPref = "app.bsky.actor.defs#contentLabelPref"
  public static let savedFeedsPref = "app.bsky.actor.defs#savedFeedsPref"
  public static let savedFeedsPrefV2 = "app.bsky.actor.defs#savedFeedsPrefV2"
  public static let personalDetailsPref = "app.bsky.actor.defs#personalDetailsPref"
  public static let declaredAgePref = "app.bsky.actor.defs#declaredAgePref"
  public static let feedViewPref = "app.bsky.actor.defs#feedViewPref"
  public static let threadViewPref = "app.bsky.actor.defs#threadViewPref"
  public static let interestsPref = "app.bsky.actor.defs#interestsPref"
  public static let mutedWordsPref = "app.bsky.actor.defs#mutedWordsPref"
  public static let hiddenPostsPref = "app.bsky.actor.defs#hiddenPostsPref"
  public static let bskyAppStatePref = "app.bsky.actor.defs#bskyAppStatePref"
  public static let labelersPref = "app.bsky.actor.defs#labelersPref"
  public static let postInteractionSettingsPref =
    "app.bsky.actor.defs#postInteractionSettingsPref"
  public static let verificationPrefs = "app.bsky.actor.defs#verificationPrefs"
  public static let liveEventPreferences = "app.bsky.actor.defs#liveEventPreferences"
}

/// A single preference record held as a JSON object.
///
/// The engine patches preferences by rewriting individual members of a record,
/// mirroring the SDK's `$build({...existing, field: value})` spread. Keeping
/// the record as a JSON object (rather than a typed struct) is what preserves
/// members the generated types do not know about: a `$build` spread copies
/// them through, and so does this.
public struct PrefObject: Sendable, Hashable {
  /// The record members, including `$type`.
  public var fields: [String: JSONValue]

  public init(fields: [String: JSONValue]) {
    self.fields = fields
  }

  /// The record's `$type` discriminant.
  public var type: String? {
    fields["$type"]?.stringValue
  }

  /// A member by name, or nil when absent.
  public subscript(key: String) -> JSONValue? {
    fields[key]
  }

  /// Decodes a member into a typed value, or nil when the member is absent.
  public func typed<T: Decodable>(_ key: String, as type: T.Type = T.self) throws -> T? {
    guard let value = fields[key] else { return nil }
    let data = try PreferencesJSON.encoder.encode(value)
    return try PreferencesJSON.decoder.decode(T.self, from: data)
  }

  /// Sets a member, overwriting any existing value.
  public mutating func set(_ key: String, _ value: some Encodable) {
    fields[key] = JSONValue(value)
  }

  /// Removes a member entirely (the SDK's "undefined means absent" posture).
  public mutating func remove(_ key: String) {
    fields.removeValue(forKey: key)
  }

  /// Encodes back into the generated union for the `putPreferences` body.
  public func encoded() throws -> App.Bsky.ActorDefs_Preferences_Elem {
    let data = try PreferencesJSON.encoder.encode(fields)
    return try PreferencesJSON.decoder.decode(
      App.Bsky.ActorDefs_Preferences_Elem.self, from: data)
  }
}

extension PrefObject {
  /// Decodes a generated union element into its JSON-object form.
  public init(_ element: App.Bsky.ActorDefs_Preferences_Elem) throws {
    let data = try PreferencesJSON.encoder.encode(element)
    self.fields = try PreferencesJSON.decoder.decode([String: JSONValue].self, from: data)
  }

  /// Builds a new record with the given `$type` and no members yet.
  public static func make(_ type: String) -> PrefObject {
    PrefObject(fields: ["$type": .string(type)])
  }
}

extension PrefObject {
  /// Reads a member that is an array of JSON objects (the shape of the nested
  /// arrays in saved feeds, muted words and NUXs).
  public func objectArray(_ key: String) throws -> [PrefObject] {
    guard let value = fields[key] else { return [] }
    guard case .array(let values) = value else { return [] }
    return values.compactMap { $0.objectValue.map(PrefObject.init(fields:)) }
  }

  /// Replaces a member with an array of JSON objects.
  public mutating func setObjectArray(_ key: String, _ objects: [PrefObject]) {
    set(key, objects.map(\.fields))
  }
}

extension PrefObject: Encodable {
  public func encode(to encoder: any Encoder) throws {
    try fields.encode(to: encoder)
  }
}
