import Foundation
import QueryStore

/// The query-key map for the profile feature.
///
/// Ports the key constructors and key roots from the RN query modules:
/// `src/state/queries/profile.ts`, `profile-follows.ts`, `profile-followers.ts`,
/// `known-followers.ts`, `labeler.ts` and the `post-feed` root the author feeds
/// share.
///
/// Every key carries the signed-in account as its `scope`, which is how a single
/// Swift ``QueryStore`` reproduces the RN app re-keying the whole `QueryClient`
/// on `currentDid`.
public enum ProfileQueryKeys {

  // MARK: - Key roots

  /// Root of the single-profile query. RN: `const RQKEY_ROOT = 'profile'`.
  public static let profile = "profile"
  /// Root of the multi-profile query. RN: `profilesQueryKeyRoot`.
  public static let profiles = "profiles"
  /// Root shared by every author-feed variant. RN: `RQKEY_ROOT = 'post-feed'`.
  public static let postFeed = "post-feed"
  /// Root of the follows list. RN: `const RQKEY_ROOT = 'profile-follows'`.
  public static let follows = "profile-follows"
  /// Root of the followers list. RN: `const RQKEY_ROOT = 'profile-followers'`.
  public static let followers = "profile-followers"
  /// Root of the known-followers list. RN: `const RQKEY_ROOT =
  /// 'profile-known-followers'`.
  public static let knownFollowers = "profile-known-followers"
  /// Root of the single-labeler query. RN: `labelerInfoQueryKeyRoot`.
  public static let labelerInfo = "labeler-info"
  /// Root of the multi-labeler query. RN: `labelersInfoQueryKeyRoot`.
  public static let labelersInfo = "labelers-info"
  /// Root of the detailed multi-labeler query. RN:
  /// `createLabelersDetailedInfoQueryKey`'s `'labelers-detailed-info'`.
  public static let labelersDetailedInfo = "labelers-detailed-info"

  // MARK: - Argument types

  /// Arguments of the single-profile query. RN: `RQKEY = (did) => [root, did]`.
  public struct ProfileArgs: QueryArgs {
    public let did: String
    public init(did: String) { self.did = did }
  }

  /// Arguments of the multi-profile query. RN: `[profilesQueryKeyRoot, handles]`.
  public struct ProfilesArgs: QueryArgs {
    public let handles: [String]
    public init(handles: [String]) { self.handles = handles }
  }

  /// Arguments of an author-feed query. RN: the `post-feed` key's
  /// `feedDesc` plus its `FeedParams`.
  public struct AuthorFeedArgs: QueryArgs {
    /// The profile whose feed this is.
    public let actor: String
    /// Which tab's filter this entry holds.
    public let tab: ProfileTab
    public init(actor: String, tab: ProfileTab) {
      self.actor = actor
      self.tab = tab
    }
  }

  /// Arguments of a follows or followers list. RN:
  /// `RQKEY = (did, sort) => [root, did, sort]`.
  public struct FollowListArgs: QueryArgs {
    public let actor: String
    /// The `sort` parameter, or `nil` when the feature flag is off. RN spreads
    /// the parameter in only when set, because the vendored lexicon rejects an
    /// undeclared key whose value is `undefined`.
    public let sort: ActorListSort?
    public init(actor: String, sort: ActorListSort? = nil) {
      self.actor = actor
      self.sort = sort
    }
  }

  /// Arguments of the known-followers list. RN: `RQKEY = (did) => [root, did]`.
  public struct KnownFollowersArgs: QueryArgs {
    public let actor: String
    public init(actor: String) { self.actor = actor }
  }

  /// Arguments of the single-labeler query.
  public struct LabelerArgs: QueryArgs {
    public let did: String
    public init(did: String) { self.did = did }
  }

  /// Arguments of a multi-labeler query. RN sorts the DID list before it
  /// becomes the key, so two orderings of the same set share one entry.
  public struct LabelersArgs: QueryArgs {
    /// The DIDs, sorted. RN: `dids.slice().sort()`.
    public let dids: [String]
    public init(dids: [String]) { self.dids = dids.sorted() }
  }

  // MARK: - Key constructors

  /// Key of the single-profile query, scoped to the signed-in account.
  public static func profile(did: String, scope: String? = nil) -> QueryKey {
    QueryKey(profile, ProfileArgs(did: did), options: QueryOptions(scope: scope))
  }

  /// Key of the multi-profile query.
  public static func profiles(handles: [String], scope: String? = nil) -> QueryKey {
    QueryKey(profiles, ProfilesArgs(handles: handles), options: QueryOptions(scope: scope))
  }

  /// Key of one profile tab's author feed.
  public static func authorFeed(actor: String, tab: ProfileTab, scope: String? = nil) -> QueryKey {
    QueryKey(
      postFeed, AuthorFeedArgs(actor: actor, tab: tab), options: QueryOptions(scope: scope))
  }

  /// Key of the follows list for `actor`.
  public static func follows(actor: String, sort: ActorListSort? = nil, scope: String? = nil)
    -> QueryKey
  {
    QueryKey(follows, FollowListArgs(actor: actor, sort: sort), options: QueryOptions(scope: scope))
  }

  /// Key of the followers list for `actor`.
  public static func followers(actor: String, sort: ActorListSort? = nil, scope: String? = nil)
    -> QueryKey
  {
    QueryKey(followers, FollowListArgs(actor: actor, sort: sort), options: QueryOptions(scope: scope))
  }

  /// Key of the known-followers list for `actor`.
  public static func knownFollowers(actor: String, scope: String? = nil) -> QueryKey {
    QueryKey(knownFollowers, KnownFollowersArgs(actor: actor), options: QueryOptions(scope: scope))
  }

  /// Key of the single-labeler query.
  public static func labelerInfo(did: String, scope: String? = nil) -> QueryKey {
    QueryKey(labelerInfo, LabelerArgs(did: did), options: QueryOptions(scope: scope))
  }

  /// Key of the multi-labeler query.
  public static func labelersInfo(dids: [String], scope: String? = nil) -> QueryKey {
    QueryKey(labelersInfo, LabelersArgs(dids: dids), options: QueryOptions(scope: scope))
  }

  /// Key of the detailed multi-labeler query, persisted at version 1 as RN does.
  public static func labelersDetailedInfo(dids: [String], scope: String? = nil) -> QueryKey {
    QueryKey(
      labelersDetailedInfo, LabelersArgs(dids: dids),
      options: QueryOptions(scope: scope, persistedVersion: 1))
  }
}
