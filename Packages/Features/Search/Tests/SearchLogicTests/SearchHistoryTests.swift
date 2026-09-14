import Foundation
import Lexicons
import Persistence
import Testing

@testable import SearchLogic

/// An in-memory ``SearchHistorySink`` for tests.
///
/// Also records the writes it receives, so a test can assert the whole list is
/// written back on each mutation (the RN `setTermHistory(newList)` pattern).
actor InMemorySearchHistorySink: SearchHistorySink {
  private var terms: [String]
  private var accounts: [String]
  private(set) var savedTerms: [[String]] = []
  private(set) var savedAccounts: [[String]] = []

  init(terms: [String] = [], accounts: [String] = []) {
    self.terms = terms
    self.accounts = accounts
  }

  func loadTermHistory() async throws -> [String] { terms }
  func saveTermHistory(_ entries: [String]) async throws {
    terms = entries
    savedTerms.append(entries)
  }
  func loadAccountHistory() async throws -> [String] { accounts }
  func saveAccountHistory(_ dids: [String]) async throws {
    accounts = dids
    savedAccounts.append(dids)
  }
}

@Suite("SearchHistory")
struct SearchHistoryTests {
  @Test("adds a term to the front (MRU)")
  func addsToFront() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    try await history.addTerm("a")
    try await history.addTerm("b")
    #expect(await history.rawTermHistory == ["b", "a"])
  }

  @Test("dedupes a repeated term, moving it to the front")
  func dedupes() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    try await history.addTerm("a")
    try await history.addTerm("b")
    try await history.addTerm("a")
    #expect(await history.rawTermHistory == ["a", "b"])
  }

  @Test("caps term history at 6")
  func termCap() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    for term in ["a", "b", "c", "d", "e", "f", "g"] {
      try await history.addTerm(term)
    }
    #expect(await history.rawTermHistory == ["g", "f", "e", "d", "c", "b"])
    #expect(await history.rawTermHistory.count == SearchHistory.termLimit)
  }

  @Test("ignores an empty query")
  func ignoresEmpty() async throws {
    let sink = InMemorySearchHistorySink()
    let history = SearchHistory(sink: sink)
    try await history.addTerm("")
    #expect(await history.rawTermHistory.isEmpty)
    #expect(await sink.savedTerms.isEmpty)
  }

  @Test("dedupes on the serialized form, so filters make distinct entries")
  func dedupesOnSerialized() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    try await history.addTerm("cats")
    try await history.addTerm("cats", filters: SearchFilters(author: "alice"))
    #expect(await history.rawTermHistory.count == 2)
    try await history.addTerm("cats")
    #expect(await history.rawTermHistory.count == 2)
    #expect(await history.termEntries.first?.q == "cats")
    #expect(await history.termEntries.first?.filters == SearchFilters())
  }

  @Test("removes a term by its stored form")
  func removesTerm() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    try await history.addTerm("a")
    try await history.addTerm("b")
    try await history.removeTerm("b")
    #expect(await history.rawTermHistory == ["a"])
  }

  @Test("clears the whole term history")
  func clearsTerms() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    try await history.addTerm("a")
    try await history.clearTerms()
    #expect(await history.rawTermHistory.isEmpty)
  }

  @Test("adds an account by DID, deduped and capped at 10")
  func accountsMru() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    for index in 0..<12 { try await history.addAccount("did:plc:\(index)") }
    #expect(await history.accountHistory.count == SearchHistory.accountLimit)
    #expect(await history.accountHistory.first == "did:plc:11")
    try await history.addAccount("did:plc:5")
    #expect(await history.accountHistory.first == "did:plc:5")
    #expect(await history.accountHistory.count == SearchHistory.accountLimit)
  }

  @Test("removes and clears accounts")
  func accountsRemove() async throws {
    let history = SearchHistory(sink: InMemorySearchHistorySink())
    try await history.addAccount("did:plc:a")
    try await history.addAccount("did:plc:b")
    try await history.removeAccount("did:plc:a")
    #expect(await history.accountHistory == ["did:plc:b"])
    try await history.clearAccounts()
    #expect(await history.accountHistory.isEmpty)
  }

  @Test("writes the whole list back on each mutation")
  func writesWholeList() async throws {
    let sink = InMemorySearchHistorySink()
    let history = SearchHistory(sink: sink)
    try await history.addTerm("a")
    try await history.addTerm("b")
    #expect(await sink.savedTerms == [["a"], ["b", "a"]])
  }

  @Test("loads both lists from the sink")
  func loads() async throws {
    let sink = InMemorySearchHistorySink(terms: ["x"], accounts: ["did:plc:z"])
    let history = SearchHistory(sink: sink)
    try await history.load()
    #expect(await history.rawTermHistory == ["x"])
    #expect(await history.accountHistory == ["did:plc:z"])
  }
}

/// The `Persistence`-backed sink: proves the adapter round-trips through the
/// real account store, and that two accounts keep separate histories.
@Suite("PersistedSearchHistorySink")
struct PersistedSearchHistorySinkTests {
  /// A fresh temporary directory for one test.
  private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("search-history-\(UUID().uuidString)")
  }

  @Test("round-trips term and account history")
  func roundTrip() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stores = ScopedStores(directory: directory)
    let sink = PersistedSearchHistorySink(store: stores.account, did: "did:plc:me")
    let history = SearchHistory(sink: sink)
    try await history.addTerm("cats")
    try await history.addAccount("did:plc:alice")

    let reloaded = SearchHistory(sink: sink)
    try await reloaded.load()
    #expect(await reloaded.rawTermHistory == ["cats"])
    #expect(await reloaded.accountHistory == ["did:plc:alice"])
  }

  @Test("scopes history per account")
  func perAccount() async throws {
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stores = ScopedStores(directory: directory)
    let mine = SearchHistory(sink: PersistedSearchHistorySink(store: stores.account, did: "did:plc:me"))
    let theirs = SearchHistory(
      sink: PersistedSearchHistorySink(store: stores.account, did: "did:plc:you"))
    try await mine.addTerm("mine")
    try await theirs.addTerm("theirs")
    #expect(await mine.rawTermHistory == ["mine"])
    #expect(await theirs.rawTermHistory == ["theirs"])
  }
}
