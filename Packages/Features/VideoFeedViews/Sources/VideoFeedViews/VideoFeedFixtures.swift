import Foundation
import Lexicons
import Moderation
import SwiftAtproto
import VideoFeedLogic

/// Sample items for the debug entry point and for previews.
///
/// The immersive screen needs a signed-in account and a feed fetch before it has
/// anything to show, so the fixture builds the smallest thing a pager can page:
/// a few ``VideoItem`` values with real, publicly playable streams. The App
/// surface mounts it in ``VideoFeedSurfaces``, which is what makes the player
/// reachable from a debug toolbar without a login.
public enum VideoFeedFixtures {
  /// A CIS-1 variant string, so the fixture's CIDs parse.
  static let cid = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

  /// A timestamp the lexicon `FormatString<Date>` accepts.
  static let indexedAt = "2026-09-14T12:00:00.000Z"

  /// Blade-runner-style sample HLS streams, the Apple-hosted test assets. They
  /// are what the player exercises in the fixture.
  static let samplePlaylists = [
    "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8",
    "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
    "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8",
  ]

  /// Poster images, so the placeholder path and the poster path are both
  /// reachable.
  static let sampleThumbnails = [
    "https://picsum.photos/seed/bskyvideo1/1200/1600",
    "https://picsum.photos/seed/bskyvideo2/1600/900",
  ]

  /// Three fixture items: a portrait video, a landscape one, and a GIF-style
  /// loop with no thumbnail so the poster fallback is exercised.
  public static func items() -> [VideoItem] {
    [
      item(
        id: "fixture-1",
        handle: "alice.test",
        displayName: "Alice",
        caption: "Portrait clip, muted by default and looping on tap.",
        playlist: samplePlaylists[0],
        width: 1080,
        height: 1920,
        thumbnail: sampleThumbnails[0],
        presentation: .`default`,
        counts: (reply: 12, like: 480)),
      item(
        id: "fixture-2",
        handle: "bluesky.test",
        displayName: "Bluesky",
        caption: "Landscape clip with a scrubber.",
        playlist: samplePlaylists[1],
        width: 1920,
        height: 1080,
        thumbnail: sampleThumbnails[1],
        presentation: .`default`,
        counts: (reply: 3, like: 12)),
      item(
        id: "fixture-3",
        handle: "gifs.test",
        displayName: "Loops",
        caption: "A GIF presentation: silent, looping, no controls, no poster.",
        playlist: samplePlaylists[2],
        width: 720,
        height: 1280,
        thumbnail: nil,
        presentation: .gif,
        counts: (nil, nil)),
    ]
  }

  /// Builds one fixture item.
  // swiftlint:disable:next function_parameter_count
  static func item(
    id: String,
    handle: String,
    displayName: String,
    caption: String,
    playlist: String,
    width: Int,
    height: Int,
    thumbnail: String?,
    presentation: App.Bsky.EmbedVideo_View_Presentation?,
    counts: (reply: Int?, like: Int?)
  ) -> VideoItem {
    let videoView = App.Bsky.EmbedVideo_View(
      alt: caption,
      aspectRatio: App.Bsky.EmbedDefs_AspectRatio(height: height, width: width),
      cid: FormatString<LexLink>(rawValue: cid),
      playlist: FormatString<URI>(rawValue: playlist),
      presentation: presentation,
      thumbnail: thumbnail.map { FormatString<URI>(rawValue: $0) })
    let post = App.Bsky.FeedDefs_PostView(
      author: App.Bsky.ActorDefs_ProfileViewBasic(
        did: FormatString<DID>(rawValue: "did:plc:\(handle)"),
        displayName: displayName,
        handle: FormatString<Handle>(rawValue: handle)),
      cid: FormatString<LexLink>(rawValue: cid),
      embed: .embedVideoView(videoView),
      indexedAt: FormatString<Date>(rawValue: indexedAt),
      likeCount: counts.like,
      record: .record(
        App.Bsky.FeedPost(
          createdAt: FormatString<Date>(rawValue: indexedAt),
          text: caption)),
      replyCount: counts.reply,
      uri: FormatString<ATURI>(
        rawValue: "at://did:plc:\(handle)/app.bsky.feed.post/\(id)"))
    return VideoItem(
      id: id,
      post: post,
      video: VideoItemVideo(view: videoView),
      embedKind: .video(VideoItemVideo(view: videoView)),
      sliceKey: id)
  }
}
