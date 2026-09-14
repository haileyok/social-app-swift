import Foundation

import SwiftAtproto

/// A preference write rejected before it reaches the server.
public struct PreferencesError: Error, Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    /// A saved feed carried no `id`.
    case savedFeedMissingId
    /// A saved feed's `value` AT URI had the wrong collection for its type.
    case savedFeedWrongCollection(type: String, collection: String?)
    /// A DID failed wire validation.
    case invalidDid(String)
    /// A NUX record failed validation.
    case invalidNux(String)
    /// A preference record's `$type` was missing.
    case missingType
  }

  public let kind: Kind

  public init(_ kind: Kind) {
    self.kind = kind
  }

  public static func == (lhs: PreferencesError, rhs: PreferencesError) -> Bool {
    lhs.kind == rhs.kind
  }
}

/// Saved-feed helpers (port of the SDK's saved-feeds module-level functions).
public enum SavedFeeds {
  public static let generatorCollection = "app.bsky.feed.generator"
  public static let listCollection = "app.bsky.graph.list"

  /// Infers the saved-feed `type` from a saved-feed URI. `following` is the
  /// timeline; anything else must be a feed generator or a list.
  public static func type(forUri uri: String) -> String? {
    if uri == "following" { return "timeline" }
    guard let parsed = try? ATURI(string: uri) else { return nil }
    switch parsed.collection?.rawValue {
    case generatorCollection: return "feed"
    case listCollection: return "list"
    default: return nil
    }
  }

  /// Validates a saved feed before writing it, mirroring `validateSavedFeed`.
  public static func validate(_ feed: PrefObject) throws {
    guard let id = feed["id"]?.stringValue, !id.isEmpty else {
      throw PreferencesError(.savedFeedMissingId)
    }
    guard let type = feed["type"]?.stringValue else {
      throw PreferencesError(.missingType)
    }
    guard type == "feed" || type == "list" else { return }
    guard let value = feed["value"]?.stringValue else {
      throw PreferencesError(.savedFeedMissingId)
    }
    let collection = (try? ATURI(string: value))?.collection?.rawValue
    if type == "feed" && collection != generatorCollection {
      throw PreferencesError(
        .savedFeedWrongCollection(type: type, collection: collection))
    }
    if type == "list" && collection != listCollection {
      throw PreferencesError(
        .savedFeedWrongCollection(type: type, collection: collection))
    }
  }
}

/// Value hygiene for muted words (port of `utils/muted-words`).
public enum MutedWords {
  /// Trims, drops a leading `#` (unless followed by a variation selector), and
  /// strips zero-width/control characters. Empty input yields `""`, which
  /// callers treat as "skip this word".
  public static func sanitize(_ value: String) -> String {
    var out = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if out.hasPrefix("#") {
      let rest = out.dropFirst()
      if rest.first != "\u{FE0F}" {
        out = String(rest)
      }
    }
    let stripped: Set<Character> = [
      "\r", "\n", "\u{00AD}", "\u{2060}", "\u{200D}", "\u{200C}", "\u{200B}",
    ]
    return String(out.filter { !stripped.contains($0) })
  }
}

/// NUX validation (port of `utils/nux.validateNux`).
public enum Nux {
  private static let allowedKeys: Set<String> = ["id", "completed", "data", "expiresAt"]

  public static func validate(_ nux: PrefObject) throws {
    guard let id = nux["id"]?.stringValue, id.utf8.count <= 100 else {
      throw PreferencesError(.invalidNux("id"))
    }
    guard nux["completed"]?.boolValue != nil else {
      throw PreferencesError(.invalidNux("completed"))
    }
    if let data = nux["data"]?.stringValue {
      guard data.utf8.count <= 3000, data.count <= 300 else {
        throw PreferencesError(.invalidNux("data"))
      }
    }
    if nux["expiresAt"]?.stringValue != nil {
      guard nux["expiresAt"]?.decoded(as: FormatString<Date>.self) != nil else {
        throw PreferencesError(.invalidNux("expiresAt"))
      }
    }
    for key in nux.fields.keys where !allowedKeys.contains(key) {
      throw PreferencesError(.invalidNux("unexpected:\(key)"))
    }
  }
}

/// DID wire validation (port of `ensureValidDidRegex`).
public enum DIDValidation {
  public static func validate(_ did: String) throws {
    guard (try? DID(string: did)) != nil else {
      throw PreferencesError(.invalidDid(did))
    }
  }
}
