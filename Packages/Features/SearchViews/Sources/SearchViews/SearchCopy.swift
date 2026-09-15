import Foundation
import SearchLogic

/// The view-owned copy for the search and Explore screens, in one place.
///
/// This is the seam a String Catalog replaces later: every user-facing string on
/// these screens is read through one of these static members, so swapping them
/// for `String(localized:)` calls is a single-file change and no view carries a
/// scattered literal.
///
/// Strings the logic layer already owns are deferred to it rather than restated:
/// ``ExploreSectionTitle/text`` supplies the section headings and
/// ``SearchHistoryEntry`` the query text, so a reworded heading never has to be
/// fixed in two packages. This catalog adds only what the logic layer has no
/// reason to know about - placeholders, tab labels, empty-state copy, chrome.
public enum SearchCopy {
  // MARK: - Screen chrome

  /// The Explore screen's navigation title.
  public static let exploreTitle = "Explore"
  /// The search screen's navigation title once a query is committed.
  public static let searchTitle = "Search"
  /// The search field's placeholder.
  public static let searchPlaceholder = "Search"
  /// The search field's accessibility label.
  public static let searchFieldLabel = "Search"
  /// The action that clears the field / cancels the search.
  public static let cancelSearchAction = "Cancel search"
  /// The action that empties the field.
  public static let clearFieldAction = "Clear search"

  // MARK: - Idle (nothing typed)

  /// The headline of the "start searching" prompt.
  public static let idleTitle = "Search"
  /// The supporting line under the idle headline.
  public static let idleMessage = "Find posts, users, and feeds on Bluesky"

  // MARK: - Suggestion list

  /// The row that runs the typed text as a full search.
  public static func searchForRow(_ query: String) -> String {
    "Search for “\(query)”"
  }

  /// The caption above the recent-searches list.
  public static let recentSearchesTitle = "Recent searches"
  /// The caption above the recent-accounts list.
  public static let recentAccountsTitle = "Recent accounts"
  /// The action that drops one recent search.
  public static let removeHistoryEntryAction = "Remove"

  // MARK: - Tabs

  /// The "Top" results tab.
  public static let tabTop = "Top"
  /// The "Latest" results tab.
  public static let tabLatest = "Latest"
  /// The "People" results tab.
  public static let tabPeople = "People"
  /// The "Feeds" results tab.
  public static let tabFeeds = "Feeds"

  /// The label for a ``SearchTab``.
  ///
  /// Kept here rather than on the enum so the logic layer stays free of display
  /// copy; the enum's `rawValue` is the stable analytics key.
  public static func label(for tab: SearchTab) -> String {
    switch tab {
    case .top: tabTop
    case .latest: tabLatest
    case .people: tabPeople
    case .feeds: tabFeeds
    }
  }

  // MARK: - Results

  /// The heading shown when a query returned nothing.
  ///
  /// Mirrors the RN copy in `SearchResults.tsx`, which distinguishes a plain
  /// query from one narrowed by advanced filters.
  public static func noResultsTitle(query: String, hasFilters: Bool) -> String {
    if hasFilters {
      return query.isEmpty
        ? "No results found for your query with advanced search filters applied."
        : "No results found for “\(query)” with advanced search filters applied."
    }
    return "No results found for “\(query)”."
  }

  /// The supporting line under the no-results heading.
  public static let noResultsMessage =
    "Try a different search term, or check your spelling."

  /// The full-surface error title for a failed search request.
  public static let resultsErrorTitle = "Could not load results"
  /// The full-surface error message for a failed search request.
  public static let resultsErrorMessage =
    "Something went wrong. Check your connection and try again."

  // MARK: - Explore

  /// The label for the "load more" row of the suggested-feeds section, when no
  /// server-supplied message is present.
  public static let loadMoreFallback = "Load more"

  /// The retry label used by every list state on these screens.
  public static let retryAction = "Retry"

  /// The empty-state copy for the Explore screen.
  public static let exploreEmptyTitle = "Nothing to explore yet"
  /// The supporting copy for the Explore empty state.
  public static let exploreEmptyMessage =
    "Suggestions will appear here once they are available."

  // MARK: - Section headings

  /// The heading for an Explore section.
  ///
  /// `SearchLogic` owns the English text (``ExploreSectionTitle/text``); this
  /// indirection exists so the catalog is the one place to look.
  public static func heading(for title: ExploreSectionTitle) -> String {
    title.text
  }

  // MARK: - Row detail lines

  /// The caption under a feed row, e.g. "Feed by @alice".
  public static func feedByline(creatorHandle: String) -> String {
    "Feed by @\(creatorHandle)"
  }

  /// The caption under a starter-pack row.
  public static func starterPackByline(creatorHandle: String) -> String {
    "Starter pack by @\(creatorHandle)"
  }

  /// The title a starter-pack row falls back to when its backing list has no
  /// name.
  public static let starterPackTitleFallback = "Starter pack"

  /// The "N posts" line on a trending topic.
  public static func trendingPostCount(_ count: Int) -> String {
    count == 1 ? "1 post" : "\(count) posts"
  }
}
