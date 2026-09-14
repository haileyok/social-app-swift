import Foundation
import Lexicons
import Moderation
import SwiftAtproto
import Testing

@testable import VideoFeedLogic

/// The item model and the feed filter: which posts survive into the pager.
///
/// Ports the `videos` `useMemo` in `src/screens/VideoFeed/index.tsx` and the
/// embed classification in `src/types/bsky/post.ts`.
@Suite("Video item model and filtering")
struct VideoItemModelTests {
  // MARK: - Embed classification

  @Test("a video embed classifies as a playable video")
  func videoEmbedClassifies() throws {
    let kind = try #require(
      VideoEmbedKind.classify(Fixtures.videoEmbed("v1", alt: "a cat")))
    guard case .video(let video) = kind else {
      Issue.record("expected .video, got \(kind)")
      return
    }
    #expect(kind.isPlayable)
    #expect(video.playlist == Fixtures.playlist("v1"))
    #expect(video.alt == "a cat")
    #expect(kind.video?.presentation == .standard)
  }

  @Test("a gallery embed is not playable")
  func galleryEmbedIsNotPlayable() throws {
    let kind = try #require(VideoEmbedKind.classify(Fixtures.galleryEmbed()))
    guard case .gallery = kind else {
      Issue.record("expected .gallery, got \(kind)")
      return
    }
    #expect(!kind.isPlayable)
    #expect(kind.video == nil)
  }

  @Test("a link card is not playable")
  func externalEmbedIsNotPlayable() throws {
    let kind = try #require(VideoEmbedKind.classify(Fixtures.externalEmbed()))
    guard case .external = kind else {
      Issue.record("expected .external, got \(kind)")
      return
    }
    #expect(!kind.isPlayable)
  }

  @Test("an image set is not playable")
  func imagesEmbedIsNotPlayable() throws {
    let kind = try #require(VideoEmbedKind.classify(Fixtures.imagesEmbed()))
    guard case .images = kind else {
      Issue.record("expected .images, got \(kind)")
      return
    }
    #expect(!kind.isPlayable)
  }

  @Test("a quote post with no media is not playable")
  func quotePostIsNotPlayable() throws {
    let kind = try #require(VideoEmbedKind.classify(Fixtures.recordEmbed()))
    guard case .post = kind else {
      Issue.record("expected .post, got \(kind)")
      return
    }
    #expect(!kind.isPlayable)
  }

  @Test("a quote post whose media is a video is playable")
  func quoteWithVideoIsPlayable() throws {
    let kind = try #require(
      VideoEmbedKind.classify(Fixtures.recordWithVideoEmbed("v2", quotedId: "quoted")))
    guard case .postWithVideo(let record, let video) = kind else {
      Issue.record("expected .postWithVideo, got \(kind)")
      return
    }
    #expect(kind.isPlayable)
    #expect(video.playlist == Fixtures.playlist("v2"))
    #expect(record.uri == Fixtures.uri("quoted"))
    #expect(record.authorDid == "did:plc:quoted")
  }

  @Test("a quote post whose media is a gallery is not playable")
  func quoteWithGalleryIsNotPlayable() throws {
    let kind = try #require(VideoEmbedKind.classify(Fixtures.recordWithGalleryEmbed()))
    guard case .post = kind else {
      Issue.record("expected .post, got \(kind)")
      return
    }
    #expect(!kind.isPlayable)
  }

  @Test("a post with no embed at all classifies to nil")
  func noEmbedIsNil() {
    #expect(VideoEmbedKind.classify(nil) == nil)
  }

  // MARK: - Unknown variants

  @Test("an unknown embed variant is tolerated and carries its type")
  func unknownVariantIsTolerated() throws {
    // An embed type added after this build: the generated union keeps an
    // `_other` arm, so it decodes rather than throwing.
    let json = """
      {"$type":"app.bsky.embed.future#view","somethingNew":42}
      """
    let record = try JSONDecoder().decode(UnknownRecord.self, from: Data(json.utf8))
    let kind = try #require(VideoEmbedKind.classify(._other(record)))
    guard case .unknown(let type) = kind else {
      Issue.record("expected .unknown, got \(kind)")
      return
    }
    #expect(type == "app.bsky.embed.future#view")
    // It is kept out of the pager: an unrecognised embed is not assumed playable.
    #expect(!kind.isPlayable)
  }

  @Test("an unknown presentation value is tolerated and reads as a video")
  func unknownPresentationIsTolerated() {
    let video = VideoItemVideo(
      view: Fixtures.videoView(
        "v3",
        presentation: App.Bsky.EmbedVideo_View_Presentation(rawValue: "hologram")),
      recordCaptions: [])
    #expect(video.presentation == .unknown("hologram"))
    #expect(!video.presentation.isGif)
    #expect(video.presentation.analyticsLabel == "video")
  }

  @Test("the gif presentation is recognised and relabelled")
  func gifPresentation() {
    let video = VideoItemVideo(
      view: Fixtures.videoView("v4", presentation: .gif), recordCaptions: [])
    #expect(video.presentation == .gif)
    #expect(video.presentation.isGif)
    #expect(video.presentation.analyticsLabel == "gif")
  }

  @Test("a missing presentation reads as a standard video")
  func missingPresentation() {
    let video = VideoItemVideo(view: Fixtures.videoView("v5"), recordCaptions: [])
    #expect(video.presentation == .standard)
  }

  // MARK: - Aspect ratio

  @Test("aspect ratio decides the tall/portrait flag")
  func tallAspectRatio() {
    // 9:16 exactly is tall.
    let exact = VideoItemVideo(
      view: Fixtures.videoView("a1", width: 9, height: 16), recordCaptions: [])
    #expect(exact.isTallAspectRatio)
    // Taller than 9:16 is tall.
    let taller = VideoItemVideo(
      view: Fixtures.videoView("a2", width: 9, height: 20), recordCaptions: [])
    #expect(taller.isTallAspectRatio)
    // Landscape is not.
    let wide = VideoItemVideo(
      view: Fixtures.videoView("a3", width: 16, height: 9), recordCaptions: [])
    #expect(!wide.isTallAspectRatio)
    // No aspect ratio defaults both dimensions to 1, so the ratio is 1:1 - square,
    // which is wider than 9:16 and therefore not "tall". This is the port of
    // `(aspectRatio?.width ?? 1) / (aspectRatio?.height ?? 1)`.
    let missing = VideoItemVideo(view: Fixtures.videoView("a4"), recordCaptions: [])
    #expect(!missing.isTallAspectRatio)
  }

  // MARK: - Captions

  @Test("captions are read from the record, not the view")
  func captionsComeFromRecord() {
    let record = Fixtures.postRecord(
      text: "with captions",
      captions: [Fixtures.caption(lang: "en"), Fixtures.caption(lang: "de")])
    let post = Fixtures.post("c1", record: record, embed: Fixtures.videoEmbed("c1"))
    let captions = videoCaptions(from: post)
    #expect(captions.count == 2)
    #expect(captions.map(\.lang) == ["en", "de"])
  }

  @Test("a post with no video record embed exposes no captions")
  func noCaptionsWithoutVideoRecord() {
    let post = Fixtures.post("c2", embed: Fixtures.videoEmbed("c2"))
    #expect(videoCaptions(from: post).isEmpty)
  }

  @Test("classify threads record captions into the video payload")
  func classifyThreadsCaptions() throws {
    let record = Fixtures.postRecord(captions: [Fixtures.caption(lang: "fr")])
    let post = Fixtures.post("c3", record: record, embed: Fixtures.videoEmbed("c3"))
    let kind = try #require(VideoEmbedKind.classify(post.embed, recordCaptions: videoCaptions(from: post)))
    #expect(kind.video?.captions.map(\.lang) == ["fr"])
  }

  // MARK: - Item construction

  @Test("the selected post of a slice becomes the item, not the thread root")
  func selectedPostBecomesItem() throws {
    let root = Fixtures.post("root", embed: Fixtures.videoEmbed("root"))
    let parent = Fixtures.post("parent", embed: Fixtures.videoEmbed("parent"))
    let selected = Fixtures.post("selected", embed: Fixtures.videoEmbed("selected"))
    let slice = Fixtures.threadSlice([root, parent, selected])

    let item = try #require(makeVideoItem(from: slice))
    #expect(item.postURI == Fixtures.uri("selected"))
    #expect(item.video.playlist == Fixtures.playlist("selected"))
  }

  @Test("a slice whose selected post has no video yields no item")
  func nonVideoSelectedPostYieldsNoItem() {
    let slice = Fixtures.slice(Fixtures.post("img", embed: Fixtures.galleryEmbed()))
    #expect(makeVideoItem(from: slice) == nil)
  }

  @Test("a slice whose feedPostUri is not among its items yields no item")
  func missingSelectedItemYieldsNoItem() {
    let slice = VideoFeedSlice(
      reactKey: "slice-x",
      feedPostUri: Fixtures.uri("absent"),
      items: [
        VideoFeedSliceItem(
          reactKey: "slice-x-0", uri: Fixtures.uri("other"),
          post: Fixtures.post("other", embed: Fixtures.videoEmbed("other")))
      ])
    #expect(makeVideoItem(from: slice) == nil)
  }

  @Test("feedContext and reqId carry through to the item")
  func feedContextCarries() throws {
    let slice = Fixtures.videoSlice("ctx", feedContext: "context-1", reqId: "req-1")
    let item = try #require(makeVideoItem(from: slice))
    #expect(item.feedContext == "context-1")
    #expect(item.reqId == "req-1")
    // The slice key survives for de-duplication reasoning.
    #expect(item.sliceKey == slice.reactKey)
    #expect(item.id == slice.items[0].reactKey)
  }

  @Test("the moderation resolver supplies a decision when the item carries none")
  func moderationResolverApplies() throws {
    let decision = Fixtures.mediaBlurDecision()
    let slice = Fixtures.videoSlice("mod")
    let resolver: VideoModerationResolver = { _ in decision }
    let item = try #require(makeVideoItem(from: slice, moderation: resolver))
    #expect(isBlurredByModeration(item.moderation))
  }

  @Test("an item's own moderation decision wins over the resolver")
  func itemModerationWinsOverResolver() throws {
    let slice = Fixtures.videoSlice("mod2", moderation: Fixtures.informingDecision())
    let resolver: VideoModerationResolver = { _ in Fixtures.mediaBlurDecision() }
    let item = try #require(makeVideoItem(from: slice, moderation: resolver))
    #expect(!isBlurredByModeration(item.moderation))
  }

  @Test("the accessibility label follows RN's Video / Video: alt form")
  func accessibilityLabel() throws {
    let withAlt = try #require(
      makeVideoItem(
        from: Fixtures.slice(
          Fixtures.post("al", embed: Fixtures.videoEmbed("al", alt: "a dog")))))
    #expect(withAlt.accessibilityLabel == "Video: a dog")

    let noAlt = try #require(
      makeVideoItem(from: Fixtures.slice(Fixtures.post("na", embed: Fixtures.videoEmbed("na")))))
    #expect(noAlt.accessibilityLabel == "Video")
  }

  // MARK: - Feed filtering fixtures

  @Test("a mixed feed keeps only the video-bearing posts, in order")
  func mixedFeedFiltersToVideos() {
    let slices = [
      Fixtures.videoSlice("v1"),
      Fixtures.slice(Fixtures.post("g1", embed: Fixtures.galleryEmbed())),
      Fixtures.slice(Fixtures.post("e1", embed: Fixtures.externalEmbed())),
      Fixtures.videoSlice("v2"),
      Fixtures.slice(Fixtures.post("i1", embed: Fixtures.imagesEmbed())),
      Fixtures.slice(Fixtures.post("q1", embed: Fixtures.recordEmbed())),
    ]
    let items = makeVideoItems(from: slices)
    #expect(items.map(\.postURI) == [Fixtures.uri("v1"), Fixtures.uri("v2")])
  }

  @Test("a quote-with-video post survives the filter")
  func quoteWithVideoSurvives() {
    let slices = [
      Fixtures.slice(
        Fixtures.post("qv", embed: Fixtures.recordWithVideoEmbed("qv"))),
      Fixtures.slice(
        Fixtures.post("qg", embed: Fixtures.recordWithGalleryEmbed())),
    ]
    let items = makeVideoItems(from: slices)
    #expect(items.count == 1)
    #expect(items[0].postURI == Fixtures.uri("qv"))
    guard case .postWithVideo = items[0].embedKind else {
      Issue.record("expected a quote-with-video kind")
      return
    }
  }

  @Test("an all-non-video feed yields an empty pager")
  func allNonVideoIsEmpty() {
    let slices = [
      Fixtures.slice(Fixtures.post("g", embed: Fixtures.galleryEmbed())),
      Fixtures.slice(Fixtures.post("e", embed: Fixtures.externalEmbed())),
    ]
    #expect(makeVideoItems(from: slices).isEmpty)
  }

  // MARK: - Initial post offset

  @Test("an initial post URI slices the pager from that item")
  func initialPostSlicesList() {
    let slices = [Fixtures.videoSlice("v1"), Fixtures.videoSlice("v2"), Fixtures.videoSlice("v3")]
    let items = makeVideoItems(from: slices)
    let sliced = videoPagerItems(items, initialPostURI: Fixtures.uri("v2"))
    #expect(sliced.map(\.postURI) == [Fixtures.uri("v2"), Fixtures.uri("v3")])
  }

  @Test("an initial post URI that is absent leaves the pager intact")
  func absentInitialPostDoesNotSlice() {
    let slices = [Fixtures.videoSlice("v1"), Fixtures.videoSlice("v2")]
    let items = makeVideoItems(from: slices)
    #expect(videoPagerItems(items, initialPostURI: Fixtures.uri("nope")).count == 2)
    #expect(videoPagerItems(items, initialPostURI: nil).count == 2)
  }

  @Test("startingVideoIndex reports the matching index and clamps unknowns to zero")
  func startingIndex() {
    let slices = [Fixtures.videoSlice("v1"), Fixtures.videoSlice("v2")]
    let items = makeVideoItems(from: slices)
    #expect(startingVideoIndex(for: items, initialPostURI: Fixtures.uri("v2")) == 1)
    #expect(startingVideoIndex(for: items, initialPostURI: Fixtures.uri("v1")) == 0)
    #expect(startingVideoIndex(for: items, initialPostURI: Fixtures.uri("nope")) == 0)
    #expect(startingVideoIndex(for: items, initialPostURI: nil) == 0)
    #expect(startingVideoIndex(for: [], initialPostURI: Fixtures.uri("v1")) == 0)
  }
}
