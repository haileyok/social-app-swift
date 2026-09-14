import FoundationEssentials

/// at:// URI (e.g. `at://did:plc:abc/app.bsky.feed.post/3jz7e4l`).
///
/// Port of @atproto/syntax aturi_validation.ts `parseAtUriString`
/// (strict mode): fully-anchored regex with named groups, ASCII charset
/// gate, identifier/NSID/rkey validation, JSON-pointer fragment rules.
/// The legacy `AtUri` class in aturi.ts is more permissive; the interop
/// fixtures follow the strict rules.
public struct AtUri: Hashable, Sendable, CustomStringConvertible {

  /// Authority (DID or handle string), validated.
  public let host: String

  /// Collection NSID, when present.
  public let collection: String?

  /// Record key, when present (validated in strict mode).
  public let rkey: String?

  /// Fragment *without* leading `#`; `""` when absent.
  public let hash: String

  /// True when the input ended with `/` (rejected in strict mode).
  public let hadTrailingSlash: Bool

  /// Query pairs (present only via non-strict parse; strict rejects queries).
  public var searchParams: [(name: String, value: String)] = []

  /// Parses and validates an at-uri in strict mode. Throws `ATSyntaxError`.
  public init(_ uri: String) throws {
    try self.init(uri, strict: true)
  }

  /// Parses with the strictness of `parseAtUriString(input, {strict:})`.
  /// Non-strict allows trailing slash and query params and skips rkey
  /// validation (mirroring `isValidAtUri`).
  public init(_ uri: String, strict: Bool) throws {
    if uri.count > 8192 {
      throw ATSyntaxError("ATURI exceeds maximum length")
    }
    // ASCII charset gate (anything outside the allowed set fails fast).
    let allowed = Set(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        + "0123456789._~:@!$&'()*+,;=%/\\[]#?-")
    if uri.contains(where: { !allowed.contains($0) }) {
      throw ATSyntaxError("Disallowed characters in ATURI (ASCII)")
    }
    guard let m = uri.wholeMatch(of: Self.atUriRegex) else {
      throw ATSyntaxError("ATURI does not match expected format")
    }
    let authority = String(m.output.1)
    let collection = m.output.2.map(String.init)
    let rkey = m.output.3.map(String.init)
    let trailingSlash = m.output.4 != nil
    let query = m.output.5.map(String.init) ?? ""
    let hash = m.output.6.map(String.init) ?? ""

    guard (try? AtIdentifier(authority)) != nil else {
      throw ATSyntaxError("ATURI has invalid authority")
    }
    if let collection, !ATSyntax.isValidNsid(collection) {
      throw ATSyntaxError("ATURI has invalid collection")
    }
    // A present-but-empty fragment fails the JSON-pointer check (it must
    // start with "/"), so validate whenever the group matched at all.
    if m.output.6 != nil {
      try Self.validateFragment(hash, strict: strict)
    }
    if strict {
      if trailingSlash {
        throw ATSyntaxError("ATURI can not have a trailing slash")
      }
      if m.output.5 != nil {
        throw ATSyntaxError("ATURI query part is not allowed")
      }
      if let rkey, !ATSyntax.isValidRecordKey(rkey) {
        throw ATSyntaxError("ATURI has invalid record key")
      }
    }
    self.host = authority
    self.collection = collection
    self.rkey = rkey
    self.hash = hash
    self.hadTrailingSlash = trailingSlash
    if !query.isEmpty {
      self.searchParams = Self.parseQuery(query)
    }
  }

  /// Builds `at://<host>/<collection>/<rkey>` validating each part.
  public static func make(
    _ handleOrDid: String, collection: String? = nil, rkey: String? = nil
  ) throws -> AtUri {
    var str = "at://" + handleOrDid
    if let collection { str += "/" + collection }
    if let rkey { str += "/" + rkey }
    return try AtUri(str)
  }

  /// Fully-anchored, mirroring AT_URI_REGEXP:
  /// `^(at://(authority)(/(collection)(/(rkey))?)(/)?)(?(query)?)(#(hash))?$`
  /// (The `at://` prefix group is intentionally non-capturing here since
  /// `wholeMatch` already anchors both ends.)
  private nonisolated(unsafe) static let atUriRegex: Regex<(
    Substring, Substring, Substring?, Substring?, Substring?, Substring?,
    Substring?
  )> = try! Regex(
    "at://([^/?#\\s]+)(?:/([^/?#\\s]+)(?:/([^/?#\\s]+))?)?(/)?(?:\\?([^#\\s]*))?(?:#([^\\s]*))?"
  )

  /// Fragment validation: loose JSON-pointer syntax; strict mode also
  /// requires *valid* percent-encoding.
  private static func validateFragment(_ value: String, strict: Bool) throws {
    // chars: alnum + ._~:@!$&'()*+,;=% + []/- (trailing dash literal)
    let pointer = try! Regex(
      "/[a-zA-Z0-9._~:@!$&')(*+,;=%\\[\\]/-]*"
    )
    if value.wholeMatch(of: pointer) == nil {
      throw ATSyntaxError("Invalid JSON pointer")
    }
    if value.contains("%") {
      do {
        _ = try Self.percentDecode(value)
      } catch {
        if strict { throw error }
        // non-strict allows invalid percent-encoding in the fragment
      }
    }
  }

  /// Decodes `%XX` sequences; throws on malformed sequences.
  private static func percentDecode(_ value: String) throws -> String {
    var out = [UInt8]()
    out.reserveCapacity(value.utf8.count)
    var bytes = Array(value.utf8)
    var i = 0
    while i < bytes.count {
      if bytes[i] == 0x25 {  // '%'
        guard i + 2 < bytes.count,
          let hi = Self.hexValue(bytes[i + 1]),
          let lo = Self.hexValue(bytes[i + 2])
        else {
          throw ATSyntaxError("Invalid percent-encoding")
        }
        out.append(UInt8(hi << 4 | lo))
        i += 3
      } else {
        out.append(bytes[i])
        i += 1
      }
    }
    guard let decoded = String(bytes: out, encoding: .utf8) else {
      throw ATSyntaxError("Invalid percent-encoding")
    }
    return decoded
  }

  private static func hexValue(_ byte: UInt8) -> Int? {
    switch byte {
    case 0x30...0x39: return Int(byte - 0x30)  // 0-9
    case 0x41...0x46: return Int(byte - 0x41 + 10)  // A-F
    case 0x61...0x66: return Int(byte - 0x61 + 10)  // a-f
    default: return nil
    }
  }

  /// Parses `a=b&c=d` (no leading `?`).
  private static func parseQuery(_ query: String) -> [(String, String)] {
    query.split(separator: "&").map { pair -> (String, String) in
      let kv = pair.split(separator: "=", maxSplits: 1)
      let name = String(kv.first ?? "")
      let value = kv.count > 1 ? String(kv[1]) : ""
      return (name, value)
    }
  }

  /// Serialized query string (no leading `?`), or empty.
  public var search: String {
    guard !searchParams.isEmpty else { return "" }
    return searchParams.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
  }

  /// Path (`/collection/rkey` or `""`).
  public var pathname: String {
    var parts: [String] = []
    if let collection { parts.append(collection) }
    if let rkey { parts.append(rkey) }
    return parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
  }

  /// Collection, validated NSID; `""` when absent.
  public var collectionSafe: String { collection ?? "" }

  /// Record key; `""` when absent.
  public var rkeySafe: String { rkey ?? "" }

  /// The host as a DID, throwing when the host is a handle.
  public var did: String {
    get throws {
      if host.hasPrefix("did:") { return host }
      throw ATSyntaxError("AtUri \"\(self)\" does not have a DID hostname")
    }
  }

  /// Serialized form.
  public var description: String {
    var s = "at://\(host)"
    if let collection { s += "/" + collection }
    if let rkey { s += "/" + rkey }
    if hadTrailingSlash { s += "/" }
    if !searchParams.isEmpty { s += "?" + search }
    if !hash.isEmpty { s += "#" + hash }
    return s
  }

  public static func == (lhs: AtUri, rhs: AtUri) -> Bool {
    lhs.host == rhs.host && lhs.collection == rhs.collection
      && lhs.rkey == rhs.rkey && lhs.hash == rhs.hash
      && lhs.searchParams.map { "\($0.name)=\($0.value)" }
        == rhs.searchParams.map { "\($0.name)=\($0.value)" }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(host)
    hasher.combine(collection)
    hasher.combine(rkey)
    hasher.combine(hash)
    hasher.combine(searchParams.map { "\($0.name)=\($0.value)" })
  }
}
