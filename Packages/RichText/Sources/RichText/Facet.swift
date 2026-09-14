/// AT Protocol richtext facet types: `app.bsky.richtext.facet` and its features.
///
/// Ported from the `@bsky/sdk` lexicon builders used by `rich-text.js` and
/// `detection.js`. Facet offsets are UTF-8 byte indices into the post text
/// (see ``UnicodeString``), start-inclusive and end-exclusive.
public enum FacetType {
  public static let link = "app.bsky.richtext.facet#link"
  public static let mention = "app.bsky.richtext.facet#mention"
  public static let tag = "app.bsky.richtext.facet#tag"
}

/// The byte range a facet covers, as `{"byteStart": n, "byteEnd": m}`.
public struct ByteSlice: Codable, Hashable, Sendable {
  public var byteStart: Int
  public var byteEnd: Int

  public init(byteStart: Int, byteEnd: Int) {
    self.byteStart = byteStart
    self.byteEnd = byteEnd
  }
}

/// A single facet feature: exactly one of a link, a mention, or a tag.
///
/// The TS engine models these as three separate `$typed` objects discriminated by
/// `$type`. A Swift enum carrying the discriminator as an explicit ``type`` keeps
/// the same wire shape while making "a segment's feature is a link" a single
/// switch instead of a scan over a heterogeneous array.
public enum FacetFeature: Codable, Hashable, Sendable {
  /// A detected URL. `uri` is the resolved destination, which for schemeless
  /// input has `https://` prepended and for trailing-punctuation input has the
  /// punctuation trimmed.
  case link(uri: String)
  /// A detected handle. The TS engine writes the raw matched handle into `did`
  /// when detection runs without resolution; callers are expected to resolve it
  /// to a real DID, and an empty `did` means "unresolved".
  case mention(did: String)
  /// A hashtag (or cashtag). `tag` excludes the leading `#`/`$` for hashtags and
  /// includes the `$` for cashtags, matching `detection.js`.
  case tag(tag: String)

  /// The `$type` discriminator, mirroring the lexicon NSID.
  public var type: String {
    switch self {
    case .link: FacetType.link
    case .mention: FacetType.mention
    case .tag: FacetType.tag
    }
  }

  /// The feature's payload string: `uri`, `did`, or `tag`.
  public var value: String {
    switch self {
    case .link(let uri): uri
    case .mention(let did): did
    case .tag(let tag): tag
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
    case uri
    case did
    case tag
  }

  private enum Kind: String, Codable {
    case link = "app.bsky.richtext.facet#link"
    case mention = "app.bsky.richtext.facet#mention"
    case tag = "app.bsky.richtext.facet#tag"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .link:
      self = .link(uri: try container.decode(String.self, forKey: .uri))
    case .mention:
      self = .mention(did: try container.decode(String.self, forKey: .did))
    case .tag:
      self = .tag(tag: try container.decode(String.self, forKey: .tag))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .link(let uri):
      try container.encode(Kind.link, forKey: .type)
      try container.encode(uri, forKey: .uri)
    case .mention(let did):
      try container.encode(Kind.mention, forKey: .type)
      try container.encode(did, forKey: .did)
    case .tag(let tag):
      try container.encode(Kind.tag, forKey: .type)
      try container.encode(tag, forKey: .tag)
    }
  }
}

/// A facet: a byte range plus the feature(s) attached to it.
///
/// The lexicon types `features` as an array, and detection only ever emits one
/// feature per facet, but the array is preserved so decoded facets round-trip
/// unchanged.
public struct Facet: Codable, Hashable, Sendable {
  public var index: ByteSlice
  public var features: [FacetFeature]

  public init(index: ByteSlice, features: [FacetFeature]) {
    self.index = index
    self.features = features
  }

  /// Convenience for the single-feature facets detection produces.
  public init(byteStart: Int, byteEnd: Int, feature: FacetFeature) {
    self.init(index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd), features: [feature])
  }

  /// The first link feature, if any. `RichTextSegment#link` in the TS engine.
  public var link: String? {
    for case .link(let uri) in features { return uri }
    return nil
  }

  /// The first mention feature's `did`, if any.
  public var mention: String? {
    for case .mention(let did) in features { return did }
    return nil
  }

  /// The first tag feature, if any.
  public var tag: String? {
    for case .tag(let tag) in features { return tag }
    return nil
  }
}

/// One facet to transfer onto a plain-text entity range, for
/// ``RichText/init(text:entities:)``.
///
/// Ported from the `entities` branch of the `RichText` constructor, which
/// converts UTF-16-indexed entities into UTF-8-indexed facets. Only `link` and
/// `mention` entity types are accepted, matching `entitiesToFacets`.
public struct RichTextEntity: Hashable, Sendable {
  public enum Kind: String, Sendable {
    case link
    case mention
  }

  public var type: Kind
  /// The feature payload: a URI for `.link`, a DID for `.mention`.
  public var value: String
  public var start: Int
  public var end: Int

  public init(type: Kind, value: String, start: Int, end: Int) {
    self.type = type
    self.value = value
    self.start = start
    self.end = end
  }
}
