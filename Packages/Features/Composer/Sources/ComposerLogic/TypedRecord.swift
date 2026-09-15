import Foundation
import Lexicons
import SwiftAtproto

/// A record wrapper that writes an explicit `$type` alongside the record's own
/// fields.
///
/// The generated lexicon structs expose `type` as a computed property and do
/// **not** encode it from their synthesized `encode(to:)`: their `CodingKeys`
/// declare `case type = "$type"` for *decoding* only, and the `encode` method
/// never writes it. Verified against
/// `App.Bsky.FeedPost.encode(to:)` in the generated ``Lexicons`` source. This
/// workspace has no client-repo serializer that adds it (upstream swift-atproto
/// fills `$type` in through a separate record-writing path that is not wired up
/// here), so the composer must add it itself.
///
/// Writing it matters for two reasons:
///
/// 1. The PDS validates `$type` and stores it in the record; other clients
///    dispatch on it.
/// 2. The record's CID is computed over its DAG-CBOR form **including**
///    `$type`; omitting it yields a CID that does not match the stored record.
///    The RN source calls this out explicitly ("IMPORTANT: $type has to exist,
///    CID is calculated with the `$type` field present and will produce the
///    wrong CID if you omit it").
///
/// The wrapper's own `type` field is `$type`'s value, so the key is emitted
/// exactly once.
public struct TypedRecord<Record: Encodable & Sendable>: Encodable, Sendable {
  /// The record NSID, written as `$type`.
  public let type: String
  /// The record itself.
  public let record: Record

  public init(_ record: Record, type: String) {
    self.record = record
    self.type = type
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AnyCodingKeys.self)
    try container.encode(type, forKey: AnyCodingKeys(stringValue: "$type"))
    try record.encode(to: encoder)
  }
}

extension App.Bsky.FeedPost {
  /// This record with its `$type` included, ready to be written to a repo.
  public var typed: TypedRecord<App.Bsky.FeedPost> { .post(self) }
}

extension App.Bsky.FeedThreadgate {
  /// This record with its `$type` included.
  public var typed: TypedRecord<App.Bsky.FeedThreadgate> { .threadgate(self) }
}

extension App.Bsky.FeedPostgate {
  /// This record with its `$type` included.
  public var typed: TypedRecord<App.Bsky.FeedPostgate> { .postgate(self) }
}

extension TypedRecord where Record == App.Bsky.FeedPost {
  /// A post record with its `$type`.
  public static func post(_ record: App.Bsky.FeedPost) -> TypedRecord {
    TypedRecord(record, type: App.Bsky.FeedPost.nsId)
  }
}

extension TypedRecord where Record == App.Bsky.FeedThreadgate {
  /// A threadgate record with its `$type`.
  public static func threadgate(_ record: App.Bsky.FeedThreadgate) -> TypedRecord {
    TypedRecord(record, type: App.Bsky.FeedThreadgate.nsId)
  }
}

extension TypedRecord where Record == App.Bsky.FeedPostgate {
  /// A postgate record with its `$type`.
  public static func postgate(_ record: App.Bsky.FeedPostgate) -> TypedRecord {
    TypedRecord(record, type: App.Bsky.FeedPostgate.nsId)
  }
}
