import Foundation
import Persistence

/// The `Persistence`-backed ``SearchHistorySink``.
///
/// Mirrors the RN storage: account-scoped keys `searchTermHistory` and
/// `searchAccountHistory` in the account store, so two accounts keep separate
/// histories. The RN value at each key is a string array, which is what is
/// written here.
///
/// `SearchLogic` owns the protocol and this adapter; the concrete store comes
/// from ``Persistence/ScopedStores`` at the app layer.
public struct PersistedSearchHistorySink: SearchHistorySink {
  /// The RN key for term history.
  public static let termHistoryKey = "searchTermHistory"
  /// The RN key for account history.
  public static let accountHistoryKey = "searchAccountHistory"

  private let store: Storage<AccountSchemaMarker>
  /// The account DID the entries are scoped to.
  private let did: String

  public init(store: Storage<AccountSchemaMarker>, did: String) {
    self.store = store
    self.did = did
  }

  public func loadTermHistory() async throws -> [String] {
    await store.get([did], Self.termHistoryKey, as: [String].self) ?? []
  }

  public func saveTermHistory(_ entries: [String]) async throws {
    try await store.set([did], Self.termHistoryKey, value: entries)
  }

  public func loadAccountHistory() async throws -> [String] {
    await store.get([did], Self.accountHistoryKey, as: [String].self) ?? []
  }

  public func saveAccountHistory(_ dids: [String]) async throws {
    try await store.set([did], Self.accountHistoryKey, value: dids)
  }
}
