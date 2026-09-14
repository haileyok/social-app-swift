import Testing
import Foundation
@testable import Lexicons

/// AC.2 verification: generated types decode `app.bsky.feed.getTimeline`
/// output fixtures, including unknown `$type` union members, without crashing.
@Suite struct GetTimelineDecodeTests {

  /// Minimal getTimeline response: one post, no embed, known union member on record.
  @Test func decodesBasicTimelinePost() throws {
    let json = """
    {
      "cursor": "abc",
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:abcdef/app.bsky.feed.post/3k2f7r",
            "cid": "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdbejg4lf4hwbpf3cli",
            "author": {
              "did": "did:plc:abcdef",
              "handle": "alice.example",
              "displayName": "Alice"
            },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "Hello world",
              "createdAt": "2026-01-01T00:00:00Z"
            },
            "indexedAt": "2026-01-01T00:00:00Z"
          }
        }
      ]
    }
    """
    let data = Data(json.utf8)
    let output = try JSONDecoder().decode(App.Bsky.FeedGetTimeline_Output.self, from: data)
    #expect(output.cursor == "abc")
    #expect(output.feed.count == 1)
    let post = try #require(output.feed.first?.post)
    #expect(post.record.type == "app.bsky.feed.post")
    #expect(post.author.handle.rawValue == "alice.example")
  }

  /// Unknown embed `$type` (a hypothetical future embed) must decode into the
  /// open-union fallback case, not throw.
  @Test func decodesUnknownEmbedTypeWithoutCrashing() throws {
    let json = """
    {
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:abcdef/app.bsky.feed.post/3k2f7r",
            "cid": "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdbejg4lf4hwbpf3cli",
            "author": {
              "did": "did:plc:abcdef",
              "handle": "alice.example"
            },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "Future embed",
              "createdAt": "2026-01-01T00:00:00Z"
            },
            "embed": {
              "$type": "app.bsky.embed.someFutureThing#view",
              "anything": ["goes", "here"],
              "nested": {"x": 1}
            },
            "indexedAt": "2026-01-01T00:00:00Z"
          }
        }
      ]
    }
    """
    let data = Data(json.utf8)
    let output = try JSONDecoder().decode(App.Bsky.FeedGetTimeline_Output.self, from: data)
    let post = try #require(output.feed.first?.post)
    #expect(post.embed != nil)
  }

  /// Known embed union member decodes to the typed case.
  @Test func decodesKnownImagesEmbed() throws {
    let json = """
    {
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:abcdef/app.bsky.feed.post/3k2f7r",
            "cid": "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdbejg4lf4hwbpf3cli",
            "author": {
              "did": "did:plc:abcdef",
              "handle": "alice.example"
            },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "pic",
              "createdAt": "2026-01-01T00:00:00Z"
            },
            "embed": {
              "$type": "app.bsky.embed.images#view",
              "images": [
                {
                  "thumb": "https://example.com/thumb.jpg",
                  "fullsize": "https://example.com/full.jpg",
                  "alt": "a test image"
                }
              ]
            },
            "indexedAt": "2026-01-01T00:00:00Z"
          }
        }
      ]
    }
    """
    let data = Data(json.utf8)
    let output = try JSONDecoder().decode(App.Bsky.FeedGetTimeline_Output.self, from: data)
    let post = try #require(output.feed.first?.post)
    guard case .embedImagesView(let images) = post.embed else {
      Issue.record("expected images view embed, got \(String(describing: post.embed))")
      return
    }
    #expect(images.images.count == 1)
    #expect(images.images.first?.alt == "a test image")
  }
}
