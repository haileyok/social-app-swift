import Foundation

/// Persistence internals: composing snapshots, restoring them, and the
/// scope bookkeeping that keeps one account's cache out of another's.
extension QueryStore {
  // MARK: - Internals: persistence

  func schedulePersist() {
    guard persistSink != nil else { return }
    _ = startPersist()
  }

  @discardableResult
  func startPersist() -> Task<Void, Never>? {
    guard persistSink != nil else { return nil }
    if let persistTask { return persistTask }
    let task = Task { [weak self] in
      await self?.writePersistedState()
      await self?.clearPersistTask()
    }
    persistTask = task
    return task
  }

  func clearPersistTask() { persistTask = nil }

  func writePersistedState() async {
    guard let persistSink else { return }
    for snapshot in snapshotsForPersist() {
      try? await persistSink.save(snapshot)
    }
  }

  func snapshotsForPersist() -> [PersistedSnapshot] {
    var grouped: [String: [PersistedQuery]] = [:]
    for (key, entry) in entries {
      guard key.persistedVersion != nil, entry.status == .success, let data = entry.data else { continue }
      guard let bytes = data.encodedBytes() else { continue }
      let scope = key.scope ?? Self.loggedOutScope
      grouped[scope, default: []].append(
        PersistedQuery(
          keyIdentifier: key.description,
          root: key.keyRoot,
          scope: key.scope,
          persistedVersion: key.persistedVersion,
          args: key.argsDebugDescription,
          fetchedAt: entry.fetchedAt ?? clock.nowMicroseconds(),
          staleTime: entry.staleTime,
          payload: bytes
        )
      )
    }
    return grouped.map { scope, queries in
      PersistedSnapshot(
        scope: scope,
        buster: versionBuster,
        writtenAt: clock.nowMicroseconds(),
        entries: queries.sorted { $0.keyIdentifier < $1.keyIdentifier }
      )
    }
  }

  func restore(_ snapshot: PersistedSnapshot) -> Int {
    guard snapshot.buster == versionBuster else { return 0 }
    var restored = 0
    for persisted in snapshot.entries {
      guard persisted.persistedVersion != nil else { continue }
      let key = QueryKey(
        root: persisted.root,
        argsText: persisted.args,
        options: QueryOptions(scope: persisted.scope, persistedVersion: persisted.persistedVersion)
      )
      var entry = entries[key] ?? QueryEntry<StoredPayload>.empty(staleTime: persisted.staleTime)
      entry.status = .success
      entry.data = .encoded(persisted.payload)
      entry.fetchedAt = persisted.fetchedAt
      entry.staleTime = persisted.staleTime
      entry.isFetching = false
      entry.isInvalidated = false
      entries[key] = entry
      restored += 1
    }
    notify(event: .restored(count: restored))
    return restored
  }

  func knownScopes() -> [String] {
    Set(entries.keys.map { $0.scope ?? Self.loggedOutScope }).union([Self.loggedOutScope]).sorted()
  }

}
extension QueryStore {
  // MARK: - Internals: type erasure

  static func cast<Data: Sendable>(
    _ payload: any Sendable,
    key: QueryKey,
    as type: Data.Type
  ) throws -> Data {
    guard let typed = payload as? Data else {
      throw QueryTypeMismatchError(key: key, expected: String(describing: Data.self))
    }
    return typed
  }
}
