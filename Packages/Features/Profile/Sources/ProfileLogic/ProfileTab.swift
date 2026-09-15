import Lexicons

/// The sort order shared by the follows and followers lists.
public enum ActorListSort: String, Sendable, Hashable, CaseIterable {
  case latest
  case top
}

/// One tab of a profile screen, and the exact `getAuthorFeed` request it makes.
///
/// Ports the tab set and its feed descriptors from `src/view/screens/Profile.tsx`
/// and the `AuthorFeedAPI` parameter derivation in `src/lib/api/feed/author.ts`.
///
/// The RN app names the descriptor `author|<did>|<filter>` and splits it back
/// apart in `createApi`; the `likes|<did>` descriptor routes to `LikesFeedAPI`
/// instead, which is why ``likes`` carries no filter.
public enum ProfileTab: String, Sendable, Hashable, CaseIterable {
  /// `author|<did>|posts_and_author_threads`.
  case posts
  /// `author|<did>|posts_with_replies`.
  case replies
  /// `author|<did>|posts_with_media`.
  case media
  /// `author|<did>|posts_with_video`.
  case videos
  /// `likes|<did>` - a different endpoint entirely.
  case likes

  /// The `getAuthorFeed` `filter` parameter, or `nil` for ``likes``.
  ///
  /// `posts` maps to `posts_and_author_threads`, which is the filter the RN
  /// profile passes for its posts tab, *not* `posts_no_replies`.
  public var authorFeedFilter: App.Bsky.FeedGetAuthorFeed_Filter? {
    switch self {
    case .posts: .postsAndAuthorThreads
    case .replies: .postsWithReplies
    case .media: .postsWithMedia
    case .videos: .postsWithVideo
    case .likes: nil
    }
  }

  /// The `includePins` parameter.
  ///
  /// `AuthorFeedAPI.params` sets `includePins` to whether the filter is
  /// `posts_and_author_threads`, so only ``posts`` asks for pins. ``likes``
  /// has no filter and so never does.
  public var includePins: Bool {
    authorFeedFilter == .postsAndAuthorThreads
  }

  /// True when this tab is served by `getAuthorFeed` rather than
  /// `getActorLikes`.
  public var usesAuthorFeed: Bool { self != .likes }

  /// True when the tab needs a signed-in session to be useful. RN gates only
  /// the replies tab on `hasSession` (likes are gated on being the profile
  /// owner instead).
  public var requiresSession: Bool { self == .replies }

  /// The page size a tab's feed requests.
  ///
  /// `post-feed.ts` sets `fetchLimit = MIN_POSTS = 30` for every descriptor,
  /// `likes` included.
  public var pageSize: Int { 30 }
}

/// One fully-resolved feed request: everything a page fetch needs.
///
/// This is the Swift form of `AuthorFeedAPI.params` / `LikesFeedAPI.params`
/// after the descriptor has been split and `includePins` has been derived.
public struct ProfileFeedRequest: Sendable, Equatable {
  /// The profile the feed belongs to.
  public let actor: String
  /// The tab that produced this request.
  public let tab: ProfileTab
  /// `getAuthorFeed` filter, absent for ``ProfileTab/likes``.
  public let filter: App.Bsky.FeedGetAuthorFeed_Filter?
  /// `includePins`, derived from the filter.
  public let includePins: Bool
  /// The endpoint this request targets.
  public let endpoint: String

  /// Derives the request for one tab.
  public init(actor: String, tab: ProfileTab) {
    self.actor = actor
    self.tab = tab
    self.filter = tab.authorFeedFilter
    self.includePins = tab.includePins
    self.endpoint = tab.usesAuthorFeed ? App.Bsky.FeedGetAuthorFeed.id : App.Bsky.FeedGetActorLikes.id
  }

  /// The query parameters, in the order the client emits them. A `nil` value is
  /// omitted rather than sent empty, matching `asParameters`.
  public func parameters(cursor: String?, limit: Int) -> [(String, String?)] {
    var params: [(String, String?)] = [("actor", actor)]
    if tab.usesAuthorFeed {
      params.append(("cursor", cursor))
      params.append(("filter", filter?.rawValue))
      params.append(("includePins", includePins ? "true" : "false"))
    } else {
      params.append(("cursor", cursor))
    }
    params.append(("limit", String(limit)))
    return params
  }
}
