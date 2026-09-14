import FoundationEssentials

/// Namespace for atproto syntax validation.
public enum ATSyntax {}

/// Validation failure for an atproto syntax type.
public struct ATSyntaxError: Error, Sendable, CustomStringConvertible {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var description: String { message }
}

// MARK: - NSID

/// Namespaced identifier (e.g. `app.bsky.feed.post`).
///
/// Port of @atproto/syntax nsid.ts validation semantics.
public struct Nsid: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// Throws if `rawValue` is not a valid NSID.
  public init(_ rawValue: String) throws {
    try ATSyntax.ensureValidNsid(rawValue)
    self.rawValue = rawValue
  }

  /// Unvalidated. Only use when the source is already trusted (e.g. decoded
  /// data validated elsewhere).
  public init(unvalidated rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }

  /// Authority segments (all but the last): `["app", "bsky", "feed"]`.
  public var segments: [String] { rawValue.split(separator: ".").map(String.init) }

  /// The name (final segment): `"post"`.
  public var name: String { segments.last ?? "" }

  /// The authority: `"app.bsky.feed"`.
  public var authority: String { segments.dropLast().joined(separator: ".") }
}

extension ATSyntax {

  /// NSID total length limit (253 authority + 1 dot + 63 name).
  private static let nsidMaxLength = 253 + 1 + 63

  /// First authority label, middle labels (one or more), then final name label.
  private nonisolated(unsafe) static let nsidRegex = /^[a-zA-Z](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+(?:\.[a-zA-Z](?:[a-zA-Z0-9]{0,62})?)$/

  /// Throws `ATSyntaxError` unless `value` is a valid NSID.
  public static func ensureValidNsid(_ value: String) throws {
    if value.count > nsidMaxLength {
      throw ATSyntaxError("NSID is too long (317 chars max)")
    }
    if value.count < 5 || value.wholeMatch(of: nsidRegex) == nil {
      throw ATSyntaxError("NSID didn't validate via regex")
    }
  }

  public static func isValidNsid(_ value: String) -> Bool {
    (try? ensureValidNsid(value)) != nil
  }
}

// MARK: - DID

/// Decentralized identifier (e.g. `did:plc:abcdef`).
///
/// Port of @atproto/syntax did.ts validation semantics (regex variant, which
/// the package itself uses for `isValidDid`).
public struct Did: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// Throws if `rawValue` is not a valid DID.
  public init(_ rawValue: String) throws {
    try ATSyntax.ensureValidDid(rawValue)
    self.rawValue = rawValue
  }

  public init(unvalidated rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }

  /// The method (`plc`, `web`, ...). Empty when unparseable.
  public var method: String {
    let parts = rawValue.split(separator: ":", maxSplits: 2)
    guard parts.count >= 2 else { return "" }
    return String(parts[1])
  }
}

extension ATSyntax {

  private static let didMaxLength = 2048

  // did:method:content — method is lower-case letters; content is boring ASCII
  // that cannot end with ":" or "%".
  private nonisolated(unsafe) static let didRegex = /^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$/

  /// Throws `ATSyntaxError` unless `value` is a valid DID.
  public static func ensureValidDid(_ value: String) throws {
    if value.count > didMaxLength {
      throw ATSyntaxError("DID is too long (2048 chars max)")
    }
    if value.wholeMatch(of: didRegex) == nil {
      throw ATSyntaxError("DID didn't validate via regex")
    }
  }

  public static func isValidDid(_ value: String) -> Bool {
    (try? ensureValidDid(value)) != nil
  }
}

// MARK: - Handle

/// User handle (e.g. `alice.example`).
///
/// Port of @atproto/syntax handle.ts validation semantics.
public struct Handle: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// Throws if `rawValue` is not a valid handle.
  public init(_ rawValue: String) throws {
    try ATSyntax.ensureValidHandle(rawValue)
    self.rawValue = rawValue
  }

  public init(unvalidated rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }

  /// Handles are equal if the same lower-case form; expose the normalized form.
  public var normalized: String { rawValue.lowercased() }
}

extension ATSyntax {

  /// The placeholder handle used in some flows.
  public static let invalidHandle = "handle.invalid"

  /// Registration-time (not protocol-level) restricted TLDs.
  public static let disallowedTlds: [String] = [
    ".local", ".arpa", ".invalid", ".localhost", ".internal", ".example",
    ".alt",
    // policy could conceivably change on ".onion" some day
    ".onion",
    // NOTE: .test is allowed in testing and development
  ]

  private static let handleMaxLength = 253
  private static let handlePartMax = 63

  private nonisolated(unsafe) static let handleRegex = /^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/

  /// Throws `ATSyntaxError` unless `value` is a valid handle.
  public static func ensureValidHandle(_ value: String) throws {
    // check that all chars are boring ASCII
    let allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
    if !value.allSatisfy({ allowed.contains($0) }) {
      throw ATSyntaxError("Disallowed characters in handle (ASCII letters, digits, dashes, periods only)")
    }
    if value.count > handleMaxLength {
      throw ATSyntaxError("Handle is too long (253 chars max)")
    }
    let labels = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    if labels.count < 2 {
      throw ATSyntaxError("Handle domain needs at least two parts")
    }
    for (i, label) in labels.enumerated() {
      if label.isEmpty {
        throw ATSyntaxError("Handle parts can not be empty")
      }
      if label.count > handlePartMax {
        throw ATSyntaxError("Handle part too long (max 63 chars)")
      }
      if label.hasPrefix("-") || label.hasSuffix("-") {
        throw ATSyntaxError("Handle parts can not start or end with hyphens")
      }
      if i + 1 == labels.count && !label.first!.isASCIILetter {
        throw ATSyntaxError("Handle final component (TLD) must start with ASCII letter")
      }
    }
  }

  public static func isValidHandle(_ value: String) -> Bool {
    (try? ensureValidHandle(value)) != nil
  }
}

extension Character {
  var isASCIILetter: Bool {
    guard let scalar = unicodeScalars.first else { return false }
    return (scalar.value >= 97 && scalar.value <= 122)
      || (scalar.value >= 65 && scalar.value <= 90)
  }
}

// MARK: - RecordKey

/// Record key (the `rkey` of an at-uri, e.g. `3jz7e4l2kx5r` or `self`).
///
/// Port of @atproto/syntax recordkey.ts validation semantics.
public struct RecordKey: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// Throws if `rawValue` is not a valid record key.
  public init(_ rawValue: String) throws {
    try ATSyntax.ensureValidRecordKey(rawValue)
    self.rawValue = rawValue
  }

  public init(unvalidated rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

extension ATSyntax {

  private static let recordKeyMaxLength = 512
  private static let recordKeyMinLength = 1
  private static let recordKeyInvalidValues: Set<String> = [".", ".."]
  private nonisolated(unsafe) static let recordKeyRegex = /^[a-zA-Z0-9_~.:-]{1,512}$/

  /// Throws `ATSyntaxError` unless `value` is a valid record key.
  public static func ensureValidRecordKey(_ value: String) throws {
    if value.count > recordKeyMaxLength || value.count < recordKeyMinLength {
      throw ATSyntaxError("record key must be 1 to 512 characters")
    }
    if recordKeyInvalidValues.contains(value) {
      throw ATSyntaxError("record key can not be \".\" or \"..\"")
    }
    if value.wholeMatch(of: recordKeyRegex) == nil {
      throw ATSyntaxError("record key syntax not valid (regex)")
    }
  }

  public static func isValidRecordKey(_ value: String) -> Bool {
    (try? ensureValidRecordKey(value)) != nil
  }
}

// MARK: - AtIdentifier

/// A DID *or* handle (used in at-uris and API params).
///
/// Port of @atproto/syntax at-identifier.ts.
public enum AtIdentifier: Hashable, Sendable, CustomStringConvertible {
  case did(Did)
  case handle(Handle)

  /// Throws if `rawValue` is neither a valid DID nor a valid handle.
  public init(_ rawValue: String) throws {
    if rawValue.hasPrefix("did:") {
      self = .did(try Did(rawValue))
    } else {
      self = .handle(try Handle(rawValue))
    }
  }

  public var description: String {
    switch self {
    case .did(let d): d.rawValue
    case .handle(let h): h.rawValue
    }
  }

  public var did: Did? {
    if case .did(let d) = self { return d }
    return nil
  }

  public var handle: Handle? {
    if case .handle(let h) = self { return h }
    return nil
  }
}

// MARK: - TID

/// Timestamp identifier (13-char base32-sortable string).
///
/// Port of @atproto/syntax tid.ts.
public struct Tid: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// Throws if `rawValue` is not a valid TID.
  public init(_ rawValue: String) throws {
    try ATSyntax.ensureValidTid(rawValue)
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

extension ATSyntax {

  /// 13 characters; first char from the "high" digit set (never 0/1 for
  /// sortability), rest from the full base32-sortable alphabet.
  private static let tidLength = 13
  private nonisolated(unsafe) static let tidRegex = /^[234567abcdefghij][234567abcdefghijklmnopqrstuvwxyz]{12}$/

  /// Throws `ATSyntaxError` unless `value` is a valid TID.
  public static func ensureValidTid(_ value: String) throws {
    if value.count != tidLength {
      throw ATSyntaxError("TID must be 13 characters")
    }
    if value.wholeMatch(of: tidRegex) == nil {
      throw ATSyntaxError("TID syntax not valid (regex)")
    }
  }

  public static func isValidTid(_ value: String) -> Bool {
    (try? ensureValidTid(value)) != nil
  }
}
