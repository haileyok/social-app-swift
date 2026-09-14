import Foundation

/// A stored search-history entry: a query plus any filters it was run with.
///
/// Ported from `SearchHistoryEntry` in `screens/Search/searchParams.ts`.
public struct SearchHistoryEntry: Sendable, Hashable {
  /// The query text the user typed.
  public let q: String
  /// The filters that were active. Empty for a plain term search.
  public let filters: SearchFilters

  public init(q: String, filters: SearchFilters = SearchFilters()) {
    self.q = q
    self.filters = filters
  }

  /// The canonical storage form: a plain string when there are no filters (the
  /// RN back-compat shape), JSON otherwise.
  public var serialized: String {
    SearchHistoryCoding.serialize(q: q, filters: filters)
  }

  /// The storage key this entry dedupes on.
  ///
  /// RN dedupes on the serialized form, so "cats" and "cats" with an author
  /// filter are distinct entries.
  public var dedupeKey: String { serialized }
}

/// Serialization for search-history entries.
///
/// Ported 1:1 from `serializeHistoryEntry` / `parseHistoryEntry`. Filter-less
/// searches store as plain strings both for readability and so pre-existing
/// term-only history stays valid; only filtered searches are JSON-encoded.
/// Parsing is deliberately total: anything that is not a well-formed
/// `{q, filters}` object is treated as a plain query string, so a bad or
/// pre-existing value never throws.
public enum SearchHistoryCoding {
  /// Serializes a search for term-history storage.
  public static func serialize(q: String, filters: SearchFilters = SearchFilters()) -> String {
    guard filters.isActive else { return q }
    return encodeJSON(q: q, filters: filters)
  }

  /// Parses a stored entry.
  public static func parse(_ stored: String) -> SearchHistoryEntry {
    guard let data = stored.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let q = object["q"] as? String
    else {
      // Not JSON, or JSON without a string `q` - a plain term-only entry.
      return SearchHistoryEntry(q: stored)
    }
    return SearchHistoryEntry(q: q, filters: SearchFilters.read(from: readFilters(object["filters"])))
  }

  private static func readFilters(_ raw: Any?) -> [String: String?]? {
    guard let raw = raw as? [String: Any] else { return nil }
    var params: [String: String?] = [:]
    for (key, value) in raw { params[key] = value as? String }
    return params
  }

  private static func encodeJSON(q: String, filters: SearchFilters) -> String {
    let payload: [String: Any] = ["q": q, "filters": filters.definedParams]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else {
      // A filter set that cannot be encoded would silently lose data, so fall
      // back to the plain query rather than dropping the entry entirely.
      return q
    }
    return text
  }
}

/// Where search history is persisted.
///
/// The RN app writes term history and account history through `useStorage` into
/// the account-scoped MMKV store, keyed `searchTermHistory` / `searchAccountHistory`.
/// This port keeps that shape but puts a protocol in front of the storage so the
/// logic is testable with an in-memory sink and the platform store stays
/// swappable.
///
/// Implementations must be safe to call concurrently.
public protocol SearchHistorySink: Sendable {
  /// Reads the stored term-history strings, newest first.
  func loadTermHistory() async throws -> [String]
  /// Replaces the stored term-history strings.
  func saveTermHistory(_ entries: [String]) async throws
  /// Reads the stored account-history DIDs, newest first.
  func loadAccountHistory() async throws -> [String]
  /// Replaces the stored account-history DIDs.
  func saveAccountHistory(_ dids: [String]) async throws
}

/// Term and account history with the RN's MRU + dedupe semantics.
///
/// Ported from the history callbacks in `screens/Search/Shell.tsx`. Both lists
/// are most-recent-first, deduped on the entry's storage form, and capped: terms
/// at 6, accounts at 10. Every mutation writes the whole list back, matching the
/// RN `setTermHistory(newList)` pattern.
public actor SearchHistory {
  /// The number of term entries kept.
  public static let termLimit = 6
  /// The number of account entries kept.
  public static let accountLimit = 10

  private let sink: any SearchHistorySink
  private var terms: [String]
  private var accounts: [String]

  /// Creates the history over `sink`, optionally seeding it from already-loaded
  /// lists (which is how the RN hook's `useStorage` initial value works).
  public init(sink: any SearchHistorySink, terms: [String] = [], accounts: [String] = []) {
    self.sink = sink
    self.terms = terms
    self.accounts = accounts
  }

  /// Loads both lists from the sink.
  public func load() async throws {
    terms = try await sink.loadTermHistory()
    accounts = try await sink.loadAccountHistory()
  }

  /// The term entries, newest first, parsed from their stored form.
  public var termEntries: [SearchHistoryEntry] {
    terms.map(SearchHistoryCoding.parse)
  }

  /// The stored term strings, newest first.
  public var rawTermHistory: [String] { terms }

  /// The stored account DIDs, newest first.
  public var accountHistory: [String] { accounts }

  /// Records a term search, moving it to the front and deduping on the
  /// serialized form.
  ///
  /// An empty query is ignored, matching the RN `if (!q) return`.
  @discardableResult
  public func addTerm(
    _ q: String, filters: SearchFilters = SearchFilters()
  ) async throws -> [SearchHistoryEntry] {
    guard !q.isEmpty else { return termEntries }
    let item = SearchHistoryCoding.serialize(q: q, filters: filters)
    var next = [item]
    next.append(contentsOf: terms.filter { $0 != item })
    terms = Array(next.prefix(Self.termLimit))
    try await sink.saveTermHistory(terms)
    return termEntries
  }

  /// Removes a term entry by its stored form.
  @discardableResult
  public func removeTerm(_ stored: String) async throws -> [SearchHistoryEntry] {
    terms = terms.filter { $0 != stored }
    try await sink.saveTermHistory(terms)
    return termEntries
  }

  /// Clears the whole term history.
  public func clearTerms() async throws {
    terms = []
    try await sink.saveTermHistory(terms)
  }

  /// Records a profile visit, moving the DID to the front.
  ///
  /// Ported from `updateProfileHistory`, which is keyed on DID rather than
  /// handle so a handle change does not duplicate the entry.
  @discardableResult
  public func addAccount(_ did: String) async throws -> [String] {
    var next = [did]
    next.append(contentsOf: accounts.filter { $0 != did })
    accounts = Array(next.prefix(Self.accountLimit))
    try await sink.saveAccountHistory(accounts)
    return accounts
  }

  /// Removes an account entry by DID.
  @discardableResult
  public func removeAccount(_ did: String) async throws -> [String] {
    accounts = accounts.filter { $0 != did }
    try await sink.saveAccountHistory(accounts)
    return accounts
  }

  /// Clears the whole account history.
  public func clearAccounts() async throws {
    accounts = []
    try await sink.saveAccountHistory(accounts)
  }
}
