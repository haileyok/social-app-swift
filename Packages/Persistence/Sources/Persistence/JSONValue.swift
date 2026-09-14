import Foundation

/// A structural JSON value.
///
/// Persistence needs to inspect stored data whose Swift shape is not known
/// ahead of time: migration payloads move between schema versions, and
/// tolerant decoding salvages the well-formed parts of a malformed document.
/// `JSONValue` is the intermediate representation both of those paths use, so
/// neither has to re-encode raw bytes to look at a field.
public enum JSONValue: Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "unsupported JSON value")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

extension JSONValue {
  /// The object members, or `nil` when this is not a JSON object.
  public var objectValue: [String: JSONValue]? {
    if case .object(let members) = self { return members }
    return nil
  }

  /// The array elements, or `nil` when this is not a JSON array.
  public var arrayValue: [JSONValue]? {
    if case .array(let elements) = self { return elements }
    return nil
  }

  /// The string, or `nil` when this is not a JSON string.
  public var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  /// The boolean, or `nil` when this is not a JSON boolean.
  public var boolValue: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  /// The number, or `nil` when this is not a JSON number.
  public var numberValue: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  /// Re-encodes this value and decodes it as `type`.
  ///
  /// This is the bridge from the structural representation back into typed
  /// schema fields. It returns `nil` rather than throwing, because callers
  /// treat a mismatch as "fall back to the field default".
  public func decoded<T: Decodable>(as type: T.Type) -> T? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}

/// One field-level decode failure inside a persisted document.
///
/// Tolerant decoding records these instead of discarding the whole document,
/// so a caller can log exactly which field fell back and to what.
public struct DecodeIssue: Sendable, Equatable {
  /// Dotted path of the offending field (e.g. `session.accounts[0].service`).
  public let field: String

  /// Human-readable description of the problem.
  public let detail: String

  public init(field: String, detail: String) {
    self.field = field
    self.detail = detail
  }
}
