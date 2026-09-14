import Foundation
import Lexicons
import Moderation
import SwiftAtproto

/// How a video should be presented, ported from the `presentation` hint on
/// `app.bsky.embed.video#view`.
///
/// The lexicon declares `knownValues: ["default", "gif"]`, but the generated
/// enum keeps an `_other` arm so a server that adds a value does not break
/// decoding. This port collapses the unknown arm to ``unknown(_:)`` and treats
/// every non-`gif` value as a normal video, which is what the RN comparison
/// `embed.presentation === 'gif'` does.
public enum VideoPresentation: Sendable, Hashable {
  /// A normal video with controls.
  case standard
  /// A silent, looping, control-free clip. RN: `presentation === 'gif'`.
  case gif
  /// A presentation value this build does not know. Treated as ``standard``.
  case unknown(String)

  /// Maps the generated lexicon value.
  public init(_ value: App.Bsky.EmbedVideo_View_Presentation?) {
    switch value {
    case .some(.gif): self = .gif
    case .some(.`default`): self = .standard
    case .some(._other(let raw)): self = .unknown(raw)
    case nil: self = .standard
    }
  }

  /// True when the clip plays as a GIF: no controls, starts muted, loops.
  public var isGif: Bool { self == .gif }

  /// The analytics label RN reports: `'gif'` or `'video'`. An unknown
  /// presentation is reported as a video.
  public var analyticsLabel: String { isGif ? "gif" : "video" }
}

/// One caption track on a video embed.
///
/// Only the record-side (`app.bsky.embed.video#main`) carries captions; the
/// view does not. This model is filled from the post record when it is available,
/// so the player can offer a track list without the Logic layer touching a blob.
public struct VideoCaptionTrack: Sendable, Hashable {
  /// The BCP-47 language tag. RN: `caption.lang`.
  public let lang: String
  /// The caption blob's CID, the handle the view dereferences to a URL.
  public let blobCID: String

  public init(lang: String, blobCID: String) {
    self.lang = lang
    self.blobCID = blobCID
  }
}

/// The video payload of a feed item, reduced to data.
///
/// Port of `app.bsky.embed.video#view` as the RN immersive feed consumes it:
/// `playlist`, `thumbnail`, `alt`, `aspectRatio` and `presentation`, plus the
/// captions that live on the record side. Deliberately contains no player and no
/// AVFoundation type - the Views package owns the player, and this type is the
/// value it is handed.
public struct VideoItemVideo: Sendable, Hashable {
  /// The HLS playlist URL. RN: `embed.playlist`.
  public let playlist: String
  /// The video CID, the stable identity of the media itself.
  public let cid: String
  /// The poster image, shown while the player loads.
  public let thumbnail: String?
  /// Alt text. RN renders a badge when present.
  public let alt: String?
  /// The intrinsic aspect ratio, when the appview supplied one.
  public let aspectRatio: VideoAspectRatio?
  /// The presentation hint.
  public let presentation: VideoPresentation
  /// Caption tracks from the record side, in declared order.
  public let captions: [VideoCaptionTrack]
  /// The embed's `$type` when it was not the known video variant.
  public let unknownVariant: String?

  public init(
    playlist: String,
    cid: String,
    thumbnail: String? = nil,
    alt: String? = nil,
    aspectRatio: VideoAspectRatio? = nil,
    presentation: VideoPresentation = .standard,
    captions: [VideoCaptionTrack] = [],
    unknownVariant: String? = nil
  ) {
    self.playlist = playlist
    self.cid = cid
    self.thumbnail = thumbnail
    self.alt = alt
    self.aspectRatio = aspectRatio
    self.presentation = presentation
    self.captions = captions
    self.unknownVariant = unknownVariant
  }

  /// True when the video is taller than 9:16, so it is scaled to cover.
  ///
  /// Port of `isTallAspectRatio`: `width / height <= 9 / 16`, defaulting each
  /// missing dimension to 1 - which makes a video with no aspect ratio "tall".
  public var isTallAspectRatio: Bool {
    let width = Double(aspectRatio?.width ?? 1)
    let height = Double(aspectRatio?.height ?? 1)
    return width / height <= VideoFeedConstants.tallAspectRatioThreshold
  }

  /// Builds the model from a decoded `embed.video#view`.
  ///
  /// - Parameters:
  ///   - view: the decoded view.
  ///   - recordCaptions: captions read from the post record, if the caller has
  ///     the record. The view itself never carries them.
  public init(
    view: App.Bsky.EmbedVideo_View,
    recordCaptions: [VideoCaptionTrack] = []
  ) {
    self.init(
      playlist: view.playlist.rawValue,
      cid: view.cid.rawValue,
      thumbnail: view.thumbnail?.rawValue,
      alt: view.alt,
      aspectRatio: view.aspectRatio.map {
        VideoAspectRatio(width: $0.width, height: $0.height)
      },
      presentation: VideoPresentation(view.presentation),
      captions: recordCaptions)
  }
}

/// An embed aspect ratio, ported from `app.bsky.embed.defs#aspectRatio`.
public struct VideoAspectRatio: Sendable, Hashable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

/// How a post's embed classifies for the video feed.
///
/// Port of `parseEmbed` / the `Embed` union in `src/types/bsky/post.ts`, reduced
/// to the cases the immersive feed cares about. The feed keeps a post when this
/// is ``video`` or ``postWithVideo`` - an embed the app does not recognise is
/// dropped rather than guessed at, because the feed's whole contract is "an item
/// the pager can play".
public enum VideoEmbedKind: Sendable, Hashable {
  /// A direct `app.bsky.embed.video#view`.
  case video(VideoItemVideo)
  /// A quote embed whose media is a video
  /// (`app.bsky.embed.recordWithMedia#view` with video media).
  case postWithVideo(record: VideoRecordEmbed, video: VideoItemVideo)
  /// A gallery embed (`app.bsky.embed.gallery#view`). Galleries are image-only
  /// today, so this is never playable; the case exists so a caller can tell a
  /// gallery apart from a link.
  case gallery
  /// A link/external card.
  case external
  /// An image set.
  case images
  /// A quote embed with no video media.
  case post
  /// Anything else, including embed types added after this build.
  case unknown(type: String?)

  /// The playable video, when this embed has one.
  public var video: VideoItemVideo? {
    switch self {
    case .video(let video), .postWithVideo(_, let video): return video
    case .gallery, .external, .images, .post, .unknown: return nil
    }
  }

  /// True when the embed carries a playable video.
  public var isPlayable: Bool { video != nil }

  /// The classified kind of a post view's embed, or `nil` when the post has no
  /// embed at all.
  ///
  /// - Parameter recordCaptions: captions read from the post record, if known.
  public static func classify(
    _ embed: App.Bsky.FeedDefs_PostView_Embed?,
    recordCaptions: [VideoCaptionTrack] = []
  ) -> VideoEmbedKind? {
    guard let embed else { return nil }
    switch embed {
    case .embedVideoView(let view):
      return .video(VideoItemVideo(view: view, recordCaptions: recordCaptions))
    case .embedGalleryView:
      return .gallery
    case .embedExternalView:
      return .external
    case .embedImagesView:
      return .images
    case .embedRecordView:
      return .post
    case .embedRecordWithMediaView(let view):
      let record = VideoRecordEmbed(view.record.record)
      if case .embedVideoView(let media) = view.media {
        return .postWithVideo(
          record: record, video: VideoItemVideo(view: media, recordCaptions: recordCaptions))
      }
      return .post
    case ._other(let unknown):
      return .unknown(type: unknown.type)
    }
  }
}

/// The quoted post inside a `recordWithMedia` embed, reduced to what the
/// immersive overlay shows.
public struct VideoRecordEmbed: Sendable, Hashable {
  /// The quoted post's URI, when the record resolved to a view.
  public let uri: String?
  /// The quoted post's author DID, when known.
  public let authorDid: String?
  /// The quoted record's `$type`, when it is not a post view.
  public let type: String?

  public init(uri: String? = nil, authorDid: String? = nil, type: String? = nil) {
    self.uri = uri
    self.authorDid = authorDid
    self.type = type
  }

  /// Reads the fields from a `recordWithMedia#view`'s record arm.
  public init(_ record: App.Bsky.EmbedRecord_View_Record) {
    switch record {
    case .embedRecordViewRecord(let view):
      self.init(uri: view.uri.rawValue, authorDid: view.author.did.rawValue, type: "app.bsky.embed.record#viewRecord")
    case .embedRecordViewNotFound(let view):
      self.init(uri: view.uri.rawValue, type: "app.bsky.embed.record#viewNotFound")
    case .embedRecordViewBlocked(let view):
      self.init(uri: view.uri.rawValue, type: "app.bsky.embed.record#viewBlocked")
    case .embedRecordViewDetached(let view):
      self.init(uri: view.uri.rawValue, type: "app.bsky.embed.record#viewDetached")
    case .feedDefsGeneratorView(let view):
      self.init(
        uri: view.uri.rawValue, authorDid: view.creator.did.rawValue,
        type: "app.bsky.feed.defs#generatorView")
    case .graphDefsListView(let view):
      self.init(
        uri: view.uri.rawValue, authorDid: view.creator.did.rawValue,
        type: "app.bsky.graph.defs#listView")
    case .labelerDefsLabelerView(let view):
      self.init(
        uri: view.uri.rawValue, authorDid: view.creator.did.rawValue,
        type: "app.bsky.labeler.defs#labelerView")
    case .graphDefsStarterPackViewBasic(let view):
      self.init(uri: view.uri.rawValue, type: "app.bsky.graph.defs#starterPackViewBasic")
    case ._other(let unknown):
      self.init(type: unknown.type)
    }
  }
}

/// One item of the immersive video feed: a post, its playable video, and the
/// feed metadata the overlay and the feedback pipeline need.
///
/// Port of the `VideoItem` type in `src/screens/VideoFeed/index.tsx`, which RN
/// builds by walking each tuned slice for the item whose URI matches the slice's
/// `feedPostUri` and whose embed is a video view.
///
/// The moderation decision is carried as data; deriving blur/flags from it is
/// ``VideoAutoplayPolicy``'s job, so this type stays a plain value.
public struct VideoItem: Sendable {
  /// Stable list identity. RN: the item's `_reactKey`.
  public let id: String
  /// The post view.
  public let post: App.Bsky.FeedDefs_PostView
  /// The playable video payload.
  public let video: VideoItemVideo
  /// The classified embed, so an overlay can tell a quote-with-video from a
  /// plain video.
  public let embedKind: VideoEmbedKind
  /// The moderation decision for the post, or `nil` when moderation is off.
  public let moderation: ModerationDecision?
  /// The feed's per-item context string. RN passes it to feed feedback.
  public let feedContext: String?
  /// The feed request id. RN passes it to feed feedback.
  public let reqId: String?
  /// The slice this item was selected from, for de-duplication reasoning.
  public let sliceKey: String

  public init(
    id: String,
    post: App.Bsky.FeedDefs_PostView,
    video: VideoItemVideo,
    embedKind: VideoEmbedKind,
    moderation: ModerationDecision? = nil,
    feedContext: String? = nil,
    reqId: String? = nil,
    sliceKey: String = ""
  ) {
    self.id = id
    self.post = post
    self.video = video
    self.embedKind = embedKind
    self.moderation = moderation
    self.feedContext = feedContext
    self.reqId = reqId
    self.sliceKey = sliceKey
  }

  /// The post URI, the key every playback state and feedback call uses.
  public var postURI: String { post.uri.rawValue }

  /// The author DID.
  public var authorDid: String { post.author.did.rawValue }

  /// True when the video plays as a silent looping GIF.
  public var isGif: Bool { video.presentation.isGif }

  /// The overlay label for the video, matching RN's `Video: <alt>` /
  /// `Video` accessibility label. Empty alt reads as plain `Video`.
  public var accessibilityLabel: String {
    guard let alt = video.alt, !alt.isEmpty else { return "Video" }
    return "Video: \(alt)"
  }
}
