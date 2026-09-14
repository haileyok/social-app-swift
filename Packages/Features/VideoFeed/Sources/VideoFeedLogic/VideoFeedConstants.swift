import Foundation
import QueryStore

/// Constants ported from the React Native immersive video feed.
///
/// Sources: `src/screens/VideoFeed/index.tsx` (viewability config, player
/// window, telemetry thresholds), `src/lib/constants.ts` (the Video feed URIs),
/// `src/lib/media/video/analytics.ts` (`PLAYBACK_START_THRESHOLD_SECONDS`) and
/// `src/state/queries/post-feed.ts` (`MIN_POSTS`, reused by the video feed's
/// page size).
public enum VideoFeedConstants {
  /// The Video feed generator URI. RN: `VIDEO_FEED_URI`.
  public static let videoFeedURI =
    "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/thevids"

  /// The staging Video feed generator URI. RN: `STAGING_VIDEO_FEED_URI`.
  public static let stagingVideoFeedURI =
    "at://did:plc:yofh3kx63drvfljkibw5zuxo/app.bsky.feed.generator/thevids"

  /// Both URIs count as "the video feed" for header/interstitial decisions.
  /// RN: `VIDEO_FEED_URIS`.
  public static let videoFeedURIs: [String] = [videoFeedURI, stagingVideoFeedURI]

  /// Items requested per page. RN reuses the feed query's `MIN_POSTS`.
  public static let fetchLimit = 30

  /// The visible-fraction threshold that makes an item active.
  ///
  /// RN's immersive feed sets `itemVisiblePercentThreshold: 100` with
  /// `minimumViewTime: 0`: only the item covering the whole viewport plays.
  public static let itemVisiblePercentThreshold = 100

  /// The minimum time an item must stay visible before it counts as active.
  /// RN: `minimumViewTime: 0`.
  public static let minimumViewTime: TimeInterval = 0

  /// How many neighbors on each side of the active item are preloaded.
  ///
  /// RN keys three pooled players off `index - 1`, `index`, `index + 1`, so the
  /// preload window is one video either side.
  public static let preloadRadius = 1

  /// The size of the RN player pool. Three players are recycled by
  /// `index % 3`.
  public static let playerPoolSize = 3

  /// Items rendered eagerly. RN: `initialNumToRender: 3`.
  public static let initialNumToRender = 3

  /// Items rendered per batch. RN: `maxToRenderPerBatch: 3`.
  public static let maxToRenderPerBatch = 3

  /// The list window size. RN: `windowSize: 6`.
  public static let windowSize = 6

  /// Playback progress, in seconds, at which a video counts as started.
  /// RN: `PLAYBACK_START_THRESHOLD_SECONDS`.
  public static let playbackStartThresholdSeconds: TimeInterval = 0.05

  /// The aspect ratio at or below which a video is "tall" (portrait) and is
  /// scaled to cover. RN: `isTallAspectRatio` compares against 9/16.
  public static let tallAspectRatioThreshold = 9.0 / 16.0
}

/// Staleness budgets for the video-feed queries.
public enum VideoFeedStale {
  /// The feed itself is never time-stale; it refreshes by explicit
  /// invalidation, matching `usePostFeedQuery`'s `STALE.INFINITY`.
  public static let feedPage: TimeInterval = STALE.INFINITY
}
