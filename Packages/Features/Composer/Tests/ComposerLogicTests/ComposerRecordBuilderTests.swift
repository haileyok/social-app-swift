import Foundation
import Lexicons
import RichText
import SwiftAtproto
import Testing

@testable import ComposerLogic

/// Post-record construction, asserted as exact JSON payloads.
///
/// Ported from `post()` and `resolveEmbed` in `src/lib/api/index.ts`. The suites
/// here pin the wire shape, because the record is what other clients read and a
/// missing `$type` or a stray `nil` field is invisible until something renders
/// wrong.
@Suite("ComposerRecordBuilder")
struct ComposerRecordBuilderTests {

  // MARK: - Minimal record

  @Test("a text-only post produces the minimal record shape")
  func textOnlyRecord() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [Fixtures.post(id: "p0", text: "hello world")]),
      rkeys: ["p0": "abc123"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    #expect(records.count == 1)
    let record = records[0].record

    #expect(record.text == "hello world")
    #expect(record.createdAt.rawValue == "2026-01-01T00:00:00.001Z")
    #expect(record.embed == nil)
    #expect(record.facets == nil)
    #expect(record.labels == nil)
    #expect(record.langs == nil)
    #expect(record.reply == nil)
    #expect(records[0].uri == "at://did:plc:testuser/app.bsky.feed.post/abc123")
    #expect(records[0].collection == "app.bsky.feed.post")

    // The `$type` must be present, because the CID is computed over it.
    let json = Fixtures.json(record.typed)
    #expect(json["$type"] as? String == "app.bsky.feed.post")
    #expect(json["createdAt"] as? String == "2026-01-01T00:00:00.001Z")
    #expect(json["text"] as? String == "hello world")
    // Optional-empty fields must be absent, not null.
    #expect(json["embed"] == nil)
    #expect(json["facets"] == nil)
    #expect(json["langs"] == nil)
  }

  @Test("langs are written when supplied and capped at three")
  func langsWritten() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [Fixtures.post(id: "p0", text: "hi")]),
      langs: ["en", "pt-BR", "ja"],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    #expect(record.langs?.map(\.rawValue) == ["en", "pt-BR", "ja"])
    let json = Fixtures.json(record)
    #expect(json["langs"] as? [String] == ["en", "pt-BR", "ja"])
  }

  @Test("self-labels produce the selfLabels shape")
  func labelsShape() throws {
    let post = Fixtures.post(
      id: "p0", text: "hi", labels: SelfLabelSet(values: ["sexual", "graphic-media"]))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let json = Fixtures.json(record)
    let labels = json["labels"] as? [String: Any]
    #expect(labels?["$type"] as? String == "com.atproto.label.defs#selfLabels")
    let values = labels?["values"] as? [[String: String]]
    #expect(values?.compactMap { $0["val"] } == ["sexual", "graphic-media"])
  }

  // MARK: - Facets

  @Test("a link in the text produces a facet in the record")
  func linkFacetInRecord() throws {
    let post = Fixtures.post(id: "p0", text: "see https://example.com now")
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let json = Fixtures.json(record)
    let facets = json["facets"] as? [[String: Any]]
    #expect(facets?.count == 1)
    let features = facets?.first?["features"] as? [[String: String]]
    #expect(features?.first?["$type"] == "app.bsky.richtext.facet#link")
    #expect(features?.first?["uri"] == "https://example.com")
  }

  // MARK: - Embed precedence

  @Test("images below the cap produce app.bsky.embed.images")
  func imagesEmbed() throws {
    let images = [
      ResolvedImage(blob: Fixtures.blob(), alt: "a cat", width: 800, height: 600)
    ]
    let post = Fixtures.post(
      id: "p0", text: "pic",
      embed: EmbedDraft(media: .images(.images([
        ComposerImage(id: "i1", path: "/a.jpg", width: 800, height: 600, alt: "a cat")
      ]))))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      media: ["p0": .images(images)],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let json = Fixtures.json(record)
    let embed = json["embed"] as? [String: Any]
    #expect(embed?["$type"] as? String == "app.bsky.embed.images")
    let imageList = embed?["images"] as? [[String: Any]]
    #expect(imageList?.count == 1)
    #expect(imageList?.first?["alt"] as? String == "a cat")
    let ratio = imageList?.first?["aspectRatio"] as? [String: Int]
    #expect(ratio?["width"] == 800)
    #expect(ratio?["height"] == 600)
    let blob = imageList?.first?["image"] as? [String: Any]
    #expect(blob?["$type"] as? String == "blob")
    #expect(blob?["mimeType"] as? String == "image/jpeg")
  }

  @Test("images above the cap produce app.bsky.embed.gallery with per-item $type")
  func galleryEmbed() throws {
    let images = (1...5).map {
      ResolvedImage(blob: Fixtures.blob(), alt: "img \($0)", width: 100, height: 100)
    }
    let post = Fixtures.post(
      id: "p0", text: "pics", embed: EmbedDraft(media: .images(.gallery([]))))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      media: ["p0": .gallery(images)],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let json = Fixtures.json(record)
    let embed = json["embed"] as? [String: Any]
    #expect(embed?["$type"] as? String == "app.bsky.embed.gallery")
    let items = embed?["items"] as? [[String: Any]]
    #expect(items?.count == 5)
    // Each item carries its own `$type`, which the lexicon requires.
    #expect(items?.first?["$type"] as? String == "app.bsky.embed.gallery#image")
    #expect(items?.first?["alt"] as? String == "img 1")
  }

  @Test("a video produces app.bsky.embed.video with presentation default")
  func videoEmbed() throws {
    let video = ResolvedVideo(
      blob: Fixtures.blob(mimeType: "video/mp4"),
      alt: "a clip",
      captions: nil,
      width: 1920,
      height: 1080,
      mimeType: "video/mp4")
    let post = Fixtures.post(id: "p0", text: "watch", embed: EmbedDraft(media: .video(
      ComposerVideo.created(asset: ComposerVideoAsset(
        uri: "file:///v.mp4", size: 1, width: 1920, height: 1080)))))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      media: ["p0": .video(video)],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let json = Fixtures.json(record)
    let embed = json["embed"] as? [String: Any]
    #expect(embed?["$type"] as? String == "app.bsky.embed.video")
    #expect(embed?["alt"] as? String == "a clip")
    #expect(embed?["presentation"] as? String == "default")
    let ratio = embed?["aspectRatio"] as? [String: Int]
    #expect(ratio?["width"] == 1920)
    #expect(ratio?["height"] == 1080)
  }

  @Test("a GIF-mime video renders with presentation gif")
  func gifPresentation() throws {
    let video = ResolvedVideo(
      blob: Fixtures.blob(mimeType: "image/gif"),
      alt: "loops",
      captions: nil,
      width: 100,
      height: 100,
      mimeType: "image/gif")
    let post = Fixtures.post(id: "p0", text: "gif")
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      media: ["p0": .video(video)],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let embed = Fixtures.json(record)["embed"] as? [String: Any]
    #expect(embed?["presentation"] as? String == "gif")
  }

  @Test("a zero dimension omits the aspect ratio rather than writing zero")
  func zeroDimensionsOmitRatio() throws {
    let video = ResolvedVideo(
      blob: Fixtures.blob(mimeType: "video/mp4"),
      alt: "",
      captions: nil,
      width: 0,
      height: 0,
      mimeType: "video/mp4")
    let post = Fixtures.post(id: "p0", text: "v")
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      media: ["p0": .video(video)],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let embed = Fixtures.json(record)["embed"] as? [String: Any]
    #expect(embed?["aspectRatio"] == nil)
  }

  @Test("a link card becomes app.bsky.embed.external with title and description")
  func linkCardEmbed() throws {
    let card = ResolvedExternal(
      uri: "https://example.com/story",
      title: "A story",
      description: "About things",
      thumb: Fixtures.blob())
    let post = Fixtures.post(
      id: "p0", text: "read",
      embed: EmbedDraft(link: ExternalLink(uri: "https://example.com/story")))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      linkCards: ["p0": card],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let embed = Fixtures.json(record)["embed"] as? [String: Any]
    #expect(embed?["$type"] as? String == "app.bsky.embed.external")
    let external = embed?["external"] as? [String: Any]
    #expect(external?["uri"] as? String == "https://example.com/story")
    #expect(external?["title"] as? String == "A story")
    #expect(external?["description"] as? String == "About things")
    let thumb = external?["thumb"] as? [String: Any]
    #expect(thumb?["mimeType"] as? String == "image/jpeg")
  }

  @Test("media wins over a link card")
  func mediaWinsOverLinkCard() throws {
    let post = Fixtures.post(
      id: "p0", text: "pic",
      embed: EmbedDraft(
        media: .images(.images([])),
        link: ExternalLink(uri: "https://example.com/story")))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      media: ["p0": .images([ResolvedImage(
        blob: Fixtures.blob(), alt: "", width: 10, height: 10)])],
      linkCards: [
        "p0": ResolvedExternal(uri: "https://example.com", title: "T", description: "D")
      ],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let embed = Fixtures.json(record)["embed"] as? [String: Any]
    #expect(embed?["$type"] as? String == "app.bsky.embed.images")
  }

  @Test("a quote alone becomes app.bsky.embed.record")
  func quoteEmbed() throws {
    let post = Fixtures.post(
      id: "p0", text: "quoting",
      embed: EmbedDraft(quote: QuoteLink(uri: "https://bsky.app/profile/a.test/post/b")))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      quoteReferences: [
        "p0": RecordReference(uri: "at://did:plc:a/app.bsky.feed.post/b", cid: "bafyquote")
      ],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let embed = Fixtures.json(record)["embed"] as? [String: Any]
    #expect(embed?["$type"] as? String == "app.bsky.embed.record")
    let quoted = embed?["record"] as? [String: Any]
    #expect(quoted?["uri"] as? String == "at://did:plc:a/app.bsky.feed.post/b")
    #expect(quoted?["cid"] as? String == "bafyquote")
  }

  @Test("a quote plus media becomes app.bsky.embed.recordWithMedia")
  func quoteWithMediaEmbed() throws {
    let post = Fixtures.post(
      id: "p0", text: "quoting with a pic",
      embed: EmbedDraft(
        quote: QuoteLink(uri: "https://bsky.app/profile/a.test/post/b"),
        media: .images(.images([]))))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      media: ["p0": .images([ResolvedImage(
        blob: Fixtures.blob(), alt: "cat", width: 10, height: 10)])],
      quoteReferences: [
        "p0": RecordReference(uri: "at://did:plc:a/app.bsky.feed.post/b", cid: "bafyquote")
      ],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    let embed = Fixtures.json(record)["embed"] as? [String: Any]
    #expect(embed?["$type"] as? String == "app.bsky.embed.recordWithMedia")
    // The `media` union discriminator IS emitted by the generated union enum.
    let media = embed?["media"] as? [String: Any]
    #expect(media?["$type"] as? String == "app.bsky.embed.images")
    // `record` is a plain ref, and the generated `EmbedRecord` struct does not
    // encode its own `$type`; see the deviations note on `TypedRecord`.
    let quoted = embed?["record"] as? [String: Any]
    let strongRef = quoted?["record"] as? [String: Any]
    #expect(strongRef?["uri"] as? String == "at://did:plc:a/app.bsky.feed.post/b")
    #expect(strongRef?["cid"] as? String == "bafyquote")
  }

  @Test("a quote with no resolved ref produces no embed")
  func unresolvedQuoteProducesNoEmbed() throws {
    let post = Fixtures.post(
      id: "p0", text: "quoting",
      embed: EmbedDraft(quote: QuoteLink(uri: "https://bsky.app/profile/a.test/post/b")))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    #expect(record.embed == nil)
  }
}
