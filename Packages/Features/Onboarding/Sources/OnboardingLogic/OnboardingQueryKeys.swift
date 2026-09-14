import Foundation
import QueryStore

/// Query keys for the onboarding suggestion endpoints.
///
/// Port of the two suggestion queries the RN flow uses:
/// `useSuggestedOnboardingUsers` / `useGetSuggestedOnboardingUsersQuery`
/// (root `unspecced-suggested-onboarding-users`) and
/// `useOnboardingSuggestedStarterPacksQuery` (root
/// `onboarding-suggested-starter-packs`).
public enum OnboardingQueryKeys {

  /// Root for `app.bsky.unspecced.getSuggestedOnboardingUsers`.
  public static let suggestedUsersRoot = "unspecced-suggested-onboarding-users"
  /// Root for `app.bsky.unspecced.getSuggestedOnboardingStarterPacks`.
  public static let suggestedStarterPacksRoot = "onboarding-suggested-starter-packs"

  /// Arguments for the suggested-users query.
  ///
  /// RN keys on `[root, category, limit, overrideInterests.join(',')]`. The
  /// interests are joined into one string here for the same reason: an array
  /// argument would make `["art","music"]` and `["music","art"]` distinct
  /// cache entries for one server answer.
  public struct SuggestedUsersArgs: QueryArgs {
    /// The interest category, or nil for the default tab.
    public let category: String?
    /// The page limit.
    public let limit: Int?
    /// The interests to send as the `X-Bsky-Topics` header, joined.
    public let overrideInterests: String

    /// Creates the args.
    public init(category: String? = nil, limit: Int? = nil, overrideInterests: [String] = []) {
      self.category = category
      self.limit = limit
      self.overrideInterests = overrideInterests.joined(separator: ",")
    }
  }

  /// Arguments for the suggested-starter-packs query.
  public struct SuggestedStarterPacksArgs: QueryArgs {
    /// The interests to send as the `X-Bsky-Topics` header, joined.
    public let overrideInterests: String

    /// Creates the args.
    public init(overrideInterests: [String] = []) {
      self.overrideInterests = overrideInterests.joined(separator: ",")
    }
  }

  /// The suggested-users key.
  public static func suggestedUsers(
    category: String? = nil, limit: Int? = nil, overrideInterests: [String] = [],
    scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      suggestedUsersRoot,
      SuggestedUsersArgs(
        category: category, limit: limit, overrideInterests: overrideInterests),
      options: QueryOptions(scope: scope))
  }

  /// The suggested-starter-packs key.
  public static func suggestedStarterPacks(
    overrideInterests: [String] = [], scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      suggestedStarterPacksRoot,
      SuggestedStarterPacksArgs(overrideInterests: overrideInterests),
      options: QueryOptions(scope: scope))
  }

  /// The limit RN requests for each onboarding suggestion call.
  ///
  /// `StepSuggestedAccounts` uses the hook's default of 10;
  /// `useOnboardingSuggestedStarterPacksQuery` passes 6 explicitly.
  public static let suggestedUsersLimit = 10
  /// The starter-packs limit.
  public static let suggestedStarterPacksLimit = 6

  /// The header carrying the topic interests.
  ///
  /// `createBskyTopicsHeader` in `lib/api/feed/utils.ts`.
  public static func topicsHeader(_ interests: [String]) -> [String: String] {
    ["X-Bsky-Topics": interests.joined(separator: ",")]
  }
}
