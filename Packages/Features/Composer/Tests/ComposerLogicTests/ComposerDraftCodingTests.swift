import Foundation
import Lexicons
import RichText
import SwiftAtproto
import Testing

@testable import ComposerLogic

/// Draft <-> composer conversion: serialization, hydration and summaries.
///
/// Ported from `drafts/state/api.ts`.
@Suite("ComposerDraftCoding")
struct ComposerDraftCodingTests {

  // MARK: - Conversion

  @Test("images are always serialized to embedGallery, even below the legacy cap")
  func imagesAlwaysGallery() {
    let images = (1...2).map {
      ComposerImage(id: "i\($0)", path: "/img\($0).jpg", width: 10, height: 10, alt: "n\($0)")
    }
    let post = Fixtures.post(id: "p0", text: "pics", embed: EmbedDraft(media: .images(.images(images))))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D", idGenerator: { "ref" })
    let draftPost = conversion.draft.posts[0]
    #expect(draftPost.embedImages == nil)
    let items = draftPost.embedGallery?.items
    #expect(items?.count == 2)
    guard case .draftDefsDraftEmbedImage(let first) = items?.first else {
      Issue.record("expected a draftEmbedImage item")
      return
    }
    #expect(first.alt == "n1")
    #expect(first.localRef.path == "image:ref")
    #expect(conversion.localRefPaths.count == 2)
  }

  @Test("a link card is not persisted when media owns the embed slot")
  func linkCardDroppedWithMedia() {
    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10)]
    let post = Fixtures.post(
      id: "p0", text: "x",
      embed: EmbedDraft(
        media: .images(.images(images)),
        link: ExternalLink(uri: "https://example.com/story")))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D", idGenerator: { "ref" })
    #expect(conversion.draft.posts[0].embedExternals == nil)
  }

  @Test("a link card with no media is persisted as an external embed")
  func linkCardPersisted() {
    let post = Fixtures.post(
      id: "p0", text: "read",
      embed: EmbedDraft(link: ExternalLink(uri: "https://example.com/story")))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D")
    #expect(conversion.draft.posts[0].embedExternals?.first?.uri.rawValue == "https://example.com/story")
  }

  @Test("a quote is persisted only when it resolves to a strong ref")
  func quotePersistedWhenResolved() {
    let post = Fixtures.post(
      id: "p0", text: "quote",
      embed: EmbedDraft(quote: QuoteLink(uri: "https://bsky.app/profile/a.test/post/b")))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D",
      resolveQuote: { _ in RecordReference(uri: "at://did:plc:a/app.bsky.feed.post/b", cid: "bafy") })
    #expect(
      conversion.draft.posts[0].embedRecords?.first?.record.uri.rawValue
        == "at://did:plc:a/app.bsky.feed.post/b")
  }

  @Test("labels are persisted as selfLabels")
  func labelsPersisted() {
    let post = Fixtures.post(id: "p0", text: "x", labels: SelfLabelSet(values: ["sexual"]))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D")
    guard case .comAtprotoLabelDefsSelfLabels(let labels)? = conversion.draft.posts[0].labels else {
      Issue.record("expected selfLabels")
      return
    }
    #expect(labels.values.map(\.val) == ["sexual"])
  }

  @Test("threadgate and postgate settings are persisted")
  func gatesPersisted() {
    let post = Fixtures.post(id: "p0", text: "x")
    let thread = Fixtures.thread(
      posts: [post], threadgate: [.followers], embeddingRules: [ComposerGates.disableRule])
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(thread), deviceId: "d", deviceName: "D")
    #expect(conversion.draft.threadgateAllow?.count == 1)
    #expect(conversion.draft.postgateEmbeddingRules?.count == 1)
  }

  @Test("a video with no compressed file is not persisted")
  func uncompressedVideoNotPersisted() {
    let video = ComposerVideo.created(asset: ComposerVideoAsset(
      uri: "file:///v.mp4", size: 1000, width: 100, height: 100))
    let post = Fixtures.post(id: "p0", text: "v", embed: EmbedDraft(media: .video(video)))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D")
    #expect(conversion.draft.posts[0].embedVideos == nil)
  }

  @Test("a compressed video's mime type is encoded into its localRef path")
  func videoMimeTypeInPath() {
    var video = ComposerVideo.created(asset: ComposerVideoAsset(
      uri: "file:///v.mp4", size: 1000, width: 100, height: 100))
    video = VideoReducer.reduce(
      video,
      .compressingToUploading(
        video: CompressedVideo(uri: "file:///out.webm", mimeType: "video/webm", size: 500),
        compressionSkipped: false, token: video.token))
    let post = Fixtures.post(id: "p0", text: "v", embed: EmbedDraft(media: .video(video)))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D", idGenerator: { "vid" })
    let path = conversion.draft.posts[0].embedVideos?.first?.localRef.path
    #expect(path == "video:video/webm:vid.webm")
    #expect(ComposerDraftCoding.parseVideoMimeType(path!) == "video/webm")
  }

  @Test("the legacy video localRef format defaults to mp4")
  func legacyVideoLocalRef() {
    #expect(ComposerDraftCoding.parseVideoMimeType("video:abc123") == "video/mp4")
    #expect(ComposerDraftCoding.parseVideoMimeType("video:video/mp4:abc.mp4") == "video/mp4")
  }

  // MARK: - Hydration

  @Test("hydrating restores text, facets and images")
  func hydrateTextAndImages() {
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        embedGallery: App.Bsky.DraftDefs_DraftEmbedGallery(items: [
          .draftDefsDraftEmbedImage(
            App.Bsky.DraftDefs_DraftEmbedImage(
              alt: "a cat",
              localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:a")))
        ]),
        text: "hello https://example.com"
      )
    ])
    let hydration = ComposerDraftCoding.hydrate(
      draft: draft,
      loadedMedia: ["image:a": "/local/a.jpg"],
      imageIdGenerator: { "i1" },
      imageDimensions: { _ in (width: 800, height: 600) })
    #expect(hydration.posts.count == 1)
    #expect(hydration.posts[0].richText.text == "hello https://example.com")
    #expect(hydration.posts[0].richText.hasFacets)
    let images = hydration.posts[0].embed.media?.images
    #expect(images?.count == 1)
    #expect(images?.first?.alt == "a cat")
    #expect(images?.first?.path == "/local/a.jpg")
    #expect(images?.first?.localRefPath == "image:a")
  }

  @Test("hydration re-picks the variant from the restored image count")
  func hydrateRepicksVariant() {
    // A draft saved in the legacy embedImages slot with 5 items - which the RN
    // comment calls out as a case that would otherwise restore broken.
    let images = (1...5).map { index in
      App.Bsky.DraftDefs_DraftEmbedImage(
        localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:\(index)"))
    }
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(embedImages: images,
        text: "pics"
      )
    ])
    let hydration = ComposerDraftCoding.hydrate(
      draft: draft,
      loadedMedia: Dictionary(uniqueKeysWithValues: (1...5).map { ("image:\($0)", "/l/\($0).jpg") }))
    guard case .images(.gallery(let restored)) = hydration.posts[0].embed.media else {
      Issue.record("expected the gallery variant for five restored images")
      return
    }
    #expect(restored.count == 5)
  }

  @Test("media missing from local storage is dropped")
  func hydrateDropsMissingMedia() {
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        embedGallery: App.Bsky.DraftDefs_DraftEmbedGallery(items: [
          .draftDefsDraftEmbedImage(
            App.Bsky.DraftDefs_DraftEmbedImage(
              localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:gone")))
        ]),
        text: "x"
      )
    ])
    let hydration = ComposerDraftCoding.hydrate(draft: draft, loadedMedia: [:])
    #expect(hydration.posts[0].embed.media == nil)
  }

  @Test("a draft video is handed back for re-processing")
  func hydrateVideoForReprocessing() {
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        embedVideos: [
          App.Bsky.DraftDefs_DraftEmbedVideo(
            alt: "a clip",
            captions: [
              App.Bsky.DraftDefs_DraftEmbedCaption(
                content: "WEBVTT", lang: FormatString<Language>(rawValue: "en"))
            ],
            localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "video:video/webm:abc.webm"))
        ],
        text: "v"
      )
    ])
    let hydration = ComposerDraftCoding.hydrate(
      draft: draft, loadedMedia: ["video:video/webm:abc.webm": "/local/v.webm"])
    let restored = hydration.restoredVideos[0]
    #expect(restored?.uri == "/local/v.webm")
    #expect(restored?.altText == "a clip")
    #expect(restored?.mimeType == "video/webm")
    #expect(restored?.captions.first?.content == "WEBVTT")
    #expect(restored?.captions.first?.lang == "en")
  }

  @Test("a quote is restored as an app URL")
  func hydrateQuote() {
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        embedRecords: [
          App.Bsky.DraftDefs_DraftEmbedRecord(
            record: Com.Atproto.RepoStrongRef(
              cid: FormatString<LexLink>(rawValue: "bafy"),
              uri: FormatString<ATURI>(rawValue: "at://did:plc:a/app.bsky.feed.post/b")))
        ],
        text: "q"
      )
    ])
    let hydration = ComposerDraftCoding.hydrate(draft: draft, loadedMedia: [:])
    #expect(hydration.posts[0].embed.quote?.uri == "https://bsky.app/profile/did:plc:a/post/b")
  }

  @Test("labels are restored from the draft")
  func hydrateLabels() {
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        labels: .comAtprotoLabelDefsSelfLabels(
          Com.Atproto.LabelDefs_SelfLabels(values: [
            Com.Atproto.LabelDefs_SelfLabel(val: "sexual"),
            Com.Atproto.LabelDefs_SelfLabel(val: "graphic-media"),
          ])),
        text: "x"
      )
    ])
    let hydration = ComposerDraftCoding.hydrate(draft: draft, loadedMedia: [:])
    #expect(hydration.posts[0].labels.values == ["sexual", "graphic-media"])
  }

  @Test("the localRefs set gathers every media path in a draft")
  func localRefSet() {
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        embedGallery: App.Bsky.DraftDefs_DraftEmbedGallery(items: [
          .draftDefsDraftEmbedImage(
            App.Bsky.DraftDefs_DraftEmbedImage(
              localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:a")))
        ]),
        text: "a"
      ),
      App.Bsky.DraftDefs_DraftPost(
        embedVideos: [
          App.Bsky.DraftDefs_DraftEmbedVideo(
            localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "video:video/mp4:b.mp4"))
        ],
        text: "b"
      ),
    ])
    #expect(ComposerDraftCoding.localRefs(in: draft) == ["image:a", "video:video/mp4:b.mp4"])
  }

  // MARK: - GIF round-trip

  @Test("a GIF round-trips through the draft URL encoding")
  func gifRoundTrip() {
    let gif = GifMedia(
      gif: ComposerGif(url: "https://media.tenor.com/abc/x.gif", width: 320, height: 240),
      alt: "a dancing cat")
    let post = Fixtures.post(id: "p0", text: "gif", embed: EmbedDraft(media: .gif(gif)))
    let conversion = ComposerDraftCoding.draft(
      from: Fixtures.state(Fixtures.thread(posts: [post])),
      deviceId: "d", deviceName: "D")
    let uri = conversion.draft.posts[0].embedExternals?.first?.uri.rawValue
    #expect(uri?.contains("ww=320") == true)
    #expect(uri?.contains("hh=240") == true)
    #expect(uri?.contains("alt=a%20dancing%20cat") == true)

    let hydration = ComposerDraftCoding.hydrate(draft: conversion.draft, loadedMedia: [:])
    guard case .gif(let restored)? = hydration.posts[0].embed.media else {
      Issue.record("expected the GIF to restore")
      return
    }
    #expect(restored.gif.width == 320)
    #expect(restored.gif.height == 240)
    #expect(restored.alt == "a dancing cat")
    // The composer's params are stripped so a re-serialize does not double them.
    #expect(!restored.gif.url.contains("ww="))
  }

  @Test("a non-GIF-host external URL is not parsed as a GIF")
  func nonGifHostNotParsed() {
    #expect(ComposerDraftCoding.parseGifFromUrl("https://example.com/a.gif?ww=1&hh=1") == nil)
  }

  @Test("a GIF URL without dimensions is not parsed")
  func gifWithoutDimsNotParsed() {
    #expect(ComposerDraftCoding.parseGifFromUrl("https://media.tenor.com/a.gif") == nil)
  }

  // MARK: - Summaries

  @Test("a summary reports media counts and missing files")
  func summaryCounts() {
    let service = FakeDraftsService()
    let storage = FakeDraftMediaStorage(existing: ["image:a"])
    let drafts = ComposerDrafts(service: service, deviceId: "device-1", storage: storage)
    let draft = App.Bsky.DraftDefs_Draft(
      deviceId: "device-1",
      posts: [
        App.Bsky.DraftDefs_DraftPost(
          embedGallery: App.Bsky.DraftDefs_DraftEmbedGallery(items: [
            .draftDefsDraftEmbedImage(
              App.Bsky.DraftDefs_DraftEmbedImage(
                alt: "here",
                localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:a"))),
            .draftDefsDraftEmbedImage(
              App.Bsky.DraftDefs_DraftEmbedImage(
                localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:gone"))),
          ]),
        text: "one"
      ),
        App.Bsky.DraftDefs_DraftPost(
          embedRecords: [
            App.Bsky.DraftDefs_DraftEmbedRecord(
              record: Com.Atproto.RepoStrongRef(
                cid: FormatString<LexLink>(rawValue: "bafy"),
                uri: FormatString<ATURI>(rawValue: "at://did:plc:a/app.bsky.feed.post/b")))
          ],
        text: "two"
      ),
      ])
    let summary = drafts.summarise(
      id: "draft-1", createdAt: "c", updatedAt: "u", draft: draft)
    #expect(summary.meta.postCount == 2)
    #expect(summary.meta.replyCount == 1)
    #expect(summary.meta.mediaCount == 2)
    #expect(summary.meta.hasMedia)
    #expect(summary.meta.hasMissingMedia)
    #expect(summary.meta.hasQuotes)
    #expect(summary.meta.quoteCount == 1)
    #expect(summary.meta.isOriginatingDevice)
    #expect(summary.posts[0].images?[0].exists == true)
    #expect(summary.posts[0].images?[1].exists == false)
  }

  @Test("a draft from another device is flagged")
  func summaryOtherDevice() {
    let service = FakeDraftsService()
    let drafts = ComposerDrafts(service: service, deviceId: "device-1")
    let draft = App.Bsky.DraftDefs_Draft(deviceId: "device-2", posts: [
      App.Bsky.DraftDefs_DraftPost(
        text: "x"
      )
    ])
    let summary = drafts.summarise(id: "d", createdAt: "c", updatedAt: "u", draft: draft)
    #expect(!summary.meta.isOriginatingDevice)
  }
}
