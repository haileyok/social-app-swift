import Foundation
import Lexicons
import Moderation
import SwiftAtproto

@testable import VideoFeedLogic

/// A CIDv1 string the vendored `LexLink` parser accepts, used wherever a fixture
/// needs a real link.
let testCID = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

/// Fixture builders for the video-feed suites.
///
/// The package deliberately does not reach into `TestSupport` (a placeholder), so
/// these are package-local, following the `HomeFeedLogicTests` pattern.
enum Fixtures {
  /// An ISO-8601 timestamp the lexicon `FormatString<Date>` accepts.
  static let defaultDate = "2026-08-31T00:00:00.000Z"

  static func profile(did: String = "did:plc:alice", handle: String = "alice.test")
    -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<SwiftAtproto.DID>(rawValue: did),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle))
  }

  static func uri(_ id: String, did: String = "did:plc:alice") -> String {
    "at://\(did)/app.bsky.feed.post/\(id)"
  }

  static func playlist(_ id: String) -> String {
    "https://video.bsky.app/watch/\(id)/playlist.m3u8"
  }

  // MARK: - Embeds

  /// A `app.bsky.embed.video#view`.
  static func videoView(
    _ id: String,
    alt: String? = nil,
    width: Int? = nil,
    height: Int? = nil,
    presentation: App.Bsky.EmbedVideo_View_Presentation? = nil,
    thumbnail: String? = nil
  ) -> App.Bsky.EmbedVideo_View {
    App.Bsky.EmbedVideo_View(
      alt: alt,
      aspectRatio: width.flatMap { w in height.map { h in App.Bsky.EmbedDefs_AspectRatio(height: h, width: w) } },
      cid: FormatString<LexLink>(rawValue: testCID),
      playlist: FormatString<URI>(rawValue: playlist(id)),
      presentation: presentation,
      thumbnail: thumbnail.map { FormatString<URI>(rawValue: $0) })
  }

  /// A video embed view.
  static func videoEmbed(
    _ id: String,
    alt: String? = nil,
    width: Int? = nil,
    height: Int? = nil,
    presentation: App.Bsky.EmbedVideo_View_Presentation? = nil
  ) -> App.Bsky.FeedDefs_PostView_Embed {
    .embedVideoView(
      videoView(id, alt: alt, width: width, height: height, presentation: presentation))
  }

  /// A gallery embed view with `count` image items.
  static func galleryEmbed(count: Int = 2) -> App.Bsky.FeedDefs_PostView_Embed {
    let items = (0..<count).map { index in
      App.Bsky.EmbedGallery_View_Items_Elem.embedGalleryViewImage(
        App.Bsky.EmbedGallery_ViewImage(
          alt: "image \(index)",
          aspectRatio: App.Bsky.EmbedDefs_AspectRatio(height: 100, width: 100),
          fullsize: FormatString<URI>(rawValue: "https://cdn.test/full-\(index).jpg"),
          thumbnail: FormatString<URI>(rawValue: "https://cdn.test/thumb-\(index).jpg")))
    }
    return .embedGalleryView(App.Bsky.EmbedGallery_View(items: items))
  }

  /// A link-card embed.
  static func externalEmbed(
    uri: String = "https://example.com"
  ) -> App.Bsky.FeedDefs_PostView_Embed {
    .embedExternalView(
      App.Bsky.EmbedExternal_View(
        external: App.Bsky.EmbedExternal_ViewExternal(
          description: "description",
          title: "title",
          uri: FormatString<URI>(rawValue: uri))))
  }

  /// An image-set embed.
  static func imagesEmbed() -> App.Bsky.FeedDefs_PostView_Embed {
    .embedImagesView(
      App.Bsky.EmbedImages_View(images: [
        App.Bsky.EmbedImages_ViewImage(
          alt: "alt",
          aspectRatio: App.Bsky.EmbedDefs_AspectRatio(height: 100, width: 100),
          fullsize: FormatString<URI>(rawValue: "https://cdn.test/full.jpg"),
          thumb: FormatString<URI>(rawValue: "https://cdn.test/thumb.jpg"))
      ]))
  }

  /// A quote-post embed with no media.
  static func recordEmbed(
    _ quotedId: String = "quoted"
  ) -> App.Bsky.FeedDefs_PostView_Embed {
    .embedRecordView(
      App.Bsky.EmbedRecord_View(
        record: .embedRecordViewRecord(
          App.Bsky.EmbedRecord_ViewRecord(
            author: profile(did: "did:plc:quoted", handle: "quoted.test"),
            cid: FormatString<LexLink>(rawValue: testCID),
            indexedAt: FormatString<Date>(rawValue: defaultDate),
            uri: FormatString<ATURI>(rawValue: uri(quotedId)),
            value: .record(App.Bsky.FeedPost(
              createdAt: FormatString<Date>(rawValue: defaultDate),
              text: "quoted"))))))
  }

  /// A quote-with-video embed: `recordWithMedia#view` whose media is a video.
  ///
  /// This is the "gallery-with-video" shape the task calls out: a post that is
  /// primarily a quote but carries a playable video. The immersive feed must show
  /// it, because RN's check is on the *media* arm.
  static func recordWithVideoEmbed(
    _ id: String,
    quotedId: String = "quoted",
    presentation: App.Bsky.EmbedVideo_View_Presentation? = nil
  ) -> App.Bsky.FeedDefs_PostView_Embed {
    .embedRecordWithMediaView(
      App.Bsky.EmbedRecordWithMedia_View(
        media: .embedVideoView(videoView(id, presentation: presentation)),
        record: App.Bsky.EmbedRecord_View(
          record: .embedRecordViewRecord(
            App.Bsky.EmbedRecord_ViewRecord(
              author: profile(did: "did:plc:quoted", handle: "quoted.test"),
              cid: FormatString<LexLink>(rawValue: testCID),
              indexedAt: FormatString<Date>(rawValue: defaultDate),
              uri: FormatString<ATURI>(rawValue: uri(quotedId)),
              value: .record(App.Bsky.FeedPost(
                createdAt: FormatString<Date>(rawValue: defaultDate),
                text: "quoted")))))))
  }

  /// A quote-with-a-gallery embed: the media arm is not a video, so the post is
  /// not playable by the immersive feed.
  static func recordWithGalleryEmbed() -> App.Bsky.FeedDefs_PostView_Embed {
    .embedRecordWithMediaView(
      App.Bsky.EmbedRecordWithMedia_View(
        media: .embedGalleryView(
          App.Bsky.EmbedGallery_View(items: [
            .embedGalleryViewImage(
              App.Bsky.EmbedGallery_ViewImage(
                alt: "alt",
                aspectRatio: App.Bsky.EmbedDefs_AspectRatio(height: 100, width: 100),
                fullsize: FormatString<URI>(rawValue: "https://cdn.test/full.jpg"),
                thumbnail: FormatString<URI>(rawValue: "https://cdn.test/thumb.jpg")))
          ])),
        record: App.Bsky.EmbedRecord_View(
          record: .embedRecordViewRecord(
            App.Bsky.EmbedRecord_ViewRecord(
              author: profile(did: "did:plc:quoted", handle: "quoted.test"),
              cid: FormatString<LexLink>(rawValue: testCID),
              indexedAt: FormatString<Date>(rawValue: defaultDate),
              uri: FormatString<ATURI>(rawValue: uri("quoted")),
              value: .record(App.Bsky.FeedPost(
                createdAt: FormatString<Date>(rawValue: defaultDate),
                text: "quoted")))))))
  }

  // MARK: - Posts

  /// A post view identified by `id`.
  static func post(
    _ id: String,
    author: App.Bsky.ActorDefs_ProfileViewBasic? = nil,
    record: App.Bsky.FeedPost? = nil,
    embed: App.Bsky.FeedDefs_PostView_Embed? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: author ?? profile(),
      cid: FormatString<LexLink>(rawValue: testCID),
      embed: embed,
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      record: .record(record ?? postRecord(text: id)),
      uri: FormatString<ATURI>(rawValue: uri(id)))
  }

  static func postRecord(
    text: String = "text",
    captions: [App.Bsky.EmbedVideo_Caption]? = nil
  ) -> App.Bsky.FeedPost {
    App.Bsky.FeedPost(
      createdAt: FormatString<Date>(rawValue: defaultDate),
      embed: captions.map {
        .embedVideo(App.Bsky.EmbedVideo(captions: $0, video: blob()))
      },
      text: text)
  }

  /// A `#caption` entry.
  static func caption(lang: String = "en", cid: String = "bafycaption")
    -> App.Bsky.EmbedVideo_Caption {
    App.Bsky.EmbedVideo_Caption(
      file: blob(mimeType: "text/vtt"),
      lang: FormatString<SwiftAtproto.Language>(rawValue: lang))
  }

  /// A blob for the embed's required `video` field.
  ///
  /// `LexBlob` exposes no memberwise initialiser (only `init(original:mimeType:)`),
  /// so fixtures are built by decoding the wire shape - which also keeps the
  /// fixture honest about what a real response looks like.
  static func blob(mimeType: String = "video/mp4") -> LexBlob {
    let json = """
      {"$type":"blob","ref":{"$link":"\(testCID)"},"mimeType":"\(mimeType)","size":1000}
      """
    // The shape is fixed and the CID is a valid constant, so a failure here is a
    // fixture bug rather than a runtime condition.
    return try! JSONDecoder().decode(LexBlob.self, from: Data(json.utf8))
  }

  // MARK: - Feed items

  /// A `feedViewPost` around `postView`.
  static func feedViewPost(
    _ postView: App.Bsky.FeedDefs_PostView,
    reply: App.Bsky.FeedDefs_ReplyRef? = nil,
    reason: App.Bsky.FeedDefs_FeedViewPost_Reason? = nil,
    feedContext: String? = nil,
    reqId: String? = nil
  ) -> App.Bsky.FeedDefs_FeedViewPost {
    App.Bsky.FeedDefs_FeedViewPost(
      feedContext: feedContext,
      post: postView,
      reason: reason,
      reply: reply,
      reqId: reqId)
  }

  /// A plain top-level post as a feed item.
  static func item(_ id: String, feedContext: String? = nil, reqId: String? = nil)
    -> App.Bsky.FeedDefs_FeedViewPost {
    feedViewPost(post(id), feedContext: feedContext, reqId: reqId)
  }

  /// A video-bearing feed item, the shape the video feed's pages are full of.
  static func videoItem(
    _ id: String,
    presentation: App.Bsky.EmbedVideo_View_Presentation? = nil,
    feedContext: String? = nil,
    reqId: String? = nil
  ) -> App.Bsky.FeedDefs_FeedViewPost {
    feedViewPost(
      post(id, embed: videoEmbed(id, presentation: presentation)),
      feedContext: feedContext,
      reqId: reqId)
  }

  // MARK: - Slices

  /// A one-item slice whose selected post is `post`.
  static func slice(
    _ post: App.Bsky.FeedDefs_PostView,
    reactKey: String? = nil,
    feedContext: String? = nil,
    reqId: String? = nil,
    moderation: ModerationDecision? = nil,
    isReply: Bool = false,
    isRepost: Bool = false
  ) -> VideoFeedSlice {
    let key = reactKey ?? "slice-\(post.uri.rawValue)-\(defaultDate)"
    return VideoFeedSlice(
      reactKey: key,
      feedPostUri: post.uri.rawValue,
      items: [
        VideoFeedSliceItem(
          reactKey: "\(key)-0-\(post.uri.rawValue)",
          uri: post.uri.rawValue,
          post: post,
          moderation: moderation)
      ],
      feedContext: feedContext,
      reqId: reqId,
      isReply: isReply,
      isRepost: isRepost)
  }

  /// A slice with several items, the *last* being the selected post - the shape
  /// the tuner produces for a thread.
  static func threadSlice(
    _ posts: [App.Bsky.FeedDefs_PostView],
    reactKey: String = "slice-thread"
  ) -> VideoFeedSlice {
    let selected = posts[posts.count - 1]
    return VideoFeedSlice(
      reactKey: reactKey,
      feedPostUri: selected.uri.rawValue,
      items: posts.enumerated().map { index, post in
        VideoFeedSliceItem(
          reactKey: "\(reactKey)-\(index)-\(post.uri.rawValue)",
          uri: post.uri.rawValue,
          post: post)
      })
  }

  /// A post that carries a playable video, as a slice.
  static func videoSlice(
    _ id: String,
    presentation: App.Bsky.EmbedVideo_View_Presentation? = nil,
    feedContext: String? = nil,
    reqId: String? = nil,
    moderation: ModerationDecision? = nil
  ) -> VideoFeedSlice {
    slice(
      post(id, embed: videoEmbed(id, presentation: presentation)),
      feedContext: feedContext,
      reqId: reqId,
      moderation: moderation)
  }

  // MARK: - Moderation

  /// A decision with a `contentMedia` blur label, the shape a media-only label
  /// produces.
  static func mediaBlurDecision() -> ModerationDecision {
    var decision = ModerationDecision()
    decision.setDid("did:plc:alice")
    decision.causes.append(
      ModerationCause(
        type: .label,
        source: .user,
        priority: 7,
        label: Label(src: "did:plc:labeler", uri: "at://x", val: "graphic-media"),
        labelDef: nil,
        target: .content,
        setting: .warn,
        behavior: ModerationBehavior(contentMedia: .blur)))
    return decision
  }

  /// A decision with a `contentView` blur.
  static func contentViewBlurDecision() -> ModerationDecision {
    var decision = ModerationDecision()
    decision.setDid("did:plc:alice")
    decision.causes.append(
      ModerationCause(
        type: .label,
        source: .user,
        priority: 5,
        label: Label(src: "did:plc:labeler", uri: "at://x", val: "nudity"),
        labelDef: nil,
        target: .content,
        setting: .warn,
        behavior: ModerationBehavior(contentView: .blur)))
    return decision
  }

  /// A decision with an inform-only cause: no blur, so playback is allowed.
  static func informingDecision() -> ModerationDecision {
    var decision = ModerationDecision()
    decision.setDid("did:plc:alice")
    decision.causes.append(
      ModerationCause(
        type: .label,
        source: .user,
        priority: 8,
        label: Label(src: "did:plc:labeler", uri: "at://x", val: "sexual"),
        labelDef: nil,
        target: .content,
        setting: .warn,
        behavior: ModerationBehavior(contentView: .inform)))
    return decision
  }
}
