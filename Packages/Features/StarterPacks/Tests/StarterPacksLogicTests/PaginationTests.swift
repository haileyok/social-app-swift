import Foundation
import Lexicons
import QueryStore
import Testing

@testable import StarterPacksLogic

/// A clock the tests drive, so staleness is deterministic.
final class TestClock: QueryClock, @unchecked Sendable {
  private let lock = NSLock()
  private var micros: Int64 = 0

  func nowMicroseconds() -> Int64 { lock.withLock { micros } }

  /// Advances the clock.
  func advance(seconds: TimeInterval) {
    lock.withLock { micros += Int64(seconds * 1_000_000) }
  }
}

/// Asserts the paged member, actor and search queries.
@Suite("StarterPackPagination")
struct PaginationTests {
  private func store() -> QueryStore {
    QueryStore(clock: TestClock())
  }

  // MARK: - Members

  @Test("the paged member read asks for the RN page size and no cursor first")
  func membersFirstPage() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setListPages([StarterPackListMembersPage(items: [Fixtures.listItem(Fixtures.memberDID)])])
    let query = StarterPackMembersQuery(store: store(), xrpc: xrpc, listURI: Fixtures.listURI())

    let items = try await query.loadFirstPage()
    #expect(items.count == 1)
    #expect(
      xrpc.calls == [
        .getList(list: Fixtures.listURI(), cursor: nil, limit: StarterPackConstants.listMembersPageSize)
      ])
  }

  @Test("the member walk follows the cursor and accumulates")
  func membersPagination() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setListPages([
      StarterPackListMembersPage(
        cursor: "c1", items: [Fixtures.listItem("did:plc:a", rkey: "a")]),
      StarterPackListMembersPage(
        cursor: "c2", items: [Fixtures.listItem("did:plc:b", rkey: "b")]),
      StarterPackListMembersPage(items: [Fixtures.listItem("did:plc:c", rkey: "c")]),
    ])
    let query = StarterPackMembersQuery(store: store(), xrpc: xrpc, listURI: Fixtures.listURI())

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    _ = try await query.loadMore()

    let items = await query.items()
    #expect(items.map { $0.subject.did.rawValue } == ["did:plc:a", "did:plc:b", "did:plc:c"])
    let cursors = xrpc.calls.map { call -> String? in
      if case .getList(_, let cursor, _) = call { return cursor } else { return nil }
    }
    #expect(cursors == [nil, "c1", "c2"])
  }

  @Test("the member walk stops at the terminal page")
  func membersTerminal() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setListPages([StarterPackListMembersPage(items: [Fixtures.listItem(Fixtures.memberDID)])])
    let query = StarterPackMembersQuery(store: store(), xrpc: xrpc, listURI: Fixtures.listURI())

    _ = try await query.loadFirstPage()
    let state = await query.paginationState()
    #expect(state.hasNextPage == false)

    // Loading more at the end is a no-op, not an error and not a request.
    _ = try await query.loadMore()
    #expect(xrpc.calls.count == 1)
  }

  @Test("the exhaustive member walk pages at 50 and forwards the cursor")
  func allMembersWalk() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setListPages([
      StarterPackListMembersPage(cursor: "c1", items: [Fixtures.listItem("did:plc:a", rkey: "a")]),
      StarterPackListMembersPage(cursor: "c2", items: [Fixtures.listItem("did:plc:b", rkey: "b")]),
      StarterPackListMembersPage(items: [Fixtures.listItem("did:plc:c", rkey: "c")]),
    ])
    let items = try await StarterPackMembersQuery.allMembers(
      xrpc: xrpc, listURI: Fixtures.listURI())
    #expect(items.map { $0.subject.did.rawValue } == ["did:plc:a", "did:plc:b", "did:plc:c"])
    #expect(
      xrpc.calls.map { call -> Int in
        if case .getList(_, _, let limit) = call { return limit } else { return -1 }
      } == [50, 50, 50])
  }

  @Test("the exhaustive member walk is capped at six pages")
  func allMembersPageCap() async throws {
    let xrpc = FakeStarterPackXrpc()
    // Every page reports a cursor, so only the cap stops the walk.
    xrpc.setListPages(
      (0..<20).map { index in
        StarterPackListMembersPage(
          cursor: "c\(index)", items: [Fixtures.listItem("did:plc:m\(index)", rkey: "r\(index)")])
      })
    let items = try await StarterPackMembersQuery.allMembers(
      xrpc: xrpc, listURI: Fixtures.listURI())
    #expect(items.count == 6)
    #expect(xrpc.calls.count == 6)
  }

  // MARK: - Actor packs

  @Test("the actor pack read asks at the RN page size")
  func actorPacksFirstPage() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setActorPages([
      StarterPackBasicPage(cursor: "c1", starterPacks: [Fixtures.packViewBasic()])
    ])
    let query = ActorStarterPacksQuery(
      store: store(), xrpc: xrpc, actor: Fixtures.authorDID)
    let packs = try await query.loadFirstPage()

    #expect(packs.count == 1)
    #expect(
      xrpc.calls == [
        .getActorStarterPacks(actor: Fixtures.authorDID, cursor: nil, limit: 10)
      ])
  }

  @Test("the actor pack walk follows the cursor and accumulates")
  func actorPacksPagination() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setActorPages([
      StarterPackBasicPage(
        cursor: "c1", starterPacks: [Fixtures.packViewBasic(rkey: "a")]),
      StarterPackBasicPage(starterPacks: [Fixtures.packViewBasic(rkey: "b")]),
    ])
    let query = ActorStarterPacksQuery(store: store(), xrpc: xrpc, actor: Fixtures.authorDID)
    _ = try await query.loadFirstPage()
    let packs = try await query.loadMore()
    #expect(packs.map { StarterPackURI.parse($0.uri.rawValue)?.rkey } == ["a", "b"])
  }

  @Test("the membership read shares the actor page size and keeps list items")
  func membershipPagination() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setMembershipPages([
      StarterPackWithMembershipPage(
        cursor: "c1",
        packs: [
          Fixtures.membershipRow(packURI: Fixtures.packURI(), member: true),
          Fixtures.membershipRow(
            packURI: Fixtures.packURI(did: Fixtures.otherDID, rkey: "other"), member: false),
        ])
    ])
    let query = ActorStarterPacksWithMembershipQuery(
      store: store(), xrpc: xrpc, actor: Fixtures.authorDID)
    let rows = try await query.loadFirstPage()

    #expect(rows.count == 2)
    #expect(
      ActorStarterPacksWithMembershipQuery.membershipPacks(rows) == [Fixtures.packURI()])
    #expect(
      ActorStarterPacksWithMembershipQuery.isMember(rows, packURI: Fixtures.packURI()))
    #expect(
      ActorStarterPacksWithMembershipQuery.isMember(
        rows, packURI: Fixtures.packURI(did: Fixtures.otherDID, rkey: "other")) == false)
    #expect(
      xrpc.calls == [
        .getStarterPacksWithMembership(actor: Fixtures.authorDID, cursor: nil, limit: 10)
      ])
  }

  // MARK: - Search

  @Test("search asks with RN's default limit and no cursor first")
  func searchFirstPage() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setSearchPages([StarterPackViewPage(starterPacks: [Fixtures.packView()])])
    let query = StarterPackSearchQuery(store: store(), xrpc: xrpc, query: "art")
    let results = try await query.loadFirstPage()

    #expect(results.count == 1)
    #expect(xrpc.calls == [.searchStarterPacks(query: "art", cursor: nil, limit: 25)])
  }

  @Test("search de-duplicates results that repeat across pages")
  func searchDeduplication() async throws {
    let repeated = Fixtures.packView()
    let second = Fixtures.packView(rkey: "second")
    let xrpc = FakeStarterPackXrpc()
    xrpc.setSearchPages([
      StarterPackViewPage(cursor: "c1", starterPacks: [repeated, second]),
      // The same pack appears again on page two, plus a new one.
      StarterPackViewPage(starterPacks: [repeated, Fixtures.packView(rkey: "third")]),
    ])
    let query = StarterPackSearchQuery(store: store(), xrpc: xrpc, query: "art")

    _ = try await query.loadFirstPage()
    let items = try await query.loadMore()
    #expect(
      items.map { StarterPackURI.parse($0.uri.rawValue)?.rkey }
        == [Fixtures.packRkey, "second", "third"])
  }

  @Test("a fresh search resets the de-duplication set")
  func searchResetOnRefresh() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setSearchPages([
      StarterPackViewPage(starterPacks: [Fixtures.packView()]),
      StarterPackViewPage(starterPacks: [Fixtures.packView()]),
    ])
    let query = StarterPackSearchQuery(store: store(), xrpc: xrpc, query: "art")

    let first = try await query.loadFirstPage()
    #expect(first.count == 1)
    // A refresh must not treat the result as already seen.
    let second = try await query.loadFirstPage(force: true)
    #expect(second.count == 1)
  }

  @Test("search follows the cursor across pages")
  func searchCursorWalk() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setSearchPages([
      StarterPackViewPage(cursor: "c1", starterPacks: [Fixtures.packView(rkey: "a")]),
      StarterPackViewPage(starterPacks: [Fixtures.packView(rkey: "b")]),
    ])
    let query = StarterPackSearchQuery(store: store(), xrpc: xrpc, query: "art")
    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    let cursors = xrpc.calls.map { call -> String? in
      if case .searchStarterPacks(_, let cursor, _) = call { return cursor } else { return nil }
    }
    #expect(cursors == [nil, "c1"])
  }

  // MARK: - Errors

  @Test("a failing member read surfaces the error")
  func membersFailure() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.fail("getList")
    let query = StarterPackMembersQuery(store: store(), xrpc: xrpc, listURI: Fixtures.listURI())
    await #expect(throws: (any Error).self) {
      try await query.loadFirstPage()
    }
  }

  @Test("a failing search surfaces the error and leaves the set unpoisoned")
  func searchFailure() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.fail("search")
    let query = StarterPackSearchQuery(store: store(), xrpc: xrpc, query: "art")
    await #expect(throws: (any Error).self) {
      try await query.loadFirstPage()
    }
  }

  // MARK: - Pack view query

  @Test("the pack view query resolves an at:// target and caches the result")
  func packQueryLoad() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setPackView(Fixtures.packView(), for: Fixtures.packURI())
    let store = store()
    let query = StarterPackQuery(
      store: store, xrpc: xrpc, target: .didAndRkey(did: Fixtures.authorDID, rkey: Fixtures.packRkey))

    let view = try await query.load()
    #expect(view?.uri.rawValue == Fixtures.packURI())
    #expect(xrpc.calls == [.getStarterPack(uri: Fixtures.packURI())])

    // The second read is served from the cache.
    let cached = try await query.load()
    #expect(cached?.uri.rawValue == Fixtures.packURI())
    #expect(xrpc.calls.count == 1)
  }

  @Test("the pack view query converts an http target to at://")
  func packQueryHTTP() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setPackView(
      Fixtures.packView(), for: "at://joshuajfriedman.com/app.bsky.graph.starterpack/3abc")
    let query = StarterPackQuery(
      store: store(), xrpc: xrpc, target: .uri("https://bsky.app/starter-pack/joshuajfriedman.com/3abc"))

    _ = try await query.load()
    #expect(
      xrpc.calls == [
        .getStarterPack(uri: "at://joshuajfriedman.com/app.bsky.graph.starterpack/3abc")
      ])
  }

  @Test("an unparseable target makes no request")
  func packQueryDisabled() async throws {
    let xrpc = FakeStarterPackXrpc()
    let query = StarterPackQuery(store: store(), xrpc: xrpc, target: .uri("garbage"))
    let view = try await query.load()
    #expect(view == nil)
    #expect(xrpc.calls.isEmpty)
  }

  @Test("the pack view query exposes a detail for the held view")
  func packQueryDetail() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setPackView(Fixtures.packView(name: "Pack"), for: Fixtures.packURI())
    let query = StarterPackQuery(
      store: store(), xrpc: xrpc, target: .uri(Fixtures.packURI()))
    _ = try await query.load()

    let detail = await query.detail(viewerDID: Fixtures.authorDID)
    #expect(detail?.name == "Pack")
    #expect(detail?.isOwn == true)
  }

  @Test("precaching writes a view without a request")
  func precache() async throws {
    let xrpc = FakeStarterPackXrpc()
    let query = StarterPackQuery(
      store: store(), xrpc: xrpc, target: .uri(Fixtures.packURI()))
    await query.precache(Fixtures.packView(name: "Cached"))

    let cached = try await query.load()
    #expect(cached?.record.starterPackRecord?.name == "Cached")
    #expect(xrpc.calls.isEmpty)
  }

  @Test("a failing pack read surfaces the error")
  func packQueryFailure() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.fail("getStarterPack")
    let query = StarterPackQuery(
      store: store(), xrpc: xrpc, target: .didAndRkey(did: Fixtures.authorDID, rkey: Fixtures.packRkey))
    await #expect(throws: (any Error).self) {
      try await query.load()
    }
  }
}
