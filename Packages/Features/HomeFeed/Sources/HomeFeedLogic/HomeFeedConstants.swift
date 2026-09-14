import Foundation
import QueryStore

/// Constants ported from the RN feed pipeline.
///
/// Sources: `src/state/queries/post-feed.ts` (`MIN_POSTS`),
/// `src/view/com/posts/PostFeed.tsx` (`CHECK_LATEST_AFTER`, `pollInterval`),
/// `src/state/queries/feed.ts` (staleness budgets) and
/// `src/state/queries/index.ts` (`STALE`).
public enum HomeFeedConstants {
  /// The minimum number of posts a single page should yield.
  ///
  /// Port of `MIN_POSTS` in `src/state/queries/post-feed.ts`. The RN query
  /// filters unwanted content after fetching, so it over-fetches by asking for
  /// this many to make sure at least this many survive.
  public static let minPosts = 30

  /// Items to request per page. RN sets `fetchLimit = MIN_POSTS`.
  public static let fetchLimit = 30

  /// How long a feed stays usable before the poller is willing to check the
  /// appview for newer content. Port of `CHECK_LATEST_AFTER`, itself
  /// `STALE.SECONDS.THIRTY`, in `src/view/com/posts/PostFeed.tsx`.
  public static let checkLatestAfter: TimeInterval = STALE.SECONDS.THIRTY

  /// The default timer between "is there anything new" polls, in seconds.
  ///
  /// RN passes `pollInterval={60e3}` from the custom-feed and list screens
  /// (`src/screens/CustomFeed/index.tsx`, `src/screens/ProfileList/FeedSection.tsx`).
  public static let defaultPollInterval: TimeInterval = 60

  /// Cap on pages fetched while filling a page with `MIN_POSTS` content. RN
  /// passes `MIN_POSTS` as the auto-pagination target and QueryStore caps the
  /// walk at five extra pages.
  public static let autoPaginationMaxAttempts = QueryStore.autoPaginationMaxAttempts

  /// The count of posts requested when peeking at the head of a feed.
  /// Port of `peekLatest`'s `limit: 1`.
  public static let peekLatestLimit = 1

  /// The limit used when hydrating a saved list. Port of `getList`'s
  /// `limit: 1` in `src/state/queries/feed.ts`.
  public static let listHydrationLimit = 1
}

/// Staleness budgets used by the home feed queries.
///
/// The RN post-feed query is `STALE.INFINITY` because a feed is refreshed
/// explicitly (`truncateAndInvalidate`) instead of by time; the pinned-feed
/// metadata queries use fifteen minutes and infinity respectively.
public enum HomeFeedStale {
  /// `usePostFeedQuery` -> `staleTime: STALE.INFINITY`.
  public static let feedPage: TimeInterval = STALE.INFINITY
  /// `usePinnedFeedsInfos` -> `staleTime: STALE.MINUTES.FIFTEEN`.
  public static let pinnedFeeds: TimeInterval = STALE.MINUTES.FIFTEEN
  /// `useSavedFeeds` -> `staleTime: STALE.INFINITY`.
  public static let savedFeeds: TimeInterval = STALE.INFINITY
  /// `useFeedSourceInfoQuery` -> `staleTime: STALE.INFINITY`.
  public static let feedSourceInfo: TimeInterval = STALE.INFINITY
}
