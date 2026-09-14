import Foundation
import Testing

@testable import QueryStore

/// Covers the `QueryStore` semantics the RN app relies on from TanStack Query:
/// fetch-on-demand with staleness checks, de-duplicated concurrent fetches,
/// invalidation, `setQueryData` optimism, per-key stale times, and error
/// preservation until a successful refetch.
@Suite("QueryStore fetch semantics")
struct QueryStoreTests {
  private func makeStore(
    clock: ManualQueryClock = ManualQueryClock(),
    defaultStaleTime: TimeInterval = STALE.MINUTES.ONE
  ) -> QueryStore {
    QueryStore(clock: clock, defaultStaleTime: defaultStaleTime)
  }

  // MARK: - Fetch on demand

  @Test("a first fetch populates the entry and records it as fresh")
  func firstFetch() async throws {
    let clock = ManualQueryClock()
    let store = makeStore(clock: clock)
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")

    let value = try await store.fetch(key) { try await fetcher.call(.firstPage) }

    #expect(value == "page-1")
    #expect(fetcher.callCount == 1)

    let entry = await store.entry(key, as: String.self)
    #expect(entry.status == .success)
    #expect(entry.data == "page-1")
    #expect(entry.fetchedAt == clock.nowMicroseconds())
    #expect(entry.isStale(now: clock.nowMicroseconds()) == false)
  }

  @Test("a fresh entry is not refetched")
  func freshEntryIsNotRefetched() async throws {
    let clock = ManualQueryClock()
    let store = makeStore(clock: clock)
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    clock.advance(by: 30)
    let second = try await store.fetch(key) { try await fetcher.call(.firstPage) }

    #expect(second == "page-1")
    #expect(fetcher.callCount == 1, "a call inside the stale window must be served from cache")
  }

  @Test("stale data is refetched on demand, and the old value stays visible meanwhile")
  func staleRefetch() async throws {
    let clock = ManualQueryClock()
    let store = makeStore(clock: clock, defaultStaleTime: STALE.SECONDS.FIFTEEN)
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>([
      .value("page-1"),
      .delayed("page-2", milliseconds: 30),
    ])

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    clock.advance(by: STALE.SECONDS.FIFTEEN)

    #expect(await store.isStale(key))

    async let refreshed = store.fetch(key) { try await fetcher.call(.firstPage) }
    // While the refetch is in flight the old payload is still readable.
    try await Task.sleep(nanoseconds: 5_000_000)
    let duringRefetch = await store.entry(key, as: String.self)
    #expect(duringRefetch.data == "page-1", "stale data must remain readable during a refetch")
    #expect(duringRefetch.isFetching)

    let value = try await refreshed
    #expect(value == "page-2")
    #expect(fetcher.callCount == 2)
    let after = await store.entry(key, as: String.self)
    #expect(after.data == "page-2")
    #expect(after.isFetching == false)
  }

  @Test("force refetches inside the stale window")
  func forceRefetch() async throws {
    let clock = ManualQueryClock()
    let store = makeStore(clock: clock)
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    #expect(fetcher.callCount == 1)

    _ = try await store.fetch(key, force: true) { try await fetcher.call(.firstPage) }
    #expect(fetcher.callCount == 2)
  }

  @Test("a per-key staleTime override is remembered on the entry")
  func perKeyStaleTimeOverride() async throws {
    let clock = ManualQueryClock()
    let store = makeStore(clock: clock, defaultStaleTime: STALE.HOURS.ONE)
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")

    _ = try await store.fetch(key, staleTime: STALE.SECONDS.FIFTEEN) { try await fetcher.call(.firstPage) }
    #expect(await store.staleTime(for: key) == STALE.SECONDS.FIFTEEN)

    clock.advance(by: STALE.SECONDS.FIFTEEN)
    #expect(await store.isStale(key), "the override must win over the store default")
    #expect(await store.shouldFetch(key))

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    #expect(fetcher.callCount == 2)
  }

  // MARK: - In-flight dedupe

  @Test("concurrent fetches for one key collapse into a single request")
  func inFlightDedupe() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>([
      .delayed("page-1", milliseconds: 40),
      .value("should-not-be-used"),
    ])

    let calls = Recorder<String>()
    async let first = store.fetch(key) { try await fetcher.call(.firstPage) }
    async let second = store.fetch(key) { try await fetcher.call(.firstPage) }
    async let third = store.fetch(key) { try await fetcher.call(.firstPage) }
    let values = try await [first, second, third]
    values.forEach { calls.record($0) }

    #expect(fetcher.callCount == 1, "one in-flight task per key")
    #expect(calls.values == ["page-1", "page-1", "page-1"])
    #expect(await store.isFetching(key) == false)
  }

  @Test("dedupe is per key, not global")
  func dedupeIsPerKey() async throws {
    let store = makeStore()
    let first = feedKey(limit: 30)
    let second = feedKey(limit: 10)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")

    async let a = store.fetch(first) { try await fetcher.call(.firstPage) }
    async let b = store.fetch(second) { try await fetcher.call(.firstPage) }
    _ = try await (a, b)

    #expect(fetcher.callCount == 2, "different keys run independent requests")
  }

  @Test("a fetch started while one is in flight joins it rather than queueing another")
  func joinsInFlightInsteadOfQueueing() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>([
      .delayed("page-1", milliseconds: 30),
      .value("page-2"),
    ])

    async let first = store.fetch(key) { try await fetcher.call(.firstPage) }
    try await Task.sleep(nanoseconds: 5_000_000)
    async let second = store.fetch(key, force: true) { try await fetcher.call(.firstPage) }
    let values = try await [first, second]

    #expect(values == ["page-1", "page-1"])
    #expect(fetcher.callCount == 1, "a forced fetch still joins the in-flight request")
  }

  // MARK: - Invalidation

  @Test("invalidation preserves data and refetches in the background")
  func invalidationPreservesData() async throws {
    let clock = ManualQueryClock()
    let store = makeStore(clock: clock)
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>([
      .value("page-1"),
      .delayed("page-2", milliseconds: 20),
    ])

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    #expect(await store.isStale(key) == false)

    async let invalidated = store.invalidate(key)
    try await Task.sleep(nanoseconds: 5_000_000)
    let during = await store.entry(key, as: String.self)
    #expect(during.data == "page-1", "invalidation must not clear the payload")
    #expect(during.isInvalidated)

    _ = await invalidated
    let after = await store.entry(key, as: String.self)
    #expect(after.data == "page-2")
    #expect(after.isInvalidated == false)
    #expect(fetcher.callCount == 2)
  }

  @Test("invalidating without refetching only marks the entry stale")
  func invalidateWithoutRefetch() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    _ = await store.invalidate(key, refetch: false)

    #expect(fetcher.callCount == 1)
    #expect(await store.isStale(key))
    let entry = await store.entry(key, as: String.self)
    #expect(entry.data == "page-1")
    #expect(entry.isInvalidated)
  }

  @Test("invalidation by root covers every key under that root")
  func invalidateByRoot() async throws {
    let store = makeStore()
    let first = feedKey(limit: 30)
    let second = feedKey(limit: 10)
    let unrelated = QueryKey(TestRoot.profile, FeedArgs(limit: 30))
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")

    _ = try await store.fetch(first) { try await fetcher.call(.firstPage) }
    _ = try await store.fetch(second) { try await fetcher.call(.firstPage) }
    _ = try await store.fetch(unrelated) { try await fetcher.call(.firstPage) }
    #expect(fetcher.callCount == 3)

    await store.invalidate(root: TestRoot.feed)

    #expect(fetcher.callCount == 5, "both feed keys refetch, the profile key does not")
    #expect(await store.isStale(unrelated) == false)
  }

  @Test("invalidation emits a fetch event carrying the invalidated reason")
  func invalidationEmitsReason() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")
    let events = EventRecorder()
    _ = await store.onEvent(events.closure)

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    _ = await store.invalidate(key)

    #expect(events.count(of: "started:\(key.description):invalidated") == 1)
    #expect(events.count(of: "succeeded:\(key.description)") == 2)
  }

  @Test("truncateAndInvalidate drops back to one page, then refetches")
  func truncateAndInvalidate() async throws {
    let store = makeStore()
    let key = QueryKey(TestRoot.feed, FeedArgs(limit: 30))
    let query = InfiniteQuery<String>(
      store: store,
      key: key,
      identity: { $0 },
      page: { cursor in
        switch cursor {
        case nil: return QueryPage(items: ["a", "b"], cursor: "c1")
        case "c1": return QueryPage(items: ["c", "d"], cursor: nil)
        default: return QueryPage(items: [], cursor: nil)
        }
      }
    )

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    #expect(await query.items() == ["a", "b", "c", "d"])

    _ = await store.truncateAndInvalidate(key)

    let state = await query.paginationState()
    #expect(state.pageCount == 1, "truncation leaves a single fresh head page")
    #expect(await query.items() == ["a", "b"])
  }

  // MARK: - setQueryData and optimism

  @Test("setQueryData writes a payload and marks it fresh")
  func setQueryData() async throws {
    let clock = ManualQueryClock()
    let store = makeStore(clock: clock)
    let key = QueryKey(TestRoot.profile, FeedArgs(limit: 30))

    await store.setQueryData(ProfilePayload(did: "did:plc:alice", displayName: "Alice"), for: key)

    let entry = await store.entry(key, as: ProfilePayload.self)
    #expect(entry.data?.displayName == "Alice")
    #expect(entry.status == .success)
    #expect(entry.fetchedAt == clock.nowMicroseconds())
    #expect(await store.isStale(key) == false)
  }

  @Test("updateQueryData rewrites the payload in place")
  func updateQueryData() async throws {
    let store = makeStore()
    let key = QueryKey(TestRoot.profile, FeedArgs(limit: 30))
    await store.setQueryData(ProfilePayload(did: "did:plc:alice", displayName: "Alice"), for: key)

    await store.updateQueryData(key, as: ProfilePayload.self) { current in
      ProfilePayload(did: current.did, displayName: "Alice B.")
    }

    let entry = await store.entry(key, as: ProfilePayload.self)
    #expect(entry.data?.displayName == "Alice B.")
  }

  @Test("an optimistic update rolls back when the request fails")
  func optimisticUpdateAndRollback() async throws {
    let store = makeStore()
    let key = QueryKey(TestRoot.profile, FeedArgs(limit: 30))
    let original = ProfilePayload(did: "did:plc:alice", displayName: "Alice")
    await store.setQueryData(original, for: key)

    // The snapshot taken before the optimism is what the rollback restores.
    let snapshot = await store.entry(key, as: ProfilePayload.self).data
    await store.setQueryData(
      ProfilePayload(did: original.did, displayName: "Alice (optimistic)"), for: key)

    let fetcher = ScriptedFetcher<ProfilePayload>([.failure(TestError("write rejected"))])
    var observedFailureCount = 0
    do {
      _ = try await store.fetch(key, force: true) { try await fetcher.call(.firstPage) }
      Issue.record("the fetch should have thrown")
    } catch {
      // The failed request leaves the optimistic value in place, so the caller
      // restores the snapshot it took before optimistically writing - the same
      // shape as the RN onError rollback.
      observedFailureCount = await store.entry(key, as: ProfilePayload.self).failureCount
      if let snapshot {
        await store.setQueryData(snapshot, for: key)
      }
    }

    #expect(observedFailureCount == 1, "the failed write is counted on the entry")
    let entry = await store.entry(key, as: ProfilePayload.self)
    #expect(entry.data == original, "the pre-optimism snapshot must be restored")
  }

  // MARK: - Error handling

  @Test("a failed first fetch records the error and no data")
  func failedFirstFetch() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>([.failure(TestError("offline"))])

    do {
      _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
      Issue.record("the fetch should have thrown")
    } catch let error as TestError {
      #expect(error.message == "offline")
    }

    let entry = await store.entry(key, as: String.self)
    #expect(entry.status == .error)
    #expect(entry.data == nil)
    #expect(entry.failureCount == 1)
    #expect((entry.error as? TestError)?.message == "offline")
    #expect(await store.isFetching(key) == false)
  }

  @Test("an error is preserved until a successful refetch clears it")
  func errorPreservedUntilSuccess() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>([
      .value("page-1"),
      .failure(TestError("offline")),
      .value("page-2"),
    ])

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    _ = try? await store.fetch(key, force: true) { try await fetcher.call(.firstPage) }

    let afterFailure = await store.entry(key, as: String.self)
    #expect(afterFailure.data == "page-1", "the old payload survives a failed refetch")
    #expect(afterFailure.status == .error)
    #expect(afterFailure.error != nil)

    _ = try await store.fetch(key, force: true) { try await fetcher.call(.firstPage) }

    let afterSuccess = await store.entry(key, as: String.self)
    #expect(afterSuccess.data == "page-2")
    #expect(afterSuccess.error == nil, "a successful refetch clears the error")
    #expect(afterSuccess.status == .success)
    #expect(afterSuccess.failureCount == 0)
  }

  @Test("a failed fetch reports whether data was preserved")
  func failureEventReportsPreservedData() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>([
      .value("page-1"),
      .failure(TestError("offline")),
    ])
    let events = EventRecorder()
    _ = await store.onEvent(events.closure)

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    _ = try? await store.fetch(key, force: true) { try await fetcher.call(.firstPage) }

    #expect(events.count(of: "failed:\(key.description):hadData=true") == 1)
  }

  // MARK: - Type safety

  @Test("reading a key as the wrong payload type throws a type mismatch")
  func typeMismatch() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")
    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }

    do {
      _ = try await store.payload(key, as: ProfilePayload.self)
      Issue.record("reading as the wrong type should throw")
    } catch let error as QueryTypeMismatchError {
      #expect(error.key == key)
      #expect(error.expected.contains("ProfilePayload"))
    }
  }

  // MARK: - Subscribers

  @Test("subscribers receive the current payload immediately and each change after")
  func subscribeReceivesPayloads() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    await store.setQueryData(ProfilePayload(did: "did:plc:alice", displayName: "Alice"), for: key)

    let seen = Recorder<String>()
    let subscription = await store.subscribe(key, as: ProfilePayload.self) { payload in
      seen.record(payload.displayName)
    }

    #expect(seen.values == ["Alice"], "a subscriber is primed with the current value")
    #expect(await store.subscriberCount(for: key) == 1)

    await store.updateQueryData(key, as: ProfilePayload.self) { current in
      ProfilePayload(did: current.did, displayName: "Alice B.")
    }
    #expect(seen.values == ["Alice", "Alice B."])

    await subscription.cancel()
    await store.updateQueryData(key, as: ProfilePayload.self) { current in
      ProfilePayload(did: current.did, displayName: "Alice C.")
    }
    #expect(seen.values == ["Alice", "Alice B."], "a cancelled subscription stops receiving")
    #expect(await store.subscriberCount(for: key) == 0)
  }

  @Test("subscribers are notified when a fetch completes")
  func subscribersSeeFetchCompletion() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")
    let seen = Recorder<String>()
    _ = await store.subscribe(key, as: String.self) { seen.record($0) }

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }

    #expect(seen.values == ["page-1"])
  }

  // MARK: - Removal

  @Test("removing a key clears its entry and notifies")
  func removeKey() async throws {
    let store = makeStore()
    let key = feedKey(limit: 30)
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")
    let events = EventRecorder()
    _ = await store.onEvent(events.closure)

    _ = try await store.fetch(key) { try await fetcher.call(.firstPage) }
    await store.remove(key)

    #expect(await store.snapshot(for: key) == nil)
    #expect(await store.entryCount == 0)
    #expect(events.count(of: "removed:\(key.description)") == 1)
  }

  @Test("removeAll clears every entry, as on sign-out")
  func removeAll() async throws {
    let store = makeStore()
    let fetcher = ScriptedFetcher<String>(fallback: "page-1")
    _ = try await store.fetch(feedKey(limit: 30)) { try await fetcher.call(.firstPage) }
    _ = try await store.fetch(feedKey(limit: 10)) { try await fetcher.call(.firstPage) }
    #expect(await store.entryCount == 2)

    await store.removeAll()

    #expect(await store.entryCount == 0)
    #expect(await store.keys.isEmpty)
  }

  @Test("scoped keys keep accounts' entries apart in one store")
  func perScopeIsolation() async throws {
    let store = makeStore()
    let alice = feedKey(limit: 30, scope: "did:plc:alice")
    let bob = feedKey(limit: 30, scope: "did:plc:bob")
    let fetcher = ScriptedFetcher<String>([.value("alice-page"), .value("bob-page")])

    async let aliceValue = store.fetch(alice) { try await fetcher.call(.firstPage) }
    async let bobValue = store.fetch(bob) { try await fetcher.call(.firstPage) }
    let values = try await [aliceValue, bobValue]

    #expect(values == ["alice-page", "bob-page"])
    #expect(await store.entry(alice, as: String.self).data == "alice-page")
    #expect(await store.entry(bob, as: String.self).data == "bob-page")
  }
}
