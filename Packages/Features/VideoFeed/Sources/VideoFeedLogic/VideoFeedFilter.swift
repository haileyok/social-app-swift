import Domain
import Foundation
import Lexicons
import Moderation
import SwiftAtproto

/// A tuned feed slice, reduced to what the immersive feed reads.
///
/// The video feed consumes the *tuned* page, not the raw one: RN runs the same
/// `usePostFeedQuery` as the timeline and then walks `page.slices` looking for
/// the slice's selected post. This struct is the minimal slice shape that walk
/// needs, so the filter can be tested without building a whole `HomeFeedQuery`.
public struct VideoFeedSlice: Sendable {
  /// The slice's identity. RN: `slice._reactKey`.
  public let reactKey: String
  /// The URI of the post the slice was selected for. RN: `slice.feedPostUri`.
  public let feedPostUri: String
  /// The slice's items, thread-root first.
  public let items: [VideoFeedSliceItem]
  /// The feed context string, carried onto the item.
  public let feedContext: String?
  /// The feed request id, carried onto the item.
  public let reqId: String?
  /// Whether the slice is a reply.
  public let isReply: Bool
  /// Whether the slice is a repost.
  public let isRepost: Bool

  public init(
    reactKey: String,
    feedPostUri: String,
    items: [VideoFeedSliceItem],
    feedContext: String? = nil,
    reqId: String? = nil,
    isReply: Bool = false,
    isRepost: Bool = false
  ) {
    self.reactKey = reactKey
    self.feedPostUri = feedPostUri
    self.items = items
    self.feedContext = feedContext
    self.reqId = reqId
    self.isReply = isReply
    self.isRepost = isRepost
  }
}

/// One post inside a ``VideoFeedSlice``.
public struct VideoFeedSliceItem: Sendable {
  /// The item's own identity. RN: `item._reactKey`.
  public let reactKey: String
  /// The post URI.
  public let uri: String
  /// The post view.
  public let post: App.Bsky.FeedDefs_PostView
  /// The moderation decision for this item, or `nil` when moderation is off.
  public let moderation: ModerationDecision?

  public init(
    reactKey: String,
    uri: String,
    post: App.Bsky.FeedDefs_PostView,
    moderation: ModerationDecision? = nil
  ) {
    self.reactKey = reactKey
    self.uri = uri
    self.post = post
    self.moderation = moderation
  }
}

/// The per-item moderation hook the filter uses.
///
/// The Logic layer does not build decisions (that needs labeler config,
/// preferences and the post record, all of which belong to the caller); it takes
/// a closure so the filter stays pure and testable.
public typealias VideoModerationResolver =
  @Sendable (App.Bsky.FeedDefs_PostView) -> ModerationDecision?

/// Turns a tuned page into the ordered list of playable video items.
///
/// Port of the `videos` `useMemo` in `src/screens/VideoFeed/index.tsx`:
///
/// 1. for each slice, find the item whose `uri` equals the slice's
///    `feedPostUri` (the slice's *selected* post);
/// 2. keep it only when its embed is a `app.bsky.embed.video#view`;
/// 3. flatten the per-page results in page order.
///
/// A post whose embed is a gallery, a link, an image set, or a type this build
/// does not know is dropped - the immersive pager can only show a video.
///
/// - Parameters:
///   - slices: the tuned slices, in feed order.
///   - moderation: resolves a decision per post, or `nil` to carry none.
public func makeVideoItems(
  from slices: [VideoFeedSlice],
  moderation: VideoModerationResolver? = nil
) -> [VideoItem] {
  slices.compactMap { slice in makeVideoItem(from: slice, moderation: moderation) }
}

/// Selects the playable item out of one slice, or `nil` when the slice's
/// selected post is not a video.
public func makeVideoItem(
  from slice: VideoFeedSlice,
  moderation: VideoModerationResolver? = nil
) -> VideoItem? {
  guard let feedItem = slice.items.first(where: { $0.uri == slice.feedPostUri }) else {
    return nil
  }
  guard
    let kind = VideoEmbedKind.classify(
      feedItem.post.embed, recordCaptions: videoCaptions(from: feedItem.post))
  else {
    return nil
  }
  guard let video = kind.video else { return nil }
  return VideoItem(
    id: feedItem.reactKey,
    post: feedItem.post,
    video: video,
    embedKind: kind,
    moderation: feedItem.moderation ?? moderation?(feedItem.post),
    feedContext: slice.feedContext,
    reqId: slice.reqId,
    sliceKey: slice.reactKey)
}

/// Reads the caption tracks out of a post view's record, when the record is a
/// post whose embed is a video.
///
/// Captions live on `app.bsky.embed.video#main`, not on the view, so they are
/// only reachable through the record. A record that is not a post, or whose
/// embed is not a video, yields no captions.
public func videoCaptions(from post: App.Bsky.FeedDefs_PostView) -> [VideoCaptionTrack] {
  // `UnknownATPValue` carries the decoded record; Domain's `feedPostRecord`
  // accessor is internal to that package, so the cast is made locally.
  guard case .record(let anyRecord) = post.record,
    let record = anyRecord as? App.Bsky.FeedPost
  else { return [] }
  guard case .embedVideo(let embed) = record.embed else { return [] }
  guard let captions = embed.captions else { return [] }
  return captions.map {
    VideoCaptionTrack(lang: $0.lang.rawValue, blobCID: $0.file.ref.rawValue)
  }
}

/// The starting index for the pager, matching RN's `initialPostUri` handling.
///
/// RN finds the first item whose post URI matches and slices the list from
/// there, so opening a video from a link starts at that video. Note the RN
/// guard is `startingVideoIndex && startingVideoIndex > -1`, which is falsy for
/// index `0` - so an initial URI that resolves to the *first* item does not
/// slice. This port reproduces that quirk deliberately, because slicing `0` is a
/// no-op anyway: the visible result is identical.
///
/// - Returns: the index to start from, always a valid index into `items`.
public func startingVideoIndex(for items: [VideoItem], initialPostURI: String?) -> Int {
  guard let initialPostURI else { return 0 }
  let index = items.firstIndex { $0.postURI == initialPostURI } ?? 0
  return max(0, min(index, max(0, items.count - 1)))
}

/// The pager's item list for a run, applying the `initialPostUri` offset.
///
/// Port of the `vids.slice(startingVideoIndex)` in `src/screens/VideoFeed`.
/// An initial URI that is not in the list leaves the list untouched.
public func videoPagerItems(
  _ items: [VideoItem], initialPostURI: String?
) -> [VideoItem] {
  guard let initialPostURI else { return items }
  guard let index = items.firstIndex(where: { $0.postURI == initialPostURI }) else {
    return items
  }
  return Array(items[index...])
}
