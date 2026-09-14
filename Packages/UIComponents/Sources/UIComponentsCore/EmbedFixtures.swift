import Foundation
import Moderation

/// Builders for hydrated embed values.
///
/// The engine's embed view types (`EmbedRecordView`, `EmbedRecordWithMediaView`,
/// `EmbedViewRecord`, `EmbedViewBlocked`) are `Codable` but expose no public
/// memberwise initializer, because the engine only ever decodes them. Fixtures
/// - the gallery and the tests - still need to build them, so this decodes the
/// same JSON the API sends. That has the side benefit of exercising the real
/// decode path rather than a shortcut constructor.
public enum EmbedFixtures {
  /// Decodes a hydrated embed from its wire JSON. Returns nil on malformed input.
  public static func embed(json: String) -> PostViewEmbed? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(PostViewEmbed.self, from: data)
  }

  /// A quoted post: `app.bsky.embed.record#view` wrapping a `viewRecord`.
  public static func quote(
    text: String,
    authorDid: String = "did:plc:quote",
    authorHandle: String = "bob.bsky.social",
    authorDisplayName: String = "Bob",
    uri: String = "at://did:plc:quote/app.bsky.feed.post/1"
  ) -> PostViewEmbed? {
    embed(
      json: """
        {
          "$type": "app.bsky.embed.record#view",
          "record": {
            "$type": "app.bsky.embed.record#viewRecord",
            "uri": "\(uri)",
            "author": {
              "$type": "app.bsky.actor.defs#profileViewBasic",
              "did": "\(authorDid)",
              "handle": "\(authorHandle)",
              "displayName": "\(authorDisplayName)"
            },
            "value": {"$type": "app.bsky.feed.post", "text": "\(escape(text))"}
          }
        }
        """)
  }

  /// A blocked quote: `app.bsky.embed.record#view` wrapping a `viewBlocked`.
  public static func blockedQuote(uri: String = "at://blocked") -> PostViewEmbed? {
    embed(
      json: """
        {
          "$type": "app.bsky.embed.record#view",
          "record": {
            "$type": "app.bsky.embed.record#viewBlocked",
            "uri": "\(uri)",
            "blocked": true
          }
        }
        """)
  }

  /// A not-found quote, which renders the "not available" body.
  public static func notFoundQuote() -> PostViewEmbed? {
    embed(
      json: """
        {
          "$type": "app.bsky.embed.record#view",
          "record": {"$type": "app.bsky.embed.record#viewNotFound", "uri": "at://gone"}
        }
        """)
  }

  /// A quoted post with an images embed: `recordWithMedia#view`.
  public static func recordWithMedia(
    imageCount: Int = 1,
    text: String = "Quoted post with media."
  ) -> PostViewEmbed? {
    let images = (0..<imageCount)
      .map { #"{"alt": "media \#($0)", "image": "https://cdn.example/\#($0).jpg"}"# }
      .joined(separator: ",")
    return embed(
      json: """
        {
          "$type": "app.bsky.embed.recordWithMedia#view",
          "record": {
            "$type": "app.bsky.embed.record#view",
            "record": {
              "$type": "app.bsky.embed.record#viewRecord",
              "uri": "at://did:plc:quote/app.bsky.feed.post/2",
              "author": {
                "$type": "app.bsky.actor.defs#profileViewBasic",
                "did": "did:plc:carol",
                "handle": "carol.bsky.social",
                "displayName": "Carol"
              },
              "value": {"$type": "app.bsky.feed.post", "text": "\(escape(text))"}
            }
          },
          "media": {
            "$type": "app.bsky.embed.images#view",
            "images": [\(images)]
          }
        }
        """)
  }

  /// An images embed with placeholder URLs, so the gallery shows real geometry.
  public static func images(_ count: Int) -> [EmbedImage] {
    (0..<count).map { index in
      EmbedImage(alt: "Image \(index + 1)", image: "https://cdn.example/\(index).jpg")
    }
  }

  /// Escapes the characters that would break the JSON string literals above.
  static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
  }
}
