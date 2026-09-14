import Foundation
import Testing

@testable import QueryStore

/// Ported from `src/state/queries/util.ts` (`createQueryKey`) and
/// `src/state/queries/index.ts` (`STALE`, `GCTIME`).
@Suite("Query keys and staleness constants")
struct QueryKeyTests {
  @Test("keys built from the same root and args are equal")
  func identityFromRootAndArgs() {
    let first = QueryKey("feed", FeedArgs(limit: 30))
    let second = QueryKey("feed", FeedArgs(limit: 30))
    let otherArgs = QueryKey("feed", FeedArgs(limit: 10))
    let otherRoot = QueryKey("profile", FeedArgs(limit: 30))

    #expect(first == second)
    #expect(first != otherArgs, "different args must be different cache entries")
    #expect(first != otherRoot)
    #expect(first.hashValue == second.hashValue)
  }

  @Test("scope separates entries for the same root and args")
  func scopeIsPartOfIdentity() {
    let alice = QueryKey("feed", FeedArgs(limit: 30), options: QueryOptions(scope: "did:plc:alice"))
    let bob = QueryKey("feed", FeedArgs(limit: 30), options: QueryOptions(scope: "did:plc:bob"))

    #expect(alice != bob, "the RN app re-keys the provider on currentDid; scope is that boundary")
    #expect(alice.scope == "did:plc:alice")
    #expect(alice.unscoped() != alice)
    #expect(alice.unscoped().scoped(to: "did:plc:alice") == alice)
  }

  @Test("persistedVersion separates entries for the same root and args")
  func persistedVersionIsPartOfIdentity() {
    let v1 = QueryKey("feed-info", FeedArgs(limit: 30), options: QueryOptions(persistedVersion: 1))
    let v2 = QueryKey("feed-info", FeedArgs(limit: 30), options: QueryOptions(persistedVersion: 2))

    #expect(v1 != v2, "bumping the persisted version must bust the old cache entry")
    #expect(v1.persistedVersion == 1)
    #expect(v1.withPersistedVersion(2) == v2)
    #expect(v1.withPersistedVersion(nil).persistedVersion == nil)
  }

  @Test("description renders root, args, scope and version")
  func debugDescription() {
    let key = QueryKey(
      "feed-info",
      FeedArgs(limit: 30),
      options: QueryOptions(scope: "did:plc:alice", persistedVersion: 1)
    )

    #expect(key.description == "feed-info(FeedArgs(limit: 30))@did:plc:alice#v1")
    #expect(key.debugDescription.contains("root: feed-info"))
    #expect(key.debugDescription.contains("args: FeedArgs(limit: 30)"))
    #expect(key.debugDescription.contains("scope: did:plc:alice"))
    #expect(key.debugDescription.contains("version: 1"))
    #expect(key.argsDebugDescription == "FeedArgs(limit: 30)")
  }

  @Test("a key with no args still has a stable description")
  func noArgsKey() {
    let key = QueryKey("preferences")
    #expect(key.keyRoot == "preferences")
    #expect(key.options == .none)
    #expect(key.description == "preferences(NoQueryArgs())")
    #expect(key == QueryKey("preferences", options: .none))
  }

  @Test("STALE constants match the RN module")
  func staleConstants() {
    #expect(STALE.SECONDS.FIFTEEN == 15)
    #expect(STALE.SECONDS.THIRTY == 30)
    #expect(STALE.MINUTES.ONE == 60)
    #expect(STALE.MINUTES.THREE == 180)
    #expect(STALE.MINUTES.FIVE == 300)
    #expect(STALE.MINUTES.FIFTEEN == 900)
    #expect(STALE.MINUTES.THIRTY == 1800)
    #expect(STALE.HOURS.ONE == 3600)
    #expect(STALE.INFINITY.isInfinite)
  }

  @Test("GCTIME.INFINITY is non-finite, as in the RN module")
  func gctimeInfinity() {
    #expect(GCTIME.INFINITY.isInfinite)
  }

  @Test("INFINITY keeps an entry fresh forever")
  func infinityNeverStales() async {
    let clock = ManualQueryClock()
    let key = QueryKey("feed-info", FeedArgs(limit: 30), options: QueryOptions(persistedVersion: 1))
    let store = QueryStore(clock: clock, defaultStaleTime: STALE.INFINITY)
    let fetcher = ScriptedFetcher<String>(fallback: "value")

    _ = try? await store.fetch(key) { try await fetcher.call(.firstPage) }
    clock.advance(by: 60 * 60 * 24 * 365)

    #expect(await store.isStale(key) == false, "an INFINITY-stale entry is never stale")
    #expect(await store.shouldFetch(key) == false)
    #expect(fetcher.callCount == 1)

    // A finite budget, by contrast, does go stale after the clock passes it.
    let finiteKey = QueryKey("other", FeedArgs(limit: 30))
    let finiteStore = QueryStore(clock: clock, defaultStaleTime: STALE.SECONDS.FIFTEEN)
    _ = try? await finiteStore.fetch(finiteKey) { try await fetcher.call(.firstPage) }
    clock.advance(by: STALE.SECONDS.FIFTEEN)
    #expect(await finiteStore.isStale(finiteKey))
  }

  @Test("QueryOptions default to no scope and no persisted version")
  func queryOptionsDefaults() {
    #expect(QueryOptions().scope == nil)
    #expect(QueryOptions().persistedVersion == nil)
    #expect(QueryOptions.none == QueryOptions())
  }
}
