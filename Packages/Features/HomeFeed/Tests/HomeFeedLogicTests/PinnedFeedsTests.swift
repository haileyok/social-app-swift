import ATProtoClient
import Foundation
import Lexicons
import Preferences
import QueryStore
import Testing

@testable import HomeFeedLogic

/// Pinned-feed resolution: ordering, batching, per-source XRPC sequences.
@Suite("Pinned feeds")
struct PinnedFeedsTests {
  let feedA = "at://did:plc:feeds/app.bsky.feed.generator/a"
  let feedB = "at://did:plc:feeds/app.bsky.feed.generator/b"
  let listURI = "at://did:plc:alice/app.bsky.graph.list/friends"

  @Test("pinned order follows the stored order, not the wire order")
  func storedOrderWins() async throws {
    let xrpc = RecordingFeedXrpc()
    // The batch read answers in the opposite order to the saved config.
    xrpc.setGenerators([
      Fixtures.generatorView(uri: feedB, displayName: "B"),
      Fixtures.generatorView(uri: feedA, displayName: "A"),
    ])
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.feedEntry(feedA, id: "a"),
      Fixtures.feedEntry(feedB, id: "b"),
    ])
    #expect(pinned.map(\.displayName) == ["A", "B"])
    #expect(pinned.map(\.config.value) == [feedA, feedB])
  }

  @Test("the timeline stays in position and needs no resolution call")
  func timelinePosition() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setGenerators([Fixtures.generatorView(uri: feedA, displayName: "A")])
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.timelineEntry(),
      Fixtures.feedEntry(feedA, id: "a"),
    ])
    #expect(pinned.count == 2)
    #expect(pinned[0].descriptor == .following)
    #expect(pinned[0].displayName == "Following")
    #expect(pinned[1].descriptor == .feedgen(uri: feedA))
    // Only the generator triggered a network read.
    #expect(xrpc.calls == [.feedGenerators(feeds: [feedA])])
  }

  @Test("the generator batch read sends every pinned generator URI at once")
  func generatorBatch() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setGenerators([
      Fixtures.generatorView(uri: feedA), Fixtures.generatorView(uri: feedB),
    ])
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    _ = try await resolver.resolveUncached(savedItems: [
      Fixtures.feedEntry(feedA, id: "a"), Fixtures.feedEntry(feedB, id: "b"),
    ])
    #expect(xrpc.calls == [.feedGenerators(feeds: [feedA, feedB])])
  }

  @Test("each pinned list is read individually with limit 1")
  func listReadsIndividual() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setLists([
      ListViewInfo(uri: listURI, name: "Friends", creatorHandle: "alice.test", creatorDid: "did:plc:alice")
    ])
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.listEntry(listURI)
    ])
    #expect(xrpc.calls == [.list(list: listURI)])
    #expect(pinned.first?.displayName == "Friends")
    #expect(pinned.first?.descriptor == .list(uri: listURI))
  }

  @Test("a failing generator batch fails the whole resolution")
  func generatorFailureFailsAll() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.fail("feedGenerators")
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    await #expect(throws: (any Error).self) {
      try await resolver.resolveUncached(savedItems: [Fixtures.feedEntry()])
    }
  }

  @Test("a failing list read is ignored, as RN's allSettled does")
  func listFailureIgnored() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.fail("list")
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.timelineEntry(), Fixtures.listEntry(listURI),
    ])
    // The timeline survives; the unresolvable list is dropped.
    #expect(pinned.map(\.descriptor) == [.following])
  }

  @Test("an unpinned feed is not resolved")
  func unpinnedIgnored() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.feedEntry(feedA, pinned: false)
    ])
    #expect(pinned.isEmpty)
    #expect(xrpc.calls.isEmpty)
  }

  @Test("a logged-out reader receives the Discover stub and makes no requests")
  func loggedOutStub() async throws {
    let xrpc = RecordingFeedXrpc()
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(
      store: store, xrpc: xrpc, isAuthenticated: false)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.timelineEntry()
    ])
    #expect(pinned.map(\.displayName) == ["Discover"])
    #expect(pinned.first?.config.value == FeedURIs.discover)
    #expect(xrpc.calls.isEmpty)
  }

  @Test("an unresolvable generator is dropped while the rest survive")
  func partialGeneratorResolution() async throws {
    let xrpc = RecordingFeedXrpc()
    // Only feedA has a view.
    xrpc.setGenerators([Fixtures.generatorView(uri: feedA, displayName: "A")])
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.feedEntry(feedA, id: "a"), Fixtures.feedEntry(feedB, id: "b"),
    ])
    #expect(pinned.map(\.config.value) == [feedA])
  }

  @Test("the resolution is cached under the feed-info key at fifteen-minute staleness")
  func resolutionCaching() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setGenerators([Fixtures.generatorView(uri: feedA, displayName: "A")])
    let store = QueryStore()
    let clock = ManualQueryClock()
    let scoped = QueryStore(clock: clock)
    let resolver = PinnedFeedsResolver(store: scoped, xrpc: xrpc, scope: "did:plc:me")

    _ = try await resolver.resolve(savedItems: [Fixtures.feedEntry(feedA, id: "a")])
    // A second call inside the stale window must not re-request.
    _ = try await resolver.resolve(savedItems: [Fixtures.feedEntry(feedA, id: "a")])
    #expect(xrpc.calls.count == 1)
    #expect(await scoped.staleTime(for: PinnedFeedsResolver.key(savedItems: [Fixtures.feedEntry(feedA, id: "a")], scope: "did:plc:me")) == HomeFeedStale.pinnedFeeds)
  }

  @Test("a generator with no display name falls back to 'Feed by @handle'")
  func displayNameFallback() async throws {
    let xrpc = RecordingFeedXrpc()
    xrpc.setGenerators([
      Fixtures.generatorView(uri: feedA, displayName: "", creatorHandle: "maker.test")
    ])
    let store = QueryStore()
    let resolver = PinnedFeedsResolver(store: store, xrpc: xrpc)

    let pinned = try await resolver.resolveUncached(savedItems: [
      Fixtures.feedEntry(feedA, id: "a")
    ])
    #expect(pinned.first?.displayName == "Feed by @maker.test")
  }
}

/// Saved-feed reading, ported from the `savedFeeds` reads in `feed.ts`.
///
/// The preferences value is produced through the real hydration path rather than
/// by constructing `Preferences` directly: `getPreferences` reads
/// `app.bsky.actor.getPreferences` and runs the v2 saved-feeds interpretation.
@Suite("Saved feed reading")
struct SavedFeedReaderTests {
  /// A `PreferencesEngine` whose transport answers `getPreferences` with
  /// `items` as the v2 saved-feeds pref.
  func preferences(_ items: [PrefObject]) async throws -> Preferences {
    let savedFeeds = PrefObject(fields: [
      "$type": JSONValue(PrefType.savedFeedsPrefV2),
      "items": JSONValue.array(items.map { JSONValue.object($0.fields) }),
    ])
    let payload: [String: Any] = [
      "preferences": [jsonObject(savedFeeds)]
    ]
    let transport = RecordingTransport(
      responseBody: try JSONSerialization.data(withJSONObject: payload))
    let client = XrpcClient(baseURL: "https://pds.example.com", transport: transport)
    let engine = PreferencesEngine(client: client)
    return try await engine.getPreferences()
  }

  /// Renders a `PrefObject` as a `JSONSerialization`-compatible dictionary.
  func jsonObject(_ object: PrefObject) -> [String: Any] {
    object.fields.mapValues(jsonValue)
  }

  func jsonValue(_ value: JSONValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let b): return b
    case .int(let i): return i
    case .double(let d): return d
    case .string(let s): return s
    case .array(let values): return values.map(jsonValue)
    case .object(let fields): return fields.mapValues(jsonValue)
    }
  }

  @Test("entries keep their stored order")
  func storedOrder() async throws {
    let prefs = try await preferences([
      Fixtures.savedFeedPref(id: "1", type: "timeline", value: "following", pinned: true),
      Fixtures.savedFeedPref(id: "2", type: "feed", value: "at://a", pinned: true),
      Fixtures.savedFeedPref(id: "3", type: "list", value: "at://l", pinned: true),
    ])
    let entries = SavedFeedReader.entries(from: prefs)
    #expect(entries.map(\.id) == ["1", "2", "3"])
    #expect(entries.map(\.type) == [.timeline, .feed, .list])
  }

  @Test("only pinned entries are returned by pinnedEntries")
  func pinnedFilter() async throws {
    let prefs = try await preferences([
      Fixtures.savedFeedPref(id: "1", type: "feed", value: "at://a", pinned: true),
      Fixtures.savedFeedPref(id: "2", type: "feed", value: "at://b", pinned: false),
    ])
    #expect(SavedFeedReader.pinnedEntries(from: prefs).map(\.id) == ["1"])
  }

  @Test("saved entries map onto the RN feed descriptors")
  func descriptorMapping() {
    #expect(Fixtures.timelineEntry().descriptor == .following)
    #expect(Fixtures.feedEntry("at://f").descriptor == .feedgen(uri: "at://f"))
    #expect(Fixtures.listEntry("at://l").descriptor == .list(uri: "at://l"))
  }

  @Test("an entry with no id is rejected by the initializer")
  func malformedDropped() {
    let withoutId = PrefObject(fields: [
      "type": JSONValue("feed"), "value": JSONValue("at://a"),
    ])
    #expect(SavedFeedEntry(prefObject: withoutId) == nil)
  }

  @Test("a missing type is inferred from the URI")
  func typeInferred() {
    let noType = PrefObject(fields: [
      "id": JSONValue("1"),
      "value": JSONValue("at://did:plc:a/app.bsky.feed.generator/cool"),
      "pinned": JSONValue(true),
    ])
    #expect(SavedFeedEntry(prefObject: noType)?.type == .feed)
  }
}
