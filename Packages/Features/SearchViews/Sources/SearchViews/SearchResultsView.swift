import DesignSystem
import Foundation
import SearchLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The results surface: a tab bar over the post, actor and feed result lists.
///
/// Tabs are native-first: the bar is a horizontal segmented control built from
/// the tab list ``SearchLogic/SearchStateModel/tabs`` computes, so the People and
/// Feeds tabs disappear exactly when `SearchLogic` says they should (a post-only
/// filter is active). Selection is reported through `onSelect`; this view owns no
/// state of its own beyond what it is handed.
public struct SearchResultsView: View {
  private let model: SearchStateModel
  private let posts: [App.Bsky.FeedDefs_PostView]
  private let actors: [App.Bsky.ActorDefs_ProfileView]
  private let feeds: [App.Bsky.FeedDefs_GeneratorView]
  private let starterPacks: [App.Bsky.GraphDefs_StarterPackView]
  private let listState: ListState
  private let onSelectTab: (SearchTab) -> Void
  private let onRetry: () -> Void
  private let onSelectProfile: (App.Bsky.ActorDefs_ProfileView) -> Void
  private let onSelectFeed: (App.Bsky.FeedDefs_GeneratorView) -> Void
  private let onSelectStarterPack: (App.Bsky.GraphDefs_StarterPackView) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    model: SearchStateModel,
    posts: [App.Bsky.FeedDefs_PostView] = [],
    actors: [App.Bsky.ActorDefs_ProfileView] = [],
    feeds: [App.Bsky.FeedDefs_GeneratorView] = [],
    starterPacks: [App.Bsky.GraphDefs_StarterPackView] = [],
    listState: ListState = .content,
    onSelectTab: @escaping (SearchTab) -> Void = { _ in },
    onRetry: @escaping () -> Void = {},
    onSelectProfile: @escaping (App.Bsky.ActorDefs_ProfileView) -> Void = { _ in },
    onSelectFeed: @escaping (App.Bsky.FeedDefs_GeneratorView) -> Void = { _ in },
    onSelectStarterPack: @escaping (App.Bsky.GraphDefs_StarterPackView) -> Void = { _ in }
  ) {
    self.model = model
    self.posts = posts
    self.actors = actors
    self.feeds = feeds
    self.starterPacks = starterPacks
    self.listState = listState
    self.onSelectTab = onSelectTab
    self.onRetry = onRetry
    self.onSelectProfile = onSelectProfile
    self.onSelectFeed = onSelectFeed
    self.onSelectStarterPack = onSelectStarterPack
  }

  public var body: some View {
    VStack(spacing: 0) {
      tabBar
      Divider().overlay(theme.atomColors.borderContrastLow)
      content
    }
    .accessibilityIdentifier(SearchAccessibility.resultsTabs)
  }

  // MARK: - Tab bar

  private var tabBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.lg) {
        ForEach(model.tabs, id: \.rawValue) { tab in
          tabButton(tab)
        }
      }
      .padding(.md, .horizontal)
    }
  }

  private func tabButton(_ tab: SearchTab) -> some View {
    let isSelected = tab == model.tab
    return Button {
      onSelectTab(tab)
    } label: {
      VStack(spacing: Spacing.xs) {
        AlfText(
          SearchCopy.label(for: tab),
          scale: .md,
          weight: isSelected ? Scales.FontWeight.semiBold : Scales.FontWeight.normal,
          color: isSelected ? theme.atomColors.text : theme.atomColors.textContrastMedium)
        Rectangle()
          .fill(isSelected ? theme.colors.primary500 : Color.clear)
          .frame(height: 2)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    .accessibilityLabel(SearchCopy.label(for: tab))
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    switch listState {
    case .loading:
      ListSkeleton()
    case .error(let error):
      ErrorStateView(error: error, retry: onRetry)
    case .content:
      resultList
    case .empty:
      emptyState
    case .loadingMore:
      resultList
    }
  }

  @ViewBuilder
  private var resultList: some View {
    switch model.tab {
    case .top, .latest:
      postsList
    case .people:
      actorsList
    case .feeds:
      feedsList
    }
  }

  private var postsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(posts, id: \.uri.rawValue) { post in
          PostFeedItem(data: SearchRowData.feedItem(post))
          Divider().overlay(theme.atomColors.borderContrastLow)
        }
        starterPackSection
      }
    }
    .accessibilityIdentifier(SearchAccessibility.resultsList)
  }

  private var actorsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(actors, id: \.did.rawValue) { actor in
          SearchProfileRow(profile: actor, onSelect: { onSelectProfile(actor) })
        }
      }
    }
    .accessibilityIdentifier(SearchAccessibility.resultsList)
  }

  private var feedsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(feeds, id: \.uri.rawValue) { feed in
          SearchFeedRow(feed: feed, onSelect: { onSelectFeed(feed) })
        }
      }
    }
    .accessibilityIdentifier(SearchAccessibility.resultsList)
  }

  /// Starter packs appear under the post tabs, as they do on the RN results
  /// screen, which lists them alongside posts rather than in a tab of their own
  /// in this port's tab set.
  @ViewBuilder
  private var starterPackSection: some View {
    if !starterPacks.isEmpty, model.tab == .top {
      VStack(alignment: .leading, spacing: 0) {
        AlfText(
          SearchCopy.heading(for: .starterPacks), scale: .xs,
          weight: Scales.FontWeight.semiBold,
          color: theme.atomColors.textContrastMedium
        )
        .padding(.md, .horizontal)
        .padding(.top, Spacing.md)
        ForEach(starterPacks, id: \.uri.rawValue) { pack in
          SearchStarterPackRow(pack: pack, onSelect: { onSelectStarterPack(pack) })
        }
      }
    }
  }

  private var emptyState: some View {
    EmptyStateView(
      strings: ListStrings(
        emptyTitle: SearchCopy.noResultsTitle(
          query: model.state.resultsQuery, hasFilters: model.filters.isActive),
        emptyMessage: SearchCopy.noResultsMessage,
        errorTitle: SearchCopy.resultsErrorTitle,
        errorMessage: SearchCopy.resultsErrorMessage,
        retryLabel: SearchCopy.retryAction),
      icon: "magnifyingglass")
  }
}

extension SearchState {
  /// The query the results state carries, or an empty string.
  fileprivate var resultsQuery: String {
    if case .results(let state) = self { return state.query }
    return ""
  }
}
