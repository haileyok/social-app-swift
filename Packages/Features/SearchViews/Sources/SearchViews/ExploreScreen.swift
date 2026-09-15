import DesignSystem
import Foundation
import Lexicons
import SearchLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The Explore screen: one section per ``ExploreSection`` in the assembled
/// ``ExplorePageData``, in the order `SearchLogic` produced them.
///
/// The view is a render of that model and nothing else: which sections appear,
/// which rows are inside them, and where an error or "load more" row goes are
/// all decided by ``SearchLogic/ExploreAssembly``. This type only maps each
/// ``ExploreItem`` onto a row component.
public struct ExploreScreen: View {
  private let data: ExplorePageData
  private let isLoading: Bool
  private let onRetry: () -> Void
  private let onSelectProfile: (ExploreRecommendedProfile) -> Void
  private let onSelectFeed: (App.Bsky.FeedDefs_GeneratorView) -> Void
  private let onSelectStarterPack: (App.Bsky.GraphDefs_StarterPackView) -> Void
  private let onSelectTrendingTopic: (App.Bsky.UnspeccedDefs_TrendingTopic) -> Void
  private let onSelectTrendingVideo: (App.Bsky.UnspeccedDefs_TrendView) -> Void
  private let onLoadMoreFeeds: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    data: ExplorePageData,
    isLoading: Bool = false,
    onRetry: @escaping () -> Void = {},
    onSelectProfile: @escaping (ExploreRecommendedProfile) -> Void = { _ in },
    onSelectFeed: @escaping (App.Bsky.FeedDefs_GeneratorView) -> Void = { _ in },
    onSelectStarterPack: @escaping (App.Bsky.GraphDefs_StarterPackView) -> Void = { _ in },
    onSelectTrendingTopic: @escaping (App.Bsky.UnspeccedDefs_TrendingTopic) -> Void = { _ in },
    onSelectTrendingVideo: @escaping (App.Bsky.UnspeccedDefs_TrendView) -> Void = { _ in },
    onLoadMoreFeeds: @escaping () -> Void = {}
  ) {
    self.data = data
    self.isLoading = isLoading
    self.onRetry = onRetry
    self.onSelectProfile = onSelectProfile
    self.onSelectFeed = onSelectFeed
    self.onSelectStarterPack = onSelectStarterPack
    self.onSelectTrendingTopic = onSelectTrendingTopic
    self.onSelectTrendingVideo = onSelectTrendingVideo
    self.onLoadMoreFeeds = onLoadMoreFeeds
  }

  public var body: some View {
    Group {
      if isLoading, data.sections.isEmpty {
        ListSkeleton()
      } else if data.sections.isEmpty {
        EmptyStateView(
          strings: ListStrings(
            emptyTitle: SearchCopy.exploreEmptyTitle,
            emptyMessage: SearchCopy.exploreEmptyMessage,
            errorTitle: SearchCopy.resultsErrorTitle,
            errorMessage: SearchCopy.resultsErrorMessage,
            retryLabel: SearchCopy.retryAction),
          icon: "sparkles",
          actionLabel: SearchCopy.retryAction,
          action: onRetry)
      } else {
        sectionList
      }
    }
    .accessibilityIdentifier(SearchAccessibility.exploreList)
  }

  private var sectionList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(data.sections, id: \.title.rawValue) { section in
          heading(for: section.title)
          ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
            row(for: item)
          }
        }
      }
    }
  }

  private func heading(for title: ExploreSectionTitle) -> some View {
    AlfText(
      SearchCopy.heading(for: title), scale: .lg, weight: Scales.FontWeight.semiBold
    )
    .padding(.md, .horizontal)
    .padding(.top, Spacing.lg)
    .padding(.bottom, Spacing.xs)
  }

  @ViewBuilder
  private func row(for item: ExploreItem) -> some View {
    switch item {
    case .profile(let recommended):
      SearchProfileRow(
        profile: recommended.profile, onSelect: { onSelectProfile(recommended) })
    case .feed(let feed):
      SearchFeedRow(feed: feed, onSelect: { onSelectFeed(feed) })
    case .starterPack(let pack):
      SearchStarterPackRow(pack: pack, onSelect: { onSelectStarterPack(pack) })
    case .trendingTopic(let topic):
      SearchTrendingRow(topic: topic, onSelect: { onSelectTrendingTopic(topic) })
    case .trendingVideo(let trend):
      SearchTrendingRow(trend: trend, onSelect: { onSelectTrendingVideo(trend) })
    case .error(let error):
      errorRow(error)
    case .loadMore(let more):
      loadMoreRow(more)
    }
  }

  /// A section-level failure row.
  ///
  /// The message comes from `SearchLogic` (it carries the RN copy); the retry
  /// affordance is the screen's, since only the caller knows which fetch failed.
  private func errorRow(_ error: ExploreSectionError) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(error.message, scale: .sm, color: theme.colors.negative600)
      AlfText(error.error, scale: .xs, color: theme.atomColors.textContrastMedium)
      Button(SearchCopy.retryAction, action: onRetry)
        .buttonStyle(.plain)
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textLink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.md, .horizontal)
    .padding(.sm, .vertical)
  }

  /// The "load more" row for a truncated section.
  private func loadMoreRow(_ more: ExploreLoadMore) -> some View {
    HStack(spacing: Spacing.sm) {
      if more.isLoadingMore {
        ProgressView()
      } else {
        AlfText(more.message, scale: .sm, color: theme.atomColors.textLink)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.md, .horizontal)
    .padding(.sm, .vertical)
    .contentShape(Rectangle())
    .onTapGesture(perform: onLoadMoreFeeds)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(more.message)
  }
}
