import Foundation

/// A JSON value, or object, held losslessly.
///
/// A local alias of `Preferences.JSONValue` would couple this package to
/// Preferences for no reason, so the shape is declared here. It covers both
/// directions and keeps integers and fractional numbers distinct.
public enum StarterPackJSON: Sendable, Hashable {
  /// JSON null.
  case null
  /// A boolean.
  case bool(Bool)
  /// An integer.
  case int(Int)
  /// A fractional number.
  case double(Double)
  /// A string.
  case string(String)
  /// An array.
  case array([StarterPackJSON])
  /// An object.
  case object([String: StarterPackJSON])
}

extension StarterPackJSON: Codable {
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
    } else if let value = try? container.decode([StarterPackJSON].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: StarterPackJSON].self) {
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

extension StarterPackJSON {
  /// The string, when this value is a JSON string.
  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  /// The object members, when this value is a JSON object.
  public var objectValue: [String: StarterPackJSON]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  /// The array elements, when this value is a JSON array.
  public var arrayValue: [StarterPackJSON]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  /// A member by name, when this value is a JSON object.
  public subscript(key: String) -> StarterPackJSON? {
    objectValue?[key]
  }
}
