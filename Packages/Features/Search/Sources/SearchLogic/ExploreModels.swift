import Foundation
import Lexicons

/// The flattened list of rows the Explore screen renders.
///
/// Ported from the `ExploreScreenItems` union in `screens/Search/Explore.tsx`.
/// The RN screen builds the same array with `items.push(...)` calls inside
/// `useMemo` blocks; this port keeps that assembly as pure data so it can be
/// tested against fixture responses without a renderer.
///
/// Only the item kinds that come from *data* are modeled here. Purely
/// presentational rows the RN screen injects (borders, the live-events banner,
/// the interests card) have no payload and are represented by
/// ``ExploreSection`` instead, which groups items under a heading.
public enum ExploreItem: Sendable, Equatable {
  /// A recommended account.
  case profile(ExploreRecommendedProfile)
  /// A recommended feed generator.
  case feed(App.Bsky.FeedDefs_GeneratorView)
  /// A recommended starter pack.
  case starterPack(App.Bsky.GraphDefs_StarterPackView)
  /// A trending topic row (topic name, link, optional description).
  case trendingTopic(App.Bsky.UnspeccedDefs_TrendingTopic)
  /// A trending-video row (the trends endpoint's `TrendView` shape).
  case trendingVideo(App.Bsky.UnspeccedDefs_TrendView)
  /// A section-level error with the message the RN screen displays.
  case error(ExploreSectionError)
  /// A "load more" affordance for a partially-listed section.
  case loadMore(ExploreLoadMore)
}

/// A recommended profile plus the recommendation id it came from.
///
/// RN merges `recIdStr` into the payload as `recId` in the query's `select`;
/// this port carries it here instead so the raw lexicon responses stay
/// round-trippable for persistence.
public struct ExploreRecommendedProfile: Sendable, Equatable {
  public let profile: App.Bsky.ActorDefs_ProfileView
  /// The snowflake the recommendation should be reported against, if any.
  public let recId: String?

  public init(profile: App.Bsky.ActorDefs_ProfileView, recId: String? = nil) {
    self.profile = profile
    self.recId = recId
  }
}

/// A section-level failure, with the RN copy and the cleaned underlying error.
public struct ExploreSectionError: Sendable, Equatable {
  /// The user-facing message, e.g. "Failed to load suggested follows".
  public let message: String
  /// The cleaned error text (the RN `cleanError` output).
  public let error: String

  public init(message: String, error: String) {
    self.message = message
    self.error = error
  }
}

/// A "load more" row for a section that lists a truncated slice.
public struct ExploreLoadMore: Sendable, Equatable {
  /// The label, e.g. "Load more suggested feeds".
  public let message: String
  /// Whether a load is already in flight (drives the spinner).
  public let isLoadingMore: Bool

  public init(message: String, isLoadingMore: Bool) {
    self.message = message
    self.isLoadingMore = isLoadingMore
  }
}

/// A titled group of ``ExploreItem``s.
///
/// The RN screen keeps headers and items in one flat array; grouping them is
/// equivalent for rendering and makes the assembly assertions read as "which
/// sections appear, in what order, with which rows".
public struct ExploreSection: Sendable, Equatable {
  /// The section heading.
  public let title: ExploreSectionTitle
  /// The rows under the heading, in display order.
  public let items: [ExploreItem]

  public init(title: ExploreSectionTitle, items: [ExploreItem]) {
    self.title = title
    self.items = items
  }
}

/// The known Explore section headings.
///
/// `rawValue` is the stable identifier; `text` is the RN copy verbatim.
public enum ExploreSectionTitle: String, Sendable, Equatable, CaseIterable {
  case trending
  case suggestedAccounts
  case suggestedFeeds
  case starterPacks
  case feedPreviews

  /// The heading text, matching `screens/Search/Explore.tsx`.
  public var text: String {
    switch self {
    case .trending: return "Trending"
    case .suggestedAccounts: return "Suggested accounts"
    case .suggestedFeeds: return "Discover feeds"
    case .starterPacks: return "Starter Packs"
    case .feedPreviews: return "Explore"
    }
  }
}

/// The assembled Explore payload.
///
/// `useFullExperience` mirrors the RN flag of the same name: with a session the
/// screen renders trending, feeds, accounts, starter packs and previews; without
/// one only the suggested accounts survive (see `Explore.tsx`'s `items` memo).
public struct ExplorePageData: Sendable, Equatable {
  /// The sections, in render order.
  public let sections: [ExploreSection]
  /// The recommendation id from the suggested-users response, when present.
  public let recId: String?

  public init(sections: [ExploreSection], recId: String? = nil) {
    self.sections = sections
    self.recId = recId
  }

  /// Every item across every section, in render order - the flat list the RN
  /// screen's `FlatList` actually consumes.
  public var allItems: [ExploreItem] {
    sections.flatMap(\.items)
  }

  /// The section with `title`, or `nil`.
  public func section(_ title: ExploreSectionTitle) -> ExploreSection? {
    sections.first { $0.title == title }
  }

  /// The profile rows across every section, in order.
  public var profiles: [ExploreRecommendedProfile] {
    allItems.compactMap { if case .profile(let p) = $0 { p } else { nil } }
  }
}
