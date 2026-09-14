import Foundation

/// A payload held by the store.
///
/// Values set through the public API are held decoded; values restored from a
/// persisted snapshot are held as their encoded bytes and decoded lazily, on the
/// first read that asks for their type. That is what makes a restore possible
/// without knowing every payload type up front.
enum StoredPayload: Sendable {
  case decoded(any Sendable)
  case encoded(Data)

  /// Returns the payload as `V`, decoding it first when it was restored from a
  /// persisted snapshot.
  ///
  /// - Returns: the typed payload, or `nil` when the stored value holds a
  ///   different type. The store reports that as a type mismatch, which means the
  ///   same key was reused with two payload types.
  func decode<V: Sendable>(as type: V.Type) -> V? {
    switch self {
    case .decoded(let value):
      return value as? V
    case .encoded(let data):
      guard let persistable = V.self as? any Persistable.Type else { return nil }
      return (try? persistable.decodePersisted(data)) as? V
    }
  }

  /// The payload as an erased `Sendable`, when it is held decoded.
  ///
  /// Restored payloads return `nil` here: nothing can hand their bytes back
  /// without knowing the concrete type.
  var erasedValue: (any Sendable)? {
    if case .decoded(let value) = self { return value }
    return nil
  }

  /// Encoded bytes for persistence, or `nil` when the payload cannot be encoded.
  func encodedBytes() -> Data? {
    switch self {
    case .decoded(let value):
      guard let persistable = value as? any Persistable else { return nil }
      return try? persistable.encodePersisted()
    case .encoded(let data):
      return data
    }
  }
}

/// Requirements needed to restore a payload whose concrete type is only known
/// from the call site, reached through an existential.
public protocol Persistable: Sendable, Codable {
  /// Encodes this value for persistence.
  func encodePersisted() throws -> Data
  static func decodePersisted(_ data: Data) throws -> Self
}

extension Persistable {
  public func encodePersisted() throws -> Data {
    try JSONEncoder().encode(self)
  }

  public static func decodePersisted(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }
}

/// A payload that may be written to a persistence sink.
///
/// Marking a payload `QueryPayload` is what makes it eligible for persistence:
/// only such payloads are written, mirroring the `shouldDehydrateQuery`
/// predicate in `src/lib/react-query.tsx`. A `QueryPayload` must be `Codable`
/// and `Sendable`; JSON round-tripping is supplied by default.
///
/// ```swift
/// struct FeedPage: QueryPayload {
///   let items: [Post]
///   let cursor: String?
/// }
/// ```
public protocol QueryPayload: Persistable {}
