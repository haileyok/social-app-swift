import Foundation
import Lexicons
import QueryStore

/// The search screen's resolved state, as data.
///
/// Ported from the branch structure of `screens/Search/Shell.tsx` +
/// `SearchResults.tsx`: with no query and no filters the screen shows Explore;
/// while typing it shows suggestions; once a query is committed it shows
/// results. Modeling the states as an enum (rather than as several independent
/// booleans, which is what the RN component does with `searchText`,
/// `showAutocomplete` and `hasFilters`) makes the transitions exhaustive and
/// the illegal combinations unrepresentable.
public enum SearchState: Sendable, Equatable {
  /// Nothing typed and no filters: the Explore page.
  case idle
  /// A query typed but not yet committed: typeahead suggestions.
  case suggesting(SearchSuggestionState)
  /// A committed query or active filters: post/actor/feed results.
  case results(SearchResultsState)
}

/// The suggestion sub-state, including the request lifecycle.
public enum SearchSuggestionState: Sendable, Equatable {
  /// Waiting for the debounce to elapse.
  case debouncing(query: String)
  /// The typeahead request is in flight.
  case loading(query: String)
  /// Suggestions resolved.
  ///
  /// `items` is the raw profile list; the RN screen prefixes it with a "Search
  /// for <query>" row, which is presentation and lives in the view.
  case loaded(query: String, items: [App.Bsky.ActorDefs_ProfileViewBasic])
  /// The typeahead request failed; `message` is the cleaned error text.
  case failed(query: String, message: String)

  /// The query this sub-state belongs to.
  public var query: String {
    switch self {
    case .debouncing(let q), .loading(let q), .loaded(let q, _), .failed(let q, _): return q
    }
  }
}

/// The results sub-state.
public struct SearchResultsState: Sendable, Equatable {
  /// The query being searched. May be empty when only filters are active.
  public let query: String
  /// The structured filters in effect.
  public let filters: SearchFilters
  /// The active tab.
  public let tab: SearchTab
  /// Whether the "Me" author filter is active (the raw `from:me` was promoted).
  public let fromMe: Bool

  public init(query: String, filters: SearchFilters, tab: SearchTab, fromMe: Bool) {
    self.query = query
    self.filters = filters
    self.tab = tab
    self.fromMe = fromMe
  }
}

/// The search result tabs.
///
/// Ported from the tab params in `screens/Search/Shell.tsx`. The People and
/// Feeds tabs disappear when a post-only filter is active, which
/// ``availableTabs(filters:hasSession:)`` computes.
public enum SearchTab: String, Sendable, Equatable, CaseIterable {
  case top
  case latest
  case people
  case feeds

  /// The stable analytics label, matching `Metrics['explore:module:searchButtonPress']`.
  public var analyticsLabel: String { rawValue }
}

/// The tabs that make sense for the given filters.
///
/// Ported from the RN logic that hides People/Feeds when any post-only filter is
/// set: a language alone should not hide them, but an author/media/etc. filter
/// should, since those only constrain posts.
public func availableTabs(filters: SearchFilters) -> [SearchTab] {
  if filters.hasPostOnlyFilters {
    return [.top, .latest]
  }
  return SearchTab.allCases
}

/// A resolved search-screen model: state plus the data the view needs.
public struct SearchStateModel: Sendable, Equatable {
  /// The current state.
  public var state: SearchState
  /// The query text as typed.
  public var query: String
  /// The active filters.
  public var filters: SearchFilters
  /// The active tab.
  public var tab: SearchTab
  /// Whether a `from:me` operator is present in the query.
  public var fromMe: Bool

  /// The tabs available for the current filters.
  public var tabs: [SearchTab] { availableTabs(filters: filters) }

  /// True when the query or filters are non-empty, i.e. results are expected.
  public var hasQueryOrFilters: Bool { !query.isEmpty || filters.isActive }

  public init(
    state: SearchState = .idle,
    query: String = "",
    filters: SearchFilters = SearchFilters(),
    tab: SearchTab = .top,
    fromMe: Bool = false
  ) {
    self.state = state
    self.query = query
    self.filters = filters
    self.tab = tab
    self.fromMe = fromMe
  }
}

/// Drives the search screen from typed input to results.
///
/// The pipeline, ported from `Shell.tsx` + `useSearchText`:
///
/// 1. typing updates ``SearchStateModel/query`` and starts the debounce;
/// 2. while the debounce runs the state is ``SearchSuggestionState/debouncing``;
/// 3. when it elapses the typeahead is fetched and the state is
///    ``SearchSuggestionState/loading`` then ``loaded``/``failed``;
/// 4. committing (submitting) cancels any pending typeahead and moves to
///    ``SearchState/results``.
///
/// Every state change is emitted through ``onChange`` so a view can re-render.
/// Testability comes from ``SearchClock``: with ``ManualSearchClock`` the
/// debounce and its cancellation are directly observed.
public actor SearchStateMachine {
  /// The view-facing model after each transition.
  public private(set) var model: SearchStateModel
  /// Called on every transition.
  private let onChange: (@Sendable (SearchStateModel) -> Void)?
  /// The debounce seam.
  private let clock: any SearchClock
  /// The typeahead fetcher. Injected so the machine is testable without a store.
  private let fetchSuggestions:
    @Sendable (String) async throws -> [App.Bsky.ActorDefs_ProfileViewBasic]
  /// The debounce delay in nanoseconds.
  private let debounceNanoseconds: UInt64

  /// The pending debounce cancellation, if any.
  private var pendingDebounce: (any SearchClockCancellation)?
  /// Monotonic id of the newest suggestion request, so a stale response is
  /// discarded when a later query has already been typed.
  private var suggestionRequestId: UInt64 = 0
  /// Monotonic id of the next scheduled debounce.
  private var nextDebounceId: UInt64 = 0

  /// Creates the machine.
  ///
  /// - Parameters:
  ///   - clock: the debounce seam. Use ``ManualSearchClock`` in tests.
  ///   - debounceMilliseconds: the typing debounce. Matches the RN
  ///     `useDebouncedValue` delay used for handle availability (500 ms).
  ///   - fetchSuggestions: the typeahead call.
  ///   - onChange: called after every transition.
  public init(
    clock: any SearchClock = SystemSearchClock(),
    debounceMilliseconds: UInt64 = 500,
    fetchSuggestions: @escaping @Sendable (String) async throws ->
      [App.Bsky.ActorDefs_ProfileViewBasic],
    onChange: (@Sendable (SearchStateModel) -> Void)? = nil
  ) {
    self.clock = clock
    self.debounceNanoseconds = debounceMilliseconds * 1_000_000
    self.fetchSuggestions = fetchSuggestions
    self.onChange = onChange
    self.model = SearchStateModel()
  }

  // MARK: - Input

  /// Records typed text and (re)starts the debounce.
  ///
  /// Ported from the RN input handler: any keystroke invalidates an in-flight
  /// suggestion request and restarts the debounce. An empty query with no
  /// filters returns to ``SearchState/idle`` immediately, with no request.
  public func type(_ text: String) {
    pendingDebounce?.cancel()
    pendingDebounce = nil
    // Any keystroke makes the in-flight suggestion response stale.
    suggestionRequestId += 1
    model.query = text
    // A raw `from:me` in the text promotes to the Me filter.
    model.fromMe = SearchQueryParams.extractFromMe(text).fromMe

    guard !text.isEmpty else {
      if model.filters.isActive {
        model.state = .results(makeResultsState())
      } else {
        model.state = .idle
      }
      emit()
      return
    }

    model.state = .suggesting(.debouncing(query: text))
    emit()
    scheduleDebounce(for: text)
  }

  /// Commits the current query, moving to results and cancelling suggestions.
  ///
  /// Ported from the RN submit handler, which writes the query into history and
  /// navigates to the results tabs.
  public func submit() {
    guard model.hasQueryOrFilters else { return }
    pendingDebounce?.cancel()
    pendingDebounce = nil
    suggestionRequestId += 1
    model.state = .results(makeResultsState())
    emit()
  }

  /// Replaces the filters.
  ///
  /// Ported from `useQueryManager.setFilters`: filters alone (with no query) are
  /// enough to show results; clearing both returns to idle.
  public func setFilters(_ filters: SearchFilters) {
    model.filters = filters
    if model.tab == .people || model.tab == .feeds, filters.hasPostOnlyFilters {
      // The post-only filter hides those tabs, so fall back to the first tab.
      model.tab = .top
    }
    if model.hasQueryOrFilters {
      model.state = .results(makeResultsState())
    } else {
      model.state = .idle
    }
    emit()
  }

  /// Selects a tab.
  public func selectTab(_ tab: SearchTab) {
    guard model.tabs.contains(tab) else { return }
    model.tab = tab
    if case .results = model.state {
      model.state = .results(makeResultsState())
      emit()
    }
  }

  /// Resets to the idle state, cancelling any pending work.
  public func reset() {
    pendingDebounce?.cancel()
    pendingDebounce = nil
    suggestionRequestId += 1
    model = SearchStateModel()
    emit()
  }

  // MARK: - Debounced pipeline

  private func scheduleDebounce(for query: String) {
    let id = nextDebounceId
    nextDebounceId += 1
    let nanoseconds = debounceNanoseconds
    pendingDebounce = clock.schedule(afterNanoseconds: nanoseconds) { [weak self] in
      guard let self else { return }
      Task { await self.debounceElapsed(id: id, query: query) }
    }
  }

  private func debounceElapsed(id: UInt64, query: String) async {
    // A later keystroke scheduled a newer debounce; this one is superseded.
    guard model.state == .suggesting(.debouncing(query: query)) else { return }
    pendingDebounce = nil
    suggestionRequestId += 1
    let requestId = suggestionRequestId
    model.state = .suggesting(.loading(query: query))
    emit()
    do {
      let items = try await fetchSuggestions(query)
      // Discard a response that a later keystroke already superseded.
      guard requestId == suggestionRequestId else { return }
      guard case .suggesting = model.state else { return }
      model.state = .suggesting(.loaded(query: query, items: items))
      emit()
    } catch {
      guard requestId == suggestionRequestId else { return }
      guard case .suggesting = model.state else { return }
      model.state = .suggesting(.failed(query: query, message: cleanError(error)))
      emit()
    }
  }

  /// Cancels any pending suggestion work without changing the state.
  ///
  /// This is the cancellation half of the pipeline: committing, resetting or
  /// deactivating all route through here so an in-flight typeahead cannot land
  /// after results are showing.
  public func cancelPendingSuggestions() {
    pendingDebounce?.cancel()
    pendingDebounce = nil
    suggestionRequestId += 1
  }

  private func makeResultsState() -> SearchResultsState {
    SearchResultsState(
      query: SearchQueryParams.extractFromMe(model.query).q,
      filters: model.filters,
      tab: model.tab,
      fromMe: model.fromMe
    )
  }

  private func emit() {
    onChange?(model)
  }
}

/// Reduces an error to the short message the search UI displays.
///
/// The RN `cleanError` helper collapses an unknown error to "Unknown error";
/// a `LocalizedError`/`Error` with a non-empty description passes through.
public func cleanError(_ error: any Error) -> String {
  let description: String
  if let localized = error as? LocalizedError, let text = localized.errorDescription {
    description = text
  } else {
    description = "\(error)"
  }
  let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? "Unknown error" : trimmed
}
