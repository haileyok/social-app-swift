import Foundation
import Lexicons

/// Builds the Explore page model from the unspecced endpoint responses.
///
/// Ported from the module `useMemo` blocks in `screens/Search/Explore.tsx`.
/// Each `build…` function corresponds to one RN module and reproduces its
/// de-dupe, slice and error branches exactly:
///
/// - `suggestedFollowsModule` dedupes by DID and drops accounts the viewer
///   already follows, then truncates to 5 on the default "For You" tab.
/// - `suggestedFeedsModule` dedupes by URI and shows 6 rows until "load more"
///   is pressed.
/// - `suggestedStarterPacksModule` drops the whole section (header included) on
///   error rather than showing an error row.
/// - `feedPreviewsModule` is a passthrough - the previews come from a separate
///   query this package does not own.
///
/// The RN screen mixes presentation-only rows (borders, banners, placeholders)
/// into the same array. Those have no data dependency, so the models here cover
/// the data-bearing rows and the assembly keeps section order.
public enum ExploreAssembly {
  /// The default "For You" tab shows only this many suggested accounts.
  public static let suggestedAccountsForYouLimit = 5
  /// The number of suggested feeds shown before "load more".
  public static let suggestedFeedsInitialLimit = 6
  /// The number of starter-pack skeletons shown while loading.
  public static let starterPackSkeletonCount = 3

  /// Inputs to the assembly, one optional response per Explore query.
  ///
  /// Every field being optional is load-bearing: the RN screen distinguishes
  /// "still loading" from "loaded empty" and picks a different row for each.
  public struct Input {
    /// `getTrendingTopics` output, or `nil` when not loaded.
    public var trendingTopics: App.Bsky.UnspeccedGetTrendingTopics_Output?
    /// The trending-video rows, already sliced by the caller.
    public var trendingVideos: [App.Bsky.UnspeccedDefs_TrendView]?
    /// `getSuggestedUsersForExplore` output, or `nil` when not loaded.
    public var suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output?
    /// `getSuggestedFeeds` output, or `nil` when not loaded.
    public var suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output?
    /// `getPopularFeedGenerators` pages, flattened by the caller.
    public var popularFeeds: [App.Bsky.FeedDefs_GeneratorView]?
    /// `getSuggestedStarterPacks` output, or `nil` when not loaded.
    public var suggestedStarterPacks: App.Bsky.UnspeccedGetSuggestedStarterPacks_Output?
    /// The feed-preview rows owned by the feed-previews query.
    public var feedPreviews: [ExploreItem]
    /// Whether the full-experience modules should be included.
    public var useFullExperience: Bool
    /// Whether the user pressed "load more" on the feeds section.
    public var hasPressedLoadMoreFeeds: Bool
    /// Whether a feeds load-more is in flight.
    public var isLoadingMoreFeeds: Bool
    /// Whether an error occurred loading suggested feeds.
    public var suggestedFeedsError: String?
    /// Whether an error occurred loading suggested users.
    public var suggestedUsersError: String?
    /// Whether an error occurred loading suggested starter packs.
    public var suggestedStarterPacksError: String?
    /// Whether an error occurred loading the selected interest category.
    public var selectedInterest: String?

    public init(
      trendingTopics: App.Bsky.UnspeccedGetTrendingTopics_Output? = nil,
      trendingVideos: [App.Bsky.UnspeccedDefs_TrendView]? = nil,
      suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output? = nil,
      suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output? = nil,
      popularFeeds: [App.Bsky.FeedDefs_GeneratorView]? = nil,
      suggestedStarterPacks: App.Bsky.UnspeccedGetSuggestedStarterPacks_Output? = nil,
      feedPreviews: [ExploreItem] = [],
      useFullExperience: Bool = true,
      hasPressedLoadMoreFeeds: Bool = false,
      isLoadingMoreFeeds: Bool = false,
      suggestedFeedsError: String? = nil,
      suggestedUsersError: String? = nil,
      suggestedStarterPacksError: String? = nil,
      selectedInterest: String? = nil
    ) {
      self.trendingTopics = trendingTopics
      self.trendingVideos = trendingVideos
      self.suggestedUsers = suggestedUsers
      self.suggestedFeeds = suggestedFeeds
      self.popularFeeds = popularFeeds
      self.suggestedStarterPacks = suggestedStarterPacks
      self.feedPreviews = feedPreviews
      self.useFullExperience = useFullExperience
      self.hasPressedLoadMoreFeeds = hasPressedLoadMoreFeeds
      self.isLoadingMoreFeeds = isLoadingMoreFeeds
      self.suggestedFeedsError = suggestedFeedsError
      self.suggestedUsersError = suggestedUsersError
      self.suggestedStarterPacksError = suggestedStarterPacksError
      self.selectedInterest = selectedInterest
    }
  }

  /// Assembles the whole page.
  ///
  /// Section order matches the RN `items` memo: trending, suggested feeds,
  /// suggested accounts, starter packs, feed previews. Without the full
  /// experience only suggested accounts are rendered.
  public static func build(_ input: Input) -> ExplorePageData {
    var sections: [ExploreSection] = []
    if input.useFullExperience {
      if let trending = buildTrending(input) { sections.append(trending) }
      if let feeds = buildSuggestedFeeds(input) { sections.append(feeds) }
    }
    if let accounts = buildSuggestedAccounts(input) { sections.append(accounts) }
    if input.useFullExperience {
      if let packs = buildStarterPacks(input) { sections.append(packs) }
      let previews = buildFeedPreviews(input)
      if !previews.items.isEmpty { sections.append(previews) }
    }
    return ExplorePageData(sections: sections, recId: input.suggestedUsers?.recIdStr)
  }

  /// Builds the trending module.
  ///
  /// The RN `ExploreTrendingTopics` module returns `null` (renders nothing) when
  /// there is no data; this returns `nil` for the same reason. Unlike
  /// suggested-follows, an empty trend list is not an error row - it hides the
  /// module.
  public static func buildTrending(_ input: Input) -> ExploreSection? {
    var items: [ExploreItem] = []
    if let topics = input.trendingTopics {
      items.append(contentsOf: topics.topics.map { ExploreItem.trendingTopic($0) })
    }
    if let videos = input.trendingVideos, !videos.isEmpty {
      items.append(contentsOf: videos.map { ExploreItem.trendingVideo($0) })
    }
    guard !items.isEmpty else { return nil }
    return ExploreSection(title: .trending, items: items)
  }

  /// Builds the suggested-accounts module.
  ///
  /// Mirrors the RN branches: a load error yields an error row, missing data
  /// yields an empty profile list, and a populated list dedupes by DID, drops
  /// followed accounts, and truncates to 5 on the default tab.
  public static func buildSuggestedAccounts(_ input: Input) -> ExploreSection? {
    var items: [ExploreItem] = []
    if let error = input.suggestedUsersError {
      items.append(
        .error(ExploreSectionError(message: "Failed to load suggested follows", error: error)))
      return ExploreSection(title: .suggestedAccounts, items: items)
    }
    guard let users = input.suggestedUsers else {
      return ExploreSection(title: .suggestedAccounts, items: items)
    }
    let profiles = dedupeProfiles(users.actors, recId: users.recIdStr)
    // The first "For You" tab only shows 5 to keep the screen short.
    if input.selectedInterest == nil, input.useFullExperience {
      items.append(contentsOf: profiles.prefix(suggestedAccountsForYouLimit).map(ExploreItem.profile))
    } else {
      items.append(contentsOf: profiles.map(ExploreItem.profile))
    }
    return ExploreSection(title: .suggestedAccounts, items: items)
  }

  /// Dedupes suggested profiles by DID, dropping accounts already followed.
  ///
  /// The RN comment is explicit: "Currently the responses contain duplicate
  /// items. Needs to be fixed on backend, but let's dedupe to be safe." The
  /// `following` check stays even when the search fallback supplied the data.
  public static func dedupeProfiles(
    _ actors: [App.Bsky.ActorDefs_ProfileView], recId: String? = nil
  ) -> [ExploreRecommendedProfile] {
    var seen = Set<String>()
    var profiles: [ExploreRecommendedProfile] = []
    for actor in actors {
      let did = actor.did.rawValue
      guard seen.insert(did).inserted else { continue }
      guard actor.viewer?.following == nil else { continue }
      profiles.append(ExploreRecommendedProfile(profile: actor, recId: recId))
    }
    return profiles
  }

  /// Builds the suggested-feeds module.
  ///
  /// With the full experience the section uses `getSuggestedFeeds` (deduped by
  /// URI and sliced to 6 until "load more"); otherwise it falls back to the
  /// popular-feed pages. Returns `nil` when no feeds are available at all, which
  /// drops the header too - the same `i.pop()` the RN module does.
  public static func buildSuggestedFeeds(_ input: Input) -> ExploreSection? {
    var items: [ExploreItem] = []
    if input.useFullExperience {
      if let error = input.suggestedFeedsError {
        items.append(
          .error(ExploreSectionError(message: "Failed to load suggested feeds", error: error)))
        return ExploreSection(title: .suggestedFeeds, items: items)
      }
      guard let feeds = input.suggestedFeeds else { return nil }
      let deduped = dedupeFeeds(feeds.feeds)
      guard !deduped.isEmpty else { return nil }
      if input.hasPressedLoadMoreFeeds {
        items.append(contentsOf: deduped.map(ExploreItem.feed))
      } else {
        items.append(
          contentsOf: deduped.prefix(suggestedFeedsInitialLimit).map(ExploreItem.feed))
        items.append(
          .loadMore(
            ExploreLoadMore(
              message: "Load more suggested feeds", isLoadingMore: input.isLoadingMoreFeeds)))
      }
      return ExploreSection(title: .suggestedFeeds, items: items)
    }
    guard let feeds = input.popularFeeds, !feeds.isEmpty else { return nil }
    items.append(contentsOf: dedupeFeeds(feeds).map(ExploreItem.feed))
    return ExploreSection(title: .suggestedFeeds, items: items)
  }

  /// Dedupes feed generators by URI, preserving order.
  public static func dedupeFeeds(
    _ feeds: [App.Bsky.FeedDefs_GeneratorView]
  ) -> [App.Bsky.FeedDefs_GeneratorView] {
    var seen = Set<String>()
    return feeds.filter { seen.insert($0.uri.rawValue).inserted }
  }

  /// Builds the starter-packs module.
  ///
  /// On error or a missing response the RN module pops the header, so the whole
  /// section disappears rather than showing an error; this returns `nil`.
  public static func buildStarterPacks(_ input: Input) -> ExploreSection? {
    guard let packs = input.suggestedStarterPacks, !packs.starterPacks.isEmpty else { return nil }
    return ExploreSection(
      title: .starterPacks, items: packs.starterPacks.map(ExploreItem.starterPack))
  }

  /// Builds the feed-previews section from rows owned by another query.
  ///
  /// Always non-nil; the caller decides whether to append it.
  public static func buildFeedPreviews(_ input: Input) -> ExploreSection {
    ExploreSection(title: .feedPreviews, items: input.feedPreviews)
  }
}
