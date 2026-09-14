import Foundation
import QueryStore

/// Query-key builders for the immersive video feed.
///
/// The video feed is a saved feed of type `feed` pointing at the "thevids"
/// generator, so it reuses the home feed's `post-feed` key root and its
/// `FeedArgs` shape: RN's `RQKEY(feedDesc, params)` does not distinguish the two
/// screens, and keeping one root means a feed fetched on Home and opened
/// immersively shares one cache entry.
///
/// Source: `RQKEY_ROOT` / `RQKEY` in `src/state/queries/post-feed.ts` plus the
/// `feedCacheKey` / `sourceInterstitial` parameter in
/// `src/screens/VideoFeed/index.tsx`.
public enum VideoFeedKeys {
  /// Root for video-feed pages. RN: `RQKEY_ROOT = 'post-feed'`.
  public static let feedRoot = "post-feed"
  /// Root for the video feed's generator metadata read.
  public static let feedInfoRoot = "feedInfo"

  /// Args for a video-feed page key.
  ///
  /// RN's `FeedParams` carries `feedCacheKey` (the interstitial that opened the
  /// feed) and `mergeFeedEnabled`; both belong in the key because they select a
  /// distinct cache entry in RN's `usePostFeedQuery`.
  public struct FeedArgs: QueryArgs {
    /// The descriptor string (`feedgen|…` or `author|…|…`).
    public let descriptor: String
    /// RN's `params.feedCacheKey`, set to the source interstitial.
    public let feedCacheKey: String?
    /// RN's `params.mergeFeedEnabled`.
    public let mergeFeedEnabled: Bool

    public init(
      descriptor: String, feedCacheKey: String? = nil, mergeFeedEnabled: Bool = false
    ) {
      self.descriptor = descriptor
      self.feedCacheKey = feedCacheKey
      self.mergeFeedEnabled = mergeFeedEnabled
    }
  }

  /// The key for a video feed's pages.
  ///
  /// - Parameters:
  ///   - source: the resolved feed source.
  ///   - feedCacheKey: the source interstitial that opened the feed, matching
  ///     RN's `params.sourceInterstitial` pass-through.
  ///   - scope: account scope (the signed-in DID).
  public static func feed(
    _ source: VideoFeedSource,
    feedCacheKey: VideoFeedInterstitial? = nil,
    scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      feedRoot,
      FeedArgs(
        descriptor: source.descriptorString,
        feedCacheKey: feedCacheKey?.rawValue),
      options: QueryOptions(scope: scope))
  }

  /// Args for the generator metadata read.
  public struct FeedInfoArgs: QueryArgs {
    public let uri: String

    public init(uri: String) {
      self.uri = uri
    }
  }

  /// The key for a video feed generator's display info, RN's
  /// `[feedInfoQueryKeyRoot, feedUri]`.
  public static func feedInfo(uri: String, scope: String? = nil) -> QueryKey {
    QueryKey(
      feedInfoRoot, FeedInfoArgs(uri: uri), options: QueryOptions(scope: scope))
  }
}

/// The interstitial that opened the video feed.
///
/// Port of RN's `sourceInterstitial: 'discover' | 'explore' | 'none'`
/// (`src/screens/VideoFeed/types.ts`). It is a cache-key component because RN
/// passes it as `feedCacheKey`, so the same feed opened from two entry points
/// caches separately - which is what makes the "from Discover" attribution
/// survive.
public enum VideoFeedInterstitial: String, Sendable, Hashable, CaseIterable {
  case discover
  case explore
  case none

  /// The value RN passes when the feed was opened directly.
  public static let direct = VideoFeedInterstitial.none
}
