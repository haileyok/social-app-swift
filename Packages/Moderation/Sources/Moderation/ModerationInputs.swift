import Foundation

/// A label applied to some subject by a labeler.
public struct Label: Sendable, Codable, Hashable {
  public var ver: Int?
  public var src: String
  public var uri: String
  public var cid: String?
  public var val: String
  public var neg: Bool?
  /// When the label was created (ISO-8601 string).
  public var cts: String?

  public init(
    ver: Int? = nil,
    src: String,
    uri: String,
    cid: String? = nil,
    val: String,
    neg: Bool? = nil,
    cts: String? = nil
  ) {
    self.ver = ver
    self.src = src
    self.uri = uri
    self.cid = cid
    self.val = val
    self.neg = neg
    self.cts = cts
  }
}

/// `app.bsky.graph.defs#listViewBasic`
public struct ListViewBasic: Sendable, Codable, Hashable {
  public var uri: String
  public var cid: String?
  public var name: String
  public var purpose: String?
  public var viewer: ListViewerState?
  public var labels: [Label]?

  public init(
    uri: String,
    cid: String? = nil,
    name: String,
    purpose: String? = nil,
    viewer: ListViewerState? = nil,
    labels: [Label]? = nil
  ) {
    self.uri = uri
    self.cid = cid
    self.name = name
    self.purpose = purpose
    self.viewer = viewer
    self.labels = labels
  }
}

/// `app.bsky.graph.defs#listViewerState`
public struct ListViewerState: Sendable, Codable, Hashable {
  public var muted: Bool?
  /// The lexicon declares this as the viewer's block record URI, but mock data
  /// (and the golden fixture) can carry a boolean. Both are accepted, and the
  /// engine never reads the value.
  public var blocked: String?

  public init(muted: Bool? = nil, blocked: String? = nil) {
    self.muted = muted
    self.blocked = blocked
  }

  private enum CodingKeys: String, CodingKey {
    case muted
    case blocked
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    muted = try c.decodeIfPresent(Bool.self, forKey: .muted)
    if let string = try? c.decodeIfPresent(String.self, forKey: .blocked) {
      blocked = string
    } else if let flag = try? c.decodeIfPresent(Bool.self, forKey: .blocked) {
      blocked = flag == true ? "true" : nil
    } else {
      blocked = nil
    }
  }
}

/// `app.bsky.actor.defs#viewerState`
public struct ActorViewerState: Sendable, Codable, Hashable {
  public var muted: Bool?
  public var mutedByList: ListViewBasic?
  public var blockedBy: Bool?
  /// URI of the viewer's block record against this actor.
  public var blocking: String?
  public var blockingByList: ListViewBasic?
  /// URI of the viewer's follow record for this actor.
  public var following: String?

  public init(
    muted: Bool? = nil,
    mutedByList: ListViewBasic? = nil,
    blockedBy: Bool? = nil,
    blocking: String? = nil,
    blockingByList: ListViewBasic? = nil,
    following: String? = nil
  ) {
    self.muted = muted
    self.mutedByList = mutedByList
    self.blockedBy = blockedBy
    self.blocking = blocking
    self.blockingByList = blockingByList
    self.following = following
  }
}

/// `app.bsky.actor.defs#profileViewBasic`
public struct ProfileViewBasic: Sendable, Codable, Hashable {
  public var did: String
  public var handle: String
  public var displayName: String?
  public var avatar: String?
  public var associated: ComAtprotoRepoStrongRefLike?
  public var viewer: ActorViewerState?
  public var labels: [Label]?

  public init(
    did: String,
    handle: String,
    displayName: String? = nil,
    avatar: String? = nil,
    viewer: ActorViewerState? = nil,
    labels: [Label]? = nil
  ) {
    self.did = did
    self.handle = handle
    self.displayName = displayName
    self.avatar = avatar
    self.viewer = viewer
    self.labels = labels
  }
}

/// A `{uri, cid}` reference. Decoded loosely; the engine only reads `uri`.
public struct ComAtprotoRepoStrongRefLike: Sendable, Codable, Hashable {
  public var uri: String
  public var cid: String?
}

/// `app.bsky.richtext.facet#tag` and friends. Variants the engine does not
/// read are preserved as their raw type so behavior stays faithful.
public struct RichTextFacetFeature: Sendable, Codable, Hashable {
  /// The feature's `$type`, e.g. `app.bsky.richtext.facet#tag`.
  public var type: String?
  /// Present only on tag features.
  public var tag: String?

  public init(type: String? = nil, tag: String? = nil) {
    self.type = type
    self.tag = tag
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case tag
  }
}

/// `app.bsky.richtext.facet`
public struct RichTextFacet: Sendable, Codable, Hashable {
  public var index: ByteIndex?
  public var features: [RichTextFacetFeature]?
}

/// A `{byteStart, byteEnd}` index pair.
public struct ByteIndex: Sendable, Codable, Hashable {
  public var byteStart: Int?
  public var byteEnd: Int?
}

/// An image with alt text, shared by `app.bsky.embed.images` and gallery.
public struct EmbedImage: Sendable, Codable, Hashable {
  public var alt: String?
  public var image: String?

  public init(alt: String? = nil, image: String? = nil) {
    self.alt = alt
    self.image = image
  }
}

/// `app.bsky.embed.video#view`: the thumbnail/aspect the feed renders.
public struct EmbedVideoView: Sendable, Codable, Hashable {
  public var thumbnail: String?
  public var alt: String?
  public var aspectRatio: Aspect?

  public init(thumbnail: String? = nil, alt: String? = nil, aspectRatio: Aspect? = nil) {
    self.thumbnail = thumbnail
    self.alt = alt
    self.aspectRatio = aspectRatio
  }

  public struct Aspect: Sendable, Codable, Hashable {
    public var width: Int?
    public var height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
      self.width = width
      self.height = height
    }
  }
}

/// `app.bsky.embed.gallery` item union, restricted to the image variant.
public enum EmbedGalleryItem: Sendable, Codable, Hashable {
  case image(EmbedImage)
  case unknown(type: String)

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    switch type {
    case "app.bsky.embed.gallery#image":
      self = .image(try EmbedImage(from: decoder))
    default:
      self = .unknown(type: type)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .image(let image):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("app.bsky.embed.gallery#image", forKey: .type)
      try image.encode(to: encoder)
    case .unknown(let type):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(type, forKey: .type)
    }
  }

  public var alt: String? {
    if case .image(let image) = self { return image.alt }
    return nil
  }
}

/// An external (link-card) embed's metadata. The engine matches mute words
/// against `title + " " + description`.
public struct EmbedExternal: Sendable, Codable, Hashable {
  public var uri: String?
  public var title: String?
  public var description: String?

  public init(uri: String? = nil, title: String? = nil, description: String? = nil) {
    self.uri = uri
    self.title = title
    self.description = description
  }
}

/// The `record` field of an `app.bsky.embed.record#view`.
public enum EmbedRecordViewUnion: Sendable, Codable, Hashable {
  case viewRecord(EmbedViewRecord)
  case viewBlocked(EmbedViewBlocked)
  case viewNotFound
  case unknown(type: String)

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    switch type {
    case "app.bsky.embed.record#viewRecord":
      self = .viewRecord(try EmbedViewRecord(from: decoder))
    case "app.bsky.embed.record#viewBlocked":
      self = .viewBlocked(try EmbedViewBlocked(from: decoder))
    case "app.bsky.embed.record#viewNotFound":
      self = .viewNotFound
    default:
      self = .unknown(type: type)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .viewRecord(let value):
      try container.encode("app.bsky.embed.record#viewRecord", forKey: .type)
      try value.encode(to: encoder)
    case .viewBlocked(let value):
      try container.encode("app.bsky.embed.record#viewBlocked", forKey: .type)
      try value.encode(to: encoder)
    case .viewNotFound:
      try container.encode("app.bsky.embed.record#viewNotFound", forKey: .type)
    case .unknown(let type):
      try container.encode(type, forKey: .type)
    }
  }

  public var viewRecord: EmbedViewRecord? {
    if case .viewRecord(let value) = self { return value }
    return nil
  }

  public var viewBlocked: EmbedViewBlocked? {
    if case .viewBlocked(let value) = self { return value }
    return nil
  }
}

/// `app.bsky.embed.record#viewRecord`
public struct EmbedViewRecord: Sendable, Codable, Hashable {
  public var uri: String?
  public var cid: String?
  public var author: ProfileViewBasic?
  public var value: FeedPostRecord?
  public var labels: [Label]?
  public var indexedAt: String?
}

/// `app.bsky.embed.record#viewBlocked`
public struct EmbedViewBlocked: Sendable, Codable, Hashable {
  public var uri: String?
  public var blocked: Bool?
  public var author: ProfileViewBasic?
}

/// A raw (non-view) post embed on a post record: `app.bsky.embed.*` main types.
public indirect enum RecordEmbed: Sendable, Codable, Hashable {
  case images([EmbedImage])
  case gallery([EmbedGalleryItem])
  case external(EmbedExternal)
  case recordWithMedia(RecordWithMediaMain)
  case record(RecordMain)
  case unknown(type: String)

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    switch type {
    case "app.bsky.embed.images":
      struct Wrapper: Codable { var images: [EmbedImage] }
      self = .images(try Wrapper(from: decoder).images)
    case "app.bsky.embed.gallery":
      struct Wrapper: Codable { var items: [EmbedGalleryItem] }
      self = .gallery(try Wrapper(from: decoder).items)
    case "app.bsky.embed.external":
      struct Wrapper: Codable { var external: EmbedExternal }
      self = .external(try Wrapper(from: decoder).external)
    case "app.bsky.embed.recordWithMedia":
      self = .recordWithMedia(try RecordWithMediaMain(from: decoder))
    case "app.bsky.embed.record":
      self = .record(try RecordMain(from: decoder))
    default:
      self = .unknown(type: type)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .images(let images):
      try container.encode("app.bsky.embed.images", forKey: .type)
      struct Wrapper: Encodable { var images: [EmbedImage] }
      try Wrapper(images: images).encode(to: encoder)
    case .gallery(let items):
      try container.encode("app.bsky.embed.gallery", forKey: .type)
      struct Wrapper: Encodable { var items: [EmbedGalleryItem] }
      try Wrapper(items: items).encode(to: encoder)
    case .external(let external):
      try container.encode("app.bsky.embed.external", forKey: .type)
      struct Wrapper: Encodable { var external: EmbedExternal }
      try Wrapper(external: external).encode(to: encoder)
    case .recordWithMedia(let value):
      try container.encode("app.bsky.embed.recordWithMedia", forKey: .type)
      try value.encode(to: encoder)
    case .record(let value):
      try container.encode("app.bsky.embed.record", forKey: .type)
      try value.encode(to: encoder)
    case .unknown(let type):
      try container.encode(type, forKey: .type)
    }
  }
}

/// `app.bsky.embed.recordWithMedia` (main).
public struct RecordWithMediaMain: Sendable, Codable, Hashable {
  public var record: RecordMain?
  public var media: RecordEmbed?
}

/// `app.bsky.embed.record` (main).
public struct RecordMain: Sendable, Codable, Hashable {
  public var record: ComAtprotoRepoStrongRefLike?
}

/// `app.bsky.feed.post` as it appears in a post record. Unknown fields are
/// ignored; only the fields the engine reads are declared.
public struct FeedPostRecord: Sendable, Codable, Hashable {
  public var type: String?
  public var text: String
  public var facets: [RichTextFacet]?
  public var tags: [String]?
  public var langs: [String]?
  public var embed: RecordEmbed?

  public init(
    type: String? = "app.bsky.feed.post",
    text: String,
    facets: [RichTextFacet]? = nil,
    tags: [String]? = nil,
    langs: [String]? = nil,
    embed: RecordEmbed? = nil
  ) {
    self.type = type
    self.text = text
    self.facets = facets
    self.tags = tags
    self.langs = langs
    self.embed = embed
  }

  enum CodingKeys: String, CodingKey {
    case type = "$type"
    case text
    case facets
    case tags
    case langs
    case embed
  }
}

/// A post's hydrated embed: `app.bsky.embed.*#view` types.
public enum PostViewEmbed: Sendable, Codable, Hashable {
  case record(EmbedRecordView)
  case recordWithMedia(EmbedRecordWithMediaView)
  case external(EmbedExternal)
  case images([EmbedImage])
  case gallery([EmbedGalleryItem])
  case video(EmbedVideoView)
  case unknown(type: String)

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    switch type {
    case "app.bsky.embed.record#view":
      self = .record(try EmbedRecordView(from: decoder))
    case "app.bsky.embed.recordWithMedia#view":
      self = .recordWithMedia(try EmbedRecordWithMediaView(from: decoder))
    case "app.bsky.embed.external#view":
      struct Wrapper: Codable { var external: EmbedExternal }
      self = .external(try Wrapper(from: decoder).external)
    case "app.bsky.embed.images#view":
      struct Wrapper: Codable { var images: [EmbedImage] }
      self = .images(try Wrapper(from: decoder).images)
    case "app.bsky.embed.gallery#view":
      struct Wrapper: Codable { var items: [EmbedGalleryItem] }
      self = .gallery(try Wrapper(from: decoder).items)
    case "app.bsky.embed.video#view":
      self = .video(try EmbedVideoView(from: decoder))
    default:
      self = .unknown(type: type)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .record(let value):
      try container.encode("app.bsky.embed.record#view", forKey: .type)
      try value.encode(to: encoder)
    case .recordWithMedia(let value):
      try container.encode("app.bsky.embed.recordWithMedia#view", forKey: .type)
      try value.encode(to: encoder)
    case .external(let external):
      try container.encode("app.bsky.embed.external#view", forKey: .type)
      struct Wrapper: Encodable { var external: EmbedExternal }
      try Wrapper(external: external).encode(to: encoder)
    case .images(let images):
      try container.encode("app.bsky.embed.images#view", forKey: .type)
      struct Wrapper: Encodable { var images: [EmbedImage] }
      try Wrapper(images: images).encode(to: encoder)
    case .gallery(let items):
      try container.encode("app.bsky.embed.gallery#view", forKey: .type)
      struct Wrapper: Encodable { var items: [EmbedGalleryItem] }
      try Wrapper(items: items).encode(to: encoder)
    case .video(let video):
      try container.encode("app.bsky.embed.video#view", forKey: .type)
      try video.encode(to: encoder)
    case .unknown(let type):
      try container.encode(type, forKey: .type)
    }
  }

  public var recordView: EmbedRecordView? {
    if case .record(let value) = self { return value }
    return nil
  }
}

/// `app.bsky.embed.record#view`
public struct EmbedRecordView: Sendable, Codable, Hashable {
  public var record: EmbedRecordViewUnion?
}

/// The `media` field of an `app.bsky.embed.recordWithMedia#view`.
public enum RecordWithMediaViewMedia: Sendable, Codable, Hashable {
  case images([EmbedImage])
  case gallery([EmbedGalleryItem])
  case external(EmbedExternal)
  case video(EmbedVideoView)
  case unknown(type: String)

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    switch type {
    case "app.bsky.embed.images#view":
      struct Wrapper: Codable { var images: [EmbedImage] }
      self = .images(try Wrapper(from: decoder).images)
    case "app.bsky.embed.gallery#view":
      struct Wrapper: Codable { var items: [EmbedGalleryItem] }
      self = .gallery(try Wrapper(from: decoder).items)
    case "app.bsky.embed.external#view":
      struct Wrapper: Codable { var external: EmbedExternal }
      self = .external(try Wrapper(from: decoder).external)
    case "app.bsky.embed.video#view":
      self = .video(try EmbedVideoView(from: decoder))
    default:
      self = .unknown(type: type)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .images(let images):
      try container.encode("app.bsky.embed.images#view", forKey: .type)
      struct Wrapper: Encodable { var images: [EmbedImage] }
      try Wrapper(images: images).encode(to: encoder)
    case .gallery(let items):
      try container.encode("app.bsky.embed.gallery#view", forKey: .type)
      struct Wrapper: Encodable { var items: [EmbedGalleryItem] }
      try Wrapper(items: items).encode(to: encoder)
    case .external(let external):
      try container.encode("app.bsky.embed.external#view", forKey: .type)
      struct Wrapper: Encodable { var external: EmbedExternal }
      try Wrapper(external: external).encode(to: encoder)
    case .video(let video):
      try container.encode("app.bsky.embed.video#view", forKey: .type)
      try video.encode(to: encoder)
    case .unknown(let type):
      try container.encode(type, forKey: .type)
    }
  }
}

/// `app.bsky.embed.recordWithMedia#view`
public struct EmbedRecordWithMediaView: Sendable, Codable, Hashable {
  public var record: EmbedRecordView?
  public var media: RecordWithMediaViewMedia?
}
