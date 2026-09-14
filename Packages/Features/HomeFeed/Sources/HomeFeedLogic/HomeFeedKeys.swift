import Foundation
import QueryStore

/// Query-key builders for the home feed.
///
/// Ports the RN key roots so a persisted snapshot and a live key agree:
/// `post-feed` (`RQKEY` in `post-feed.ts`), `feed-info`
/// (`createPinnedFeedInfosQueryKey`, persisted at version 1), `getFeedSourceInfo`
/// and `feedInfo` in `feed.ts`, and `profile-feedgens` in
/// `profile-feedgens.ts`.
public enum HomeFeedKeys {
  /// Root for feed pages. RN: `RQKEY_ROOT = 'post-feed'`.
  public static let feedRoot = "post-feed"
  /// Root for the resolved pinned/saved feed lists. RN: `FEED_INFO_RQKEY_ROOT`.
  public static let feedInfoRoot = "feed-info"
  /// Root for a single feed source's hydrated info.
  public static let feedSourceInfoRoot = "getFeedSourceInfo"
  /// Root for a feed generator's detail read. RN: `feedInfoQueryKeyRoot`.
  public static let feedGeneratorRoot = "feedInfo"
  /// Root for a user's feed generators. RN: `profile-feedgens`.
  public static let actorFeedsRoot = "profile-feedgens"

  /// The persisted payload version RN sets on the pinned/saved feed-info keys.
  public static let feedInfoPersistedVersion = 1

  /// Args for a feed-page key. The descriptor and params form the identity, so
  /// two feeds never share a cache entry.
  public struct FeedArgs: QueryArgs {
    public let descriptor: String
    public let mergeFeedEnabled: Bool

    public init(descriptor: String, mergeFeedEnabled: Bool = false) {
      self.descriptor = descriptor
      self.mergeFeedEnabled = mergeFeedEnabled
    }
  }

  /// The key for a feed's pages, ported from `RQKEY(feedDesc, params)`.
  ///
  /// - Parameters:
  ///   - descriptor: the feed descriptor string.
  ///   - mergeFeedEnabled: the RN `params.mergeFeedEnabled` flag.
  ///   - scope: account scope (the signed-in DID). Two accounts get two entries.
  public static func feed(
    _ descriptor: FeedDescriptor,
    mergeFeedEnabled: Bool = false,
    scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      feedRoot,
      FeedArgs(descriptor: descriptor.description, mergeFeedEnabled: mergeFeedEnabled),
      options: QueryOptions(scope: scope))
  }

  /// Args for the resolved feed-info lists.
  public struct FeedInfoArgs: QueryArgs {
    /// `pinned` or `saved`, matching RN's `kind`.
    public let kind: String
    /// The saved-feed values, in stored order.
    public let feedUris: [String]

    public init(kind: String, feedUris: [String]) {
      self.kind = kind
      self.feedUris = feedUris
    }
  }

  /// The pinned/saved feed-info key, ported from
  /// `createPinnedFeedInfosQueryKey(kind, feedUris)` (persisted, version 1).
  public static func feedInfo(
    kind: HomeFeedInfoKind, feedUris: [String], scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      feedInfoRoot,
      FeedInfoArgs(kind: kind.rawValue, feedUris: feedUris),
      options: QueryOptions(scope: scope, persistedVersion: feedInfoPersistedVersion))
  }

  /// Args for a single feed source's info.
  public struct FeedSourceArgs: QueryArgs {
    public let uri: String

    public init(uri: String) {
      self.uri = uri
    }
  }

  /// A feed source's hydrated info key, ported from
  /// `feedSourceInfoQueryKey({uri})`.
  public static func feedSourceInfo(uri: String, scope: String? = nil) -> QueryKey {
    QueryKey(
      feedSourceInfoRoot, FeedSourceArgs(uri: uri),
      options: QueryOptions(scope: scope))
  }

  /// A feed generator's detail key, ported from
  /// `[feedInfoQueryKeyRoot, feedUri]`.
  public static func feedGenerator(uri: String?, scope: String? = nil) -> QueryKey {
    QueryKey(
      feedGeneratorRoot, FeedSourceArgs(uri: uri ?? ""),
      options: QueryOptions(scope: scope))
  }

  /// A user's feed generators key, ported from `profile-feedgens.ts`.
  public static func actorFeeds(actor: String, scope: String? = nil) -> QueryKey {
    QueryKey(
      actorFeedsRoot, FeedSourceArgs(uri: actor),
      options: QueryOptions(scope: scope))
  }
}

/// Which feed-info list is being resolved. RN: `kind: 'pinned' | 'saved'`.
public enum HomeFeedInfoKind: String, Sendable, Hashable {
  case pinned
  case saved
}
