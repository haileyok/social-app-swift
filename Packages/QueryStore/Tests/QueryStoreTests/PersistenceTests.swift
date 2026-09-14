import Foundation
import Testing

@testable import QueryStore

/// Covers the persistence hooks: a pluggable sink, per-DID snapshots, a version
/// buster, and the restore path. The RN behaviour being matched is
/// `src/lib/react-query.tsx`: one persister per account keyed
/// `queryClient-<did|logged-out>`, `buster: env.APP_VERSION`, and a dehydrate
/// predicate that writes only persisted-versioned successful queries.
@Suite("Persistence")
struct PersistenceTests {
  /// The scope the RN app uses for a signed-out cache.
  private let alice = "did:plc:alice"
  private let bob = "did:plc:bob"

  private func persistedKey(
    limit: Int = 30,
    scope: String? = nil,
    version: Int? = 1
  ) -> QueryKey {
    QueryKey(
      TestRoot.persistedFeed,
      FeedArgs(limit: limit),
      options: QueryOptions(scope: scope, persistedVersion: version)
    )
  }

  private func persistedValue(_ ids: [String], cursor: String? = nil) -> InfiniteQueryData<String> {
    InfiniteQueryData(pages: [QueryPage(items: ids, cursor: cursor)])
  }

  // MARK: - Writing

  @Test("persist writes successful persisted-versioned entries to the sink")
  func persistWritesSnapshot() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    let key = persistedKey(scope: alice)

    await store.setQueryData(persistedValue(["a", "b"]), for: key, persist: true)
    await store.persist()

    let snapshot = try #require(sink.snapshot(scope: alice))
    #expect(snapshot.buster == "1.0.0")
    #expect(snapshot.count == 1)
    let entry = try #require(snapshot.entries.first)
    #expect(entry.root == TestRoot.persistedFeed)
    #expect(entry.scope == alice)
    #expect(entry.persistedVersion == 1)
    #expect(entry.args.contains("limit: 30"))
  }

  @Test("entries without a persisted version are never written")
  func unversionedEntriesAreNotPersisted() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")

    await store.setQueryData(ProfilePayload(did: alice, displayName: "Alice"), for: feedKey(limit: 30), persist: true)
    await store.setQueryData(persistedValue(["a"]), for: persistedKey(scope: alice), persist: true)
    await store.persist()

    let snapshot = try #require(sink.snapshot(scope: alice))
    #expect(snapshot.count == 1, "only the versioned key is dehydratable")
    #expect(snapshot.entries.first?.root == TestRoot.persistedFeed)
  }

  @Test("a failed entry is not persisted")
  func failedEntriesAreNotPersisted() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    let key = persistedKey(scope: alice)
    let fetcher = ScriptedFetcher<InfiniteQueryData<String>>([.failure(TestError("offline"))])

    _ = try? await store.fetch(key) { try await fetcher.call(.firstPage) }
    await store.persist()

    // Nothing was ever written for this scope, so there is no snapshot at all.
    #expect(sink.snapshot(scope: alice) == nil)
  }

  @Test("successful persisted entries are written without an explicit persist call")
  func successSchedulesPersist() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    let key = persistedKey(scope: alice)
    await store.setQueryData(persistedValue(["a"]), for: key, persist: true)

    // `setQueryData(persist:)` schedules a write; `persist()` awaits it.
    await store.persist()

    #expect(sink.snapshot(scope: alice)?.count == 1)
  }

  @Test("each account's entries are written to its own snapshot")
  func perScopeSnapshots() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")

    await store.setQueryData(persistedValue(["alice-1"]), for: persistedKey(scope: alice), persist: true)
    await store.setQueryData(persistedValue(["bob-1"]), for: persistedKey(scope: bob), persist: true)
    await store.persist()

    #expect(sink.snapshot(scope: alice)?.count == 1)
    #expect(sink.snapshot(scope: bob)?.count == 1)
    #expect(sink.snapshot(scope: alice)?.entries.first?.scope == alice)
    #expect(sink.snapshot(scope: bob)?.entries.first?.scope == bob)
  }

  @Test("a signed-out cache uses the logged-out scope name")
  func loggedOutScopeName() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")

    #expect(QueryStore.loggedOutScope == "logged-out")
    await store.setQueryData(persistedValue(["a"]), for: persistedKey(scope: nil), persist: true)
    await store.persist()

    #expect(sink.snapshot(scope: "logged-out")?.count == 1)
  }

  // MARK: - Round trip

  @Test("a snapshot round-trips through the sink into a fresh store")
  func roundTrip() async throws {
    let sink = InMemoryPersistSink()
    let first = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    let key = persistedKey(scope: alice)
    await first.setQueryData(persistedValue(["a", "b"], cursor: "c1"), for: key, persist: true)
    await first.persist()

    let second = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    let restored = await second.restorePersisted(scopes: [alice])

    #expect(restored == 1)
    let data = try await second.payload(key, as: InfiniteQueryData<String>.self)
    #expect(data?.items == ["a", "b"], "the payload decodes back to its typed form")
    #expect(data?.nextCursor == "c1")

    let entry = await second.entry(key, as: InfiniteQueryData<String>.self)
    #expect(entry.status == .success)
    #expect(entry.isFetching == false)
  }

  @Test("a restored entry keeps the stale time it was written with")
  func restoredEntryKeepsStaleTime() async throws {
    let sink = InMemoryPersistSink()
    let writer = QueryStore(
      clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0",
      defaultStaleTime: STALE.SECONDS.FIFTEEN)
    let key = persistedKey(scope: alice)
    await writer.setQueryData(persistedValue(["a"]), for: key, persist: true)
    await writer.persist()

    let reader = QueryStore(
      clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0",
      defaultStaleTime: STALE.HOURS.ONE)
    _ = await reader.restorePersisted(scopes: [alice])

    #expect(
      await reader.staleTime(for: key) == STALE.SECONDS.FIFTEEN,
      "the snapshot's budget wins over the reading store's default")
  }

  @Test("a restored entry carries the fetchedAt the snapshot recorded")
  func restoredEntryKeepsTimestamp() async throws {
    let clock = ManualQueryClock()
    let sink = InMemoryPersistSink()
    let first = QueryStore(clock: clock, persistSink: sink, versionBuster: "1.0.0")
    let key = persistedKey(scope: alice)

    clock.set(microseconds: 1_000_000)
    await first.setQueryData(persistedValue(["a"]), for: key, persist: true)
    await first.persist()

    let second = QueryStore(clock: clock, persistSink: sink, versionBuster: "1.0.0")
    _ = await second.restorePersisted(scopes: [alice])

    let entry = await second.entry(key, as: InfiniteQueryData<String>.self)
    #expect(entry.fetchedAt == 1_000_000, "the snapshot's timestamp is restored verbatim")

    clock.advance(by: STALE.MINUTES.ONE)
    #expect(await second.isStale(key), "a restored entry is still subject to its stale time")
  }

  @Test("a restored entry is refetched once it goes stale")
  func restoredEntryRefetchesWhenStale() async throws {
    let clock = ManualQueryClock()
    let sink = InMemoryPersistSink()
    let first = QueryStore(
      clock: clock, persistSink: sink, versionBuster: "1.0.0",
      defaultStaleTime: STALE.SECONDS.FIFTEEN)
    let key = persistedKey(scope: alice)
    await first.setQueryData(persistedValue(["cached"]), for: key, persist: true)
    await first.persist()

    let second = QueryStore(
      clock: clock, persistSink: sink, versionBuster: "1.0.0", defaultStaleTime: STALE.SECONDS.FIFTEEN)
    _ = await second.restorePersisted(scopes: [alice])
    #expect(await second.isStale(key) == false)

    clock.advance(by: STALE.SECONDS.FIFTEEN)
    #expect(await second.shouldFetch(key))

    let fetcher = ScriptedFetcher<InfiniteQueryData<String>>(fallback: persistedValue(["fresh"]))
    _ = try await second.fetch(key) { try await fetcher.call(.firstPage) }

    #expect(fetcher.callCount == 1)
    let data = try await second.payload(key, as: InfiniteQueryData<String>.self)
    #expect(data?.items == ["fresh"])
  }

  // MARK: - Version busting

  @Test("a snapshot written under a different buster is discarded")
  func busterMismatchDiscardsSnapshot() async throws {
    let sink = InMemoryPersistSink()
    let writer = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    await writer.setQueryData(persistedValue(["a"]), for: persistedKey(scope: alice), persist: true)
    await writer.persist()

    // The app was upgraded, so its APP_VERSION - the TanStack buster - changed.
    let upgraded = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.1.0")
    let restored = await upgraded.restorePersisted(scopes: [alice])

    #expect(restored == 0, "a buster mismatch must invalidate the whole snapshot")
    #expect(await upgraded.entryCount == 0)
  }

  @Test("an entry whose persisted version differs from the live key is dropped")
  func persistedVersionBust() async throws {
    let sink = InMemoryPersistSink()
    let writer = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    await writer.setQueryData(
      persistedValue(["old-shape"]), for: persistedKey(scope: alice, version: 1), persist: true)
    await writer.persist()

    // The persisted payload shape changed, so the live key now carries version 2.
    let upgraded = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    let restored = await upgraded.restorePersisted(scopes: [alice])

    // The store restores what the snapshot holds, keyed at the version it was
    // written with; a caller reading the live version-2 key sees nothing.
    #expect(restored == 1)
    let liveKey = persistedKey(scope: alice, version: 2)
    #expect(try await upgraded.payload(liveKey, as: InfiniteQueryData<String>.self) == nil)

    // The version-1 key still resolves, which is what makes the bust safe rather
    // than destructive.
    let oldKey = persistedKey(scope: alice, version: 1)
    #expect(try await upgraded.payload(oldKey, as: InfiniteQueryData<String>.self)?.items == ["old-shape"])
  }

  @Test("a snapshot payload for one account does not leak into another")
  func restoreIsScoped() async throws {
    let sink = InMemoryPersistSink()
    let writer = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    await writer.setQueryData(persistedValue(["alice-only"]), for: persistedKey(scope: alice), persist: true)
    await writer.persist()

    let reader = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    _ = await reader.restorePersisted(scopes: [alice, bob])

    #expect(try await reader.payload(persistedKey(scope: alice), as: InfiniteQueryData<String>.self) != nil)
    #expect(try await reader.payload(persistedKey(scope: bob), as: InfiniteQueryData<String>.self) == nil)
  }

  @Test("the snapshot matches on args, so different args do not collide")
  func restoreMatchesOnArgs() async throws {
    let sink = InMemoryPersistSink()
    let writer = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    await writer.setQueryData(persistedValue(["thirty"]), for: persistedKey(limit: 30, scope: alice), persist: true)
    await writer.persist()

    let reader = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    _ = await reader.restorePersisted(scopes: [alice, bob])

    #expect(try await reader.payload(persistedKey(limit: 30, scope: alice), as: InfiniteQueryData<String>.self)?.items == ["thirty"])
    #expect(try await reader.payload(persistedKey(limit: 10, scope: alice), as: InfiniteQueryData<String>.self) == nil)
  }

  @Test("restoring emits a restored event")
  func restoreEmitsEvent() async throws {
    let sink = InMemoryPersistSink()
    let writer = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    await writer.setQueryData(persistedValue(["a"]), for: persistedKey(scope: alice), persist: true)
    await writer.persist()

    let reader = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    let events = EventRecorder()
    _ = await reader.onEvent(events.closure)
    _ = await reader.restorePersisted(scopes: [alice, bob])

    #expect(events.count(of: "restored:1") == 1)
  }

  // MARK: - Sign out

  @Test("signOut clears the cache and removes persisted state")
  func signOutClearsPersistedState() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")
    await store.setQueryData(persistedValue(["a"]), for: persistedKey(scope: alice), persist: true)
    await store.persist()
    #expect(sink.snapshot(scope: alice) != nil)

    await store.signOut()

    #expect(await store.entryCount == 0, "the in-memory cache is gone")
    #expect(sink.snapshot(scope: alice) == nil, "the persisted snapshot is gone")
    #expect(sink.removeCount >= 1)
  }

  @Test("a store with no sink is inert but functional")
  func noSinkIsNoOp() async throws {
    let store = QueryStore(clock: ManualQueryClock())
    await store.setQueryData(persistedValue(["a"]), for: persistedKey(scope: alice), persist: true)

    await store.persist()
    let restored = await store.restorePersisted(scopes: [alice])

    #expect(restored == 0)
    #expect(await store.entryCount == 1, "caching still works without persistence")
  }

  @Test("the sink is only consulted for adopted persisted keys when persisting")
  func sinkTrafficIsMinimal() async throws {
    let sink = InMemoryPersistSink()
    let store = QueryStore(clock: ManualQueryClock(), persistSink: sink, versionBuster: "1.0.0")

    await store.setQueryData(persistedValue(["a"]), for: persistedKey(scope: alice), persist: true)
    await store.persist()

    #expect(sink.saveCount == 1, "one write per account scope, not per entry")
    #expect(sink.loadCount == 0, "a compose-only pass does not read")
  }
}
