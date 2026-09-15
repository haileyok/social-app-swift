import Foundation

/// Where an immersive video feed gets its posts: the routing params of
/// `VideoFeedSourceContext` in `src/screens/VideoFeed/types.ts`.
///
/// The RN screen is param-driven, not a saved-feed-only screen: it either shows
/// the "thevids" feed generator or a single author's video posts. Both are
/// carried here as one value so the feed pipeline treats them identically.
public enum VideoFeedSource: Sendable, Hashable {
  /// The Video feed generator. RN: `{type: 'feedgen', uri}`.
  case feedgen(uri: String)
  /// One author's video posts. RN: `{type: 'author', did, filter}`.
  case author(did: String, filter: VideoAuthorFilter)

  /// The "Video" feed generator, RN's `VIDEO_FEED_URI`.
  public static var video: VideoFeedSource { .feedgen(uri: VideoFeedConstants.videoFeedURI) }

  /// True when this source is one of the Bluesky-owned video feed generators
  /// (`VIDEO_FEED_URIS`), which the app treats specially for interstitials and
  /// the trending-videos module.
  public var isVideoFeedGenerator: Bool {
    guard case .feedgen(let uri) = self else { return false }
    return VideoFeedConstants.videoFeedURIs.contains(uri)
  }

  /// The generator URI, when this is a generator source.
  public var feedgenURI: String? {
    if case .feedgen(let uri) = self { return uri }
    return nil
  }

  /// The feed descriptor string, exactly as RN's `useMemo` builds it.
  public var descriptorString: String {
    switch self {
    case .feedgen(let uri): return "feedgen|\(uri)"
    case .author(let did, let filter): return "author|\(did)|\(filter.rawValue)"
    }
  }

  /// The descriptor string, for the shared feed pipeline.
  ///
  /// Identical to ``descriptorString``; RN uses one string for both the key and
  /// the fetch, so this port does too.
  public var descriptor: String { descriptorString }

  /// Parses the RN descriptor string back into a source. Returns `nil` for a
  /// descriptor that is neither a video feedgen nor a video author feed.
  public init?(descriptor: String) {
    let parts = descriptor.split(separator: "|", maxSplits: 2).map(String.init)
    guard let head = parts.first else { return nil }
    switch head {
    case "feedgen" where parts.count == 2:
      self = .feedgen(uri: parts[1])
    case "author" where parts.count == 3:
      guard let filter = VideoAuthorFilter(rawValue: parts[2]) else { return nil }
      self = .author(did: parts[1], filter: filter)
    default:
      return nil
    }
  }
}

/// An author-feed filter narrow enough for the video feed.
///
/// RN types this as the full `AuthorFilter` union but the immersive screen only
/// ever receives `posts_with_video`; the other values are modelled so the
/// descriptor round-trips without loss.
public enum VideoAuthorFilter: String, Sendable, Hashable, CaseIterable {
  case postsWithReplies = "posts_with_replies"
  case postsNoReplies = "posts_no_replies"
  case postsAndAuthorThreads = "posts_and_author_threads"
  case postsWithMedia = "posts_with_media"
  case postsWithVideo = "posts_with_video"

  /// The filter the immersive video feed uses for an author.
  public static let video = VideoAuthorFilter.postsWithVideo
}
