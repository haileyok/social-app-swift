import Foundation
import Lexicons
import SearchLogic
import SwiftAtproto
import UIComponentsCore

/// Bridges the search field's text into the logic layer's state machine, and
/// calls the two fetches the screens need.
///
/// The protocol exists for the same reason ``LoginFlow`` is injected into the
/// login views: it keeps the SwiftUI surfaces previewable and fixture-driven
/// without a transport, while the real implementation below talks to the
/// search XRPC endpoints through ``SearchLogic/SearchFetchers``.
public protocol SearchServicing: Sendable {
  /// `app.bsky.actor.searchActorsTypeahead`, reduced to the suggestion list.
  ///
  /// The raw response is filtered through
  /// ``SearchLogic/ActorAutocomplete/suggestions(prefix:searched:verdict:)``
  /// first, so dedupe and the inclusion rule belong to the logic layer.
  func suggestions(for prefix: String) async throws -> [Lexicons.App.Bsky.ActorDefs_ProfileViewBasic]

  /// Post results for a committed query, sorted for the active tab.
  func posts(
    query: String, sort: SearchQueryKeys.SearchPostsSort, filters: SearchFilters
  ) async throws -> [Lexicons.App.Bsky.FeedDefs_PostView]

  /// Actor results for the People tab.
  func actors(
    query: String, filters: SearchFilters
  ) async throws -> [Lexicons.App.Bsky.ActorDefs_ProfileView]

  /// Feed-generator results for the Feeds tab.
  func feeds(query: String) async throws -> [Lexicons.App.Bsky.FeedDefs_GeneratorView]

  /// Starter-pack results.
  func starterPacks(query: String) async throws -> [Lexicons.App.Bsky.GraphDefs_StarterPackView]
}

/// The live ``SearchServicing`` over ``SearchLogic/SearchFetchers``.
public struct LiveSearchService: SearchServicing {
  private let fetchers: SearchFetchers

  /// Creates the service over a fetcher facade.
  public init(fetchers: SearchFetchers) {
    self.fetchers = fetchers
  }

  public func suggestions(for prefix: String) async throws
    -> [Lexicons.App.Bsky.ActorDefs_ProfileViewBasic] {
    // The RN hook short-circuits an empty prefix; ActorAutocomplete owns that
    // rule, so it is applied here rather than in the view.
    guard ActorAutocomplete.shouldFetch(prefix: ActorAutocomplete.normalizePrefix(prefix)) else {
      return []
    }
    let output = try await fetchers.searchActorsTypeahead(
      prefix: ActorAutocomplete.normalizePrefix(prefix))
    return ActorAutocomplete.suggestions(prefix: prefix, searched: output.actors)
  }

  public func posts(
    query: String, sort: SearchQueryKeys.SearchPostsSort, filters: SearchFilters
  ) async throws -> [Lexicons.App.Bsky.FeedDefs_PostView] {
    try await fetchers.searchPostsV2(query: query, sort: sort, filters: filters).posts
  }

  public func actors(
    query: String, filters: SearchFilters
  ) async throws -> [Lexicons.App.Bsky.ActorDefs_ProfileView] {
    try await fetchers.searchActors(query: query).actors
  }

  public func feeds(query: String) async throws -> [Lexicons.App.Bsky.FeedDefs_GeneratorView] {
    // The Feeds tab has no dedicated search endpoint in the pinned lexicon
    // snapshot, so it lists popular feed generators, as the RN screen's Feeds
    // tab does when the search-backed endpoint is unavailable. The query is
    // applied client-side so the tab still narrows to what was typed.
    let pages = try await fetchers.getPopularFeedGenerators(limit: 25)
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return pages.feeds }
    return pages.feeds.filter {
      $0.displayName.lowercased().contains(normalized)
        || ($0.description?.lowercased().contains(normalized) ?? false)
    }
  }

  public func starterPacks(query: String) async throws
    -> [Lexicons.App.Bsky.GraphDefs_StarterPackView] {
    try await fetchers.searchStarterPacks(query: query).starterPacks
  }
}

/// The SwiftUI-facing adapter over the search state machine.
///
/// ``SearchLogic/SearchStateMachine`` is an actor emitting a `Sendable` model
/// through a callback rather than being `Observable` itself (it is deliberately
/// usable off the main actor). This type is the bridge: it holds the field's
/// text, registers one listener, republishes each transition on the main actor,
/// and runs the fetches the results tabs and the Explore screen render.
///
/// Every decision stays with the logic layer - ``type(_:)``,
/// ``SearchStateMachine/submit()``, ``SearchStateMachine/selectTab(_:)`` and
/// ``SearchStateMachine/setFilters(_:)`` are called and their output rendered;
/// no rule is re-derived here.
@MainActor
@Observable
public final class SearchViewModel {
  /// The field's text, mirrored into the machine on every keystroke.
  public var text: String = ""
  /// The machine's model, republished on the main actor.
  public private(set) var model = SearchStateModel()
  /// The commit history, newest first.
  public private(set) var recentSearches: [SearchHistoryEntry] = []
  /// The post rows for the active query and tab.
  public private(set) var posts: [Lexicons.App.Bsky.FeedDefs_PostView] = []
  /// The actor rows for the People tab.
  public private(set) var actors: [Lexicons.App.Bsky.ActorDefs_ProfileView] = []
  /// The feed rows for the Feeds tab.
  public private(set) var feeds: [Lexicons.App.Bsky.FeedDefs_GeneratorView] = []
  /// The starter-pack rows.
  public private(set) var starterPacks: [Lexicons.App.Bsky.GraphDefs_StarterPackView] = []
  /// The full-surface state of the results lists.
  public private(set) var listState: ListState = .content
  /// True while a results fetch is in flight.
  public private(set) var isLoadingResults = false

  /// The state machine this model renders.
  public let machine: SearchStateMachine
  /// The fetches the results tabs and Explore use.
  public let service: any SearchServicing

  /// The query the currently-loaded results belong to, so a stale response is
  /// discarded when the query or tab changed while it was in flight.
  private var loadedKey: String?

  /// Creates the adapter.
  ///
  /// - Parameters:
  ///   - service: the fetch surface. Defaults to a fixture-backed service that
  ///     returns nothing, which is enough to render every empty and idle state.
  ///   - history: the term history, when one is available. Passing `nil` leaves
  ///     the recent-searches list empty rather than failing.
  public init(
    service: any SearchServicing = EmptySearchService(),
    history: SearchHistory? = nil
  ) {
    self.service = service
    self.history = history
    // The machine reports every transition through the single callback it is
    // given at init, so the callback is installed through a box: the box is
    // captured by the closure immediately, and the box's listener is filled in
    // once `self` is fully initialized.
    let box = ListenerBox()
    self.machine = SearchStateMachine(
      fetchSuggestions: { [service] prefix in try await service.suggestions(for: prefix) },
      onChange: { model in box.listener?(model) })
    box.listener = { [weak self] model in
      Task { @MainActor in self?.apply(model) }
    }
    Task { await self.loadHistory() }
  }

  private let history: SearchHistory?

  private func apply(_ model: SearchStateModel) {
    self.model = model
    if case .results = model.state {
      Task { await self.loadResultsIfNeeded() }
    }
  }

  /// Loads the stored term history into the view.
  public func loadHistory() async {
    guard let history else { return }
    try? await history.load()
    recentSearches = await history.termEntries
  }

  // MARK: - Input

  /// Records typed text in the machine, which owns the debounce and the state
  /// transition.
  public func type(_ value: String) {
    text = value
    Task { await machine.type(value) }
  }

  /// Commits the query, records it in history, and loads results.
  public func submit() async {
    await machine.submit()
    guard let history, !model.query.isEmpty else { return }
    try? await history.addTerm(model.query, filters: model.filters)
    recentSearches = await history.termEntries
  }

  /// Runs a stored history entry.
  public func submit(entry: SearchHistoryEntry) {
    text = entry.q
    Task {
      await machine.setFilters(entry.filters)
      await machine.type(entry.q)
      await machine.submit()
      apply(await machine.model)
    }
  }

  /// Drops one stored entry.
  public func remove(entry: SearchHistoryEntry) async {
    guard let history else { return }
    // The stored form is what the history dedupes on, so the entry is removed
    // by exactly that string.
    try? await history.removeTerm(entry.serialized)
    recentSearches = await history.termEntries
  }

  /// Selects a results tab.
  public func select(tab: SearchTab) {
    Task { await machine.selectTab(tab) }
  }

  /// Clears the field and returns to the idle state.
  public func clear() {
    text = ""
    posts = []
    actors = []
    feeds = []
    starterPacks = []
    loadedKey = nil
    Task { await machine.reset() }
  }

  // MARK: - Results

  /// Runs the fetch the active tab needs, once per (query, filters, tab) key.
  public func loadResultsIfNeeded() async {
    guard case .results(let results) = model.state else { return }
    let key = "\(results.tab.rawValue)|\(results.query)|\(results.filters.definedParams)"
    guard key != loadedKey else { return }
    loadedKey = key
    isLoadingResults = true
    listState = .loading
    defer { isLoadingResults = false }

    do {
      switch results.tab {
      case .top, .latest:
        let sort: SearchQueryKeys.SearchPostsSort = results.tab == .latest ? .latest : .top
        let pages = try await service.posts(
          query: results.query, sort: sort, filters: results.filters)
        posts = pages
        listState = pages.isEmpty ? .empty : .content
      case .people:
        let users = try await service.actors(query: results.query, filters: results.filters)
        actors = users
        listState = users.isEmpty ? .empty : .content
      case .feeds:
        let generators = try await service.feeds(query: results.query)
        feeds = generators
        listState = generators.isEmpty ? .empty : .content
      }
      // Starter packs are a separate section of the results screen, so they are
      // loaded alongside the active tab rather than instead of it.
      starterPacks = (try? await service.starterPacks(query: results.query)) ?? []
    } catch {
      listState = .error(
        ListState.ListErrorState(
          title: SearchCopy.resultsErrorTitle, message: SearchCopy.resultsErrorMessage))
    }
  }

  /// The suggestion sub-state, when the screen is showing suggestions.
  public var suggestions: SearchSuggestionState? {
    if case .suggesting(let state) = model.state { return state }
    return nil
  }

  /// True when the screen should render Explore rather than results.
  public var isIdle: Bool { model.state == .idle }
}

/// A one-shot indirection so the state machine's `onChange` callback can be
/// wired to a listener that is only available after the owner is initialized.
///
/// The machine takes its callback at init and the callback must capture the
/// owner; without this box the closure would have to capture a partially
/// initialized `self`. `@unchecked Sendable` is sound here because the only
/// mutation happens on the main actor during `init`, before any transition can
/// fire.
private final class ListenerBox: @unchecked Sendable {
  var listener: (@Sendable (SearchStateModel) -> Void)?
}

/// A ``SearchServicing`` that returns nothing, so previews and the fixture hook
/// render every empty state without a transport.
public struct EmptySearchService: SearchServicing {
  public init() {}

  public func suggestions(for prefix: String) async throws
    -> [Lexicons.App.Bsky.ActorDefs_ProfileViewBasic] { [] }
  public func posts(
    query: String, sort: SearchQueryKeys.SearchPostsSort, filters: SearchFilters
  ) async throws -> [Lexicons.App.Bsky.FeedDefs_PostView] { [] }
  public func actors(
    query: String, filters: SearchFilters
  ) async throws -> [Lexicons.App.Bsky.ActorDefs_ProfileView] { [] }
  public func feeds(query: String) async throws -> [Lexicons.App.Bsky.FeedDefs_GeneratorView] { [] }
  public func starterPacks(query: String) async throws
    -> [Lexicons.App.Bsky.GraphDefs_StarterPackView] { [] }
}
