import DesignSystem
import Foundation
import SearchLogic
import SwiftUI
import UIComponents

/// The search screen: a field over one of three bodies, chosen by the state
/// machine's state.
///
/// The three bodies are the RN screen's three branches -
/// ``SearchState/idle`` renders Explore, ``SearchState/suggesting`` renders the
/// suggestion list, ``SearchState/results`` renders the tabbed results - and the
/// switch is exhaustive over ``SearchState``, so an unhandled combination cannot
/// compile.
///
/// This view owns only presentation state: which Explore page it has been
/// handed, and the callbacks. Every transition goes through the view model,
/// which forwards to `SearchLogic`.
public struct SearchScreen: View {
  @State private var viewModel: SearchViewModel
  private let exploreData: ExplorePageData
  private let isLoadingExplore: Bool
  private let title: String

  @Environment(\.alfTheme) private var theme

  /// Creates the screen.
  ///
  /// - Parameters:
  ///   - viewModel: the adapter over the logic layer. Defaults to one backed by
  ///     the empty service, which renders the idle/Explore surface.
  ///   - exploreData: the assembled Explore page. Defaults to an empty page, so
  ///     the screen renders its empty state rather than fabricating sections.
  ///   - isLoadingExplore: whether the Explore queries are still in flight.
  ///   - title: the navigation title copy.
  public init(
    viewModel: SearchViewModel = SearchViewModel(),
    exploreData: ExplorePageData = ExplorePageData(sections: []),
    isLoadingExplore: Bool = false,
    title: String = SearchCopy.searchTitle
  ) {
    self._viewModel = State(initialValue: viewModel)
    self.exploreData = exploreData
    self.isLoadingExplore = isLoadingExplore
    self.title = title
  }

  public var body: some View {
    VStack(spacing: 0) {
      SearchField(
        text: Binding(
          get: { viewModel.text },
          set: { viewModel.type($0) }),
        onCommit: { Task { await viewModel.submit() } },
        onCancel: { viewModel.clear() })
      Divider().overlay(theme.atomColors.borderContrastLow)
      body(for: viewModel.model.state)
    }
    .background(theme.atomColors.bg)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func body(for state: SearchState) -> some View {
    switch state {
    case .idle:
      ExploreScreen(
        data: exploreData,
        isLoading: isLoadingExplore,
        onRetry: { Task { await viewModel.loadResultsIfNeeded() } },
        onLoadMoreFeeds: { Task { await viewModel.loadResultsIfNeeded() } })
    case .suggesting(let suggestions):
      SearchSuggestionsList(
        suggestions: suggestions,
        history: viewModel.recentSearches,
        onSearchFor: { _ in Task { await viewModel.submit() } },
        onSelectHistory: { viewModel.submit(entry: $0) },
        onRemoveHistory: { entry in Task { await viewModel.remove(entry: entry) } })
    case .results(let results):
      SearchResultsView(
        model: viewModel.model,
        posts: viewModel.posts,
        actors: viewModel.actors,
        feeds: viewModel.feeds,
        starterPacks: viewModel.starterPacks,
        listState: viewModel.listState,
        onSelectTab: { viewModel.select(tab: $0) },
        onRetry: { Task { await viewModel.loadResultsIfNeeded() } })
        .id(results.tab.rawValue)
    }
  }
}

#Preview("Search") {
  NavigationStack {
    SearchScreen(exploreData: SearchFixtures.explorePage)
  }
}
