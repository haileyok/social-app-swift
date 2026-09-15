import DesignSystem
import DesignTokens
import Foundation
import Lexicons
import SearchLogic
import SwiftUI
import UIComponents

/// The accessibility identifiers the search surfaces expose.
///
/// Kept in this package rather than `App`'s `ShellAccessibility` so a UI test
/// that links only `SearchViews` can address the same elements, mirroring how
/// `LoginAccessibility` serves the login screens.
public enum SearchAccessibility {
  /// The search screen's input field.
  public static let searchField = "search.input"
  /// The suggestions/history list.
  public static let suggestionsList = "search.suggestions"
  /// The results tab bar.
  public static let resultsTabs = "search.tabs"
  /// The results list for the active tab.
  public static let resultsList = "search.results"
  /// The Explore screen's section list.
  public static let exploreList = "search.explore"
  /// The row that runs the typed text as a search.
  public static let searchForRow = "search.suggestions.searchFor"
  /// The caption above the recent-searches list.
  public static let recentSearchesHeader = "search.suggestions.recentHeader"
}

/// The suggestion panel shown while a query is being typed.
///
/// Renders the three RN branches as one list: the "Search for <query>" row
/// first, then the recent-searches history when there are no network
/// suggestions, then the typeahead profiles. `SearchLogic` owns which items are
/// eligible; this view orders and labels them.
public struct SearchSuggestionsList: View {
  private let suggestions: SearchSuggestionState?
  private let history: [SearchHistoryEntry]
  private let onSearchFor: (String) -> Void
  private let onSubmit: () -> Void
  private let onSelectProfile: (Lexicons.App.Bsky.ActorDefs_ProfileViewBasic) -> Void
  private let onSelectHistory: (SearchHistoryEntry) -> Void
  private let onRemoveHistory: (SearchHistoryEntry) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    suggestions: SearchSuggestionState?,
    history: [SearchHistoryEntry],
    onSearchFor: @escaping (String) -> Void = { _ in },
    onSubmit: @escaping () -> Void = {},
    onSelectProfile: @escaping (Lexicons.App.Bsky.ActorDefs_ProfileViewBasic) -> Void = { _ in },
    onSelectHistory: @escaping (SearchHistoryEntry) -> Void = { _ in },
    onRemoveHistory: @escaping (SearchHistoryEntry) -> Void = { _ in }
  ) {
    self.suggestions = suggestions
    self.history = history
    self.onSearchFor = onSearchFor
    self.onSubmit = onSubmit
    self.onSelectProfile = onSelectProfile
    self.onSelectHistory = onSelectHistory
    self.onRemoveHistory = onRemoveHistory
  }

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if let query = activeQuery, !query.isEmpty {
          searchForRow(query)
        }
        if !history.isEmpty, showsHistoryFirst {
          historySection
        }
        suggestionsSection
      }
    }
    .accessibilityIdentifier(SearchAccessibility.suggestionsList)
  }

  // MARK: - Sections

  /// The row that commits the typed text as a full search.
  private func searchForRow(_ query: String) -> some View {
    RowContainer(onSelect: { onSearchFor(query) }, content: {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 15))
          .foregroundStyle(theme.atomColors.textContrastMedium)
        AlfText(SearchCopy.searchForRow(query), scale: .md)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
    })
    .accessibilityIdentifier(SearchAccessibility.searchForRow)
  }

  private var historySection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader(SearchCopy.recentSearchesTitle)
        .accessibilityIdentifier(SearchAccessibility.recentSearchesHeader)
      ForEach(history, id: \.serialized) { entry in
        RowContainer(
          onSelect: { onSelectHistory(entry) },
          onRemove: { onRemoveHistory(entry) },
          content: {
            HStack(spacing: Spacing.sm) {
              Image(systemName: "clock")
                .font(.system(size: 15))
                .foregroundStyle(theme.atomColors.textContrastMedium)
              AlfText(entry.q, scale: .md)
                .lineLimit(1)
              Spacer(minLength: 0)
            }
          }
        )
      }
    }
  }

  @ViewBuilder
  private var suggestionsSection: some View {
    switch suggestions {
    case .loaded(_, let items):
      if !items.isEmpty {
        sectionHeader(SearchCopy.recentAccountsTitle)
        ForEach(items, id: \.did.rawValue) { profile in
          SearchProfileRow(profile: profile, onSelect: { onSelectProfile(profile) })
        }
      }
    case .loading:
      LoadMoreSpinner()
    case .failed(_, let message):
      sectionHeader(message)
    case .debouncing, .none:
      EmptyView()
    }
  }

  private func sectionHeader(_ text: String) -> some View {
    AlfText(text, scale: .xs, weight: Scales.FontWeight.semiBold,
      color: theme.atomColors.textContrastMedium)
      .padding(.md, .horizontal)
      .padding(.top, Spacing.md)
      .padding(.bottom, Spacing.xs)
  }

  // MARK: - Derived

  /// The query the current suggestion sub-state belongs to, when there is one.
  private var activeQuery: String? { suggestions?.query }

  /// Whether the history list belongs above the typeahead results.
  ///
  /// The RN screen shows recents in place of suggestions until the typeahead
  /// resolves, so history sits above a loading or empty suggestion list and
  /// below a populated one would be redundant - this keeps the ordering the RN
  /// screen has: "Search for", then recents, then the resolved profiles.
  private var showsHistoryFirst: Bool {
    switch suggestions {
    case .loaded(_, let items): return items.isEmpty
    case .debouncing, .loading, .failed, .none: return true
    }
  }
}
