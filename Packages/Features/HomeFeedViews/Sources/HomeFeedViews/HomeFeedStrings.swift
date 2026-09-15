import Foundation

/**
 The Home feed's user-facing copy, in one place.

 The repo's i18n story (Lingui, `.xcstrings`) belongs to the RN app and is not
 ported yet; this seam is the Swift stand-in the plan calls for. Every string a
 Home feed surface can render is a constant here, so a later `.xcstrings`
 migration rewrites one file instead of hunting literals across the views, and
 so the demo fixtures and the real screen share the same copy by construction.

 Wording follows `src/view/com/posts/PostFeedReason.tsx`,
 `src/view/com/posts/FollowingEmptyState.tsx` and `src/screens/Home/NoFeedsPinned.tsx`.
 */
public enum HomeFeedStrings {
  // MARK: - Feed switcher

  /// The switcher's accessibility label.
  public static let feedSwitcherLabel = "Feeds"

  /// The fallback label for a pinned feed with no resolved display name.
  public static let unnamedFeed = "Feed"

  // MARK: - Reason lines

  /// The repost attribution line, RN's `Reposted by <name>`.
  public static func repostedBy(_ name: String) -> String {
    "Reposted by \(name)"
  }

  /// The repost line when the viewer is the reposter, RN's `Reposted by you`.
  public static let repostedByYou = "Reposted by you"

  /// The pinned-post line, RN's `Pinned`.
  public static let pinned = "Pinned"

  /// The context line for a thread slice whose parent is not in the slice,
  /// RN's `Replying to @handle`.
  public static func replyingTo(_ handle: String) -> String {
    "@\(handle)"
  }

  // MARK: - New-posts pill

  /// The pill shown when the feed has unseen content.
  public static let newPosts = "New posts"

  /// The pill's accessibility hint.
  public static let newPostsHint = "Scrolls to the top of the feed"

  // MARK: - Loading

  /// The skeleton list's accessibility label.
  public static let loading = "Loading"

  /// The trailing spinner's accessibility label.
  public static let loadingMore = "Loading more"

  /// The inline pagination failure row.
  public static let loadMoreFailed = "Could not load more"

  /// The pagination retry button.
  public static let retry = "Retry"

  // MARK: - Empty states

  /// The empty following-timeline title.
  public static let emptyFollowingTitle = "Your following feed is empty"

  /// The empty following-timeline body, RN's `FollowingEmptyState`.
  public static let emptyFollowingMessage =
    "Follow more users to see what's happening. Try searching for people you know, or browse a suggested feed."

  /// The empty non-timeline feed title.
  public static let emptyFeedTitle = "This feed is empty"

  /// The empty non-timeline feed body.
  public static let emptyFeedMessage = "There are no posts in this feed right now."

  /// The action that refetches an empty feed.
  public static let emptyRefreshAction = "Refresh"

  /// The title shown when the account has no pinned feeds.
  public static let noFeedsTitle = "No feeds pinned"

  /// The body shown when the account has no pinned feeds.
  public static let noFeedsMessage =
    "Pin feeds to your Home tab to keep them at the top of the app."

  /// RN's `NoFeedsPinned` primary action.
  public static let noFeedsAction = "Add recommended feeds"

  // MARK: - Logged out

  /// The title shown with no session.
  public static let loggedOutTitle = "Sign in to see your feed"

  /// The body shown with no session.
  public static let loggedOutMessage =
    "Your Home feed follows the accounts you follow. Sign in to load it."

  /// The logged-out call to action.
  public static let loggedOutAction = "Sign in"

  // MARK: - Errors

  /// The offline error title, RN's `PostFeedErrorMessage` network branch.
  public static let errorNetworkTitle = "Could not connect"

  /// The offline error body.
  public static let errorNetworkMessage =
    "Check your internet connection and try again."

  /// The service-error title.
  public static let errorServiceTitle = "Could not load this feed"

  /// The service-error body when the appview gave no message.
  public static let errorServiceMessage = "Something went wrong loading this feed."

  /// The signed-in-only title, RN's `FeedSignedInOnly`.
  public static let errorSignedInOnlyTitle = "Sign in to view this feed"

  /// The signed-in-only body.
  public static let errorSignedInOnlyMessage =
    "This feed is only available to signed-in accounts."

  /// The fallback error title.
  public static let errorUnknownTitle = "Something went wrong"

  /// The fallback error body.
  public static let errorUnknownMessage = "The feed could not be loaded."

  /// The action that retries a failed load.
  public static let errorRetryAction = "Try again"
}
