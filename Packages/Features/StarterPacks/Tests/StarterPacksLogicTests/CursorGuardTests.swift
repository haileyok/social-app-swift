import Foundation
import Lexicons
import QueryStore
import Testing

@testable import StarterPacksLogic

/// Asserts the cursor-walk guard that works around `QueryStore.loadMore()`.
///
/// `InfiniteQuery.loadMore()` refuses whenever `nextCursor == nextCursor`, which
/// is every call from page two on, so the paged starter-pack walks request pages
/// through `fetchPage(at:)` behind this guard instead. These tests pin both the
/// guard's own behavior and the end-to-end multi-page walk it enables.
@Suite("CursorWalkGuard")
struct CursorWalkGuardTests {
  @Test("the first page is always admitted")
  func admitsNil() {
    let guardrail = CursorWalkGuard()
    #expect(guardrail.admit(nil))
    #expect(guardrail.admit(nil))
  }

  @Test("a cursor is admitted once and refused thereafter")
  func admitsCursorOnce() {
    let guardrail = CursorWalkGuard()
    #expect(guardrail.admit("c1"))
    #expect(guardrail.admit("c1") == false)
    #expect(guardrail.admit("c2"))
  }

  @Test("resetting clears the walk")
  func reset() {
    let guardrail = CursorWalkGuard()
    #expect(guardrail.admit("c1"))
    guardrail.reset()
    #expect(guardrail.admit("c1"))
  }

  @Test("a three-page member walk reaches the terminal page")
  func memberWalkThreePages() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setListPages([
      StarterPackListMembersPage(cursor: "c1", items: [Fixtures.listItem("did:plc:a", rkey: "a")]),
      StarterPackListMembersPage(cursor: "c2", items: [Fixtures.listItem("did:plc:b", rkey: "b")]),
      StarterPackListMembersPage(cursor: "c3", items: [Fixtures.listItem("did:plc:c", rkey: "c")]),
      StarterPackListMembersPage(items: [Fixtures.listItem("did:plc:d", rkey: "d")]),
    ])
    let query = StarterPackMembersQuery(
      store: QueryStore(), xrpc: xrpc, listURI: Fixtures.listURI())

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    _ = try await query.loadMore()
    let items = try await query.loadMore()

    #expect(items.count == 4)
    let cursors = xrpc.calls.map { call -> String? in
      if case .getList(_, let cursor, _) = call { return cursor } else { return nil }
    }
    #expect(cursors == [nil, "c1", "c2", "c3"])
  }

  @Test("a server echoing its own cursor is refused rather than looped")
  func repeatedCursorRefused() async throws {
    let xrpc = FakeStarterPackXrpc()
    // Every page reports the same cursor, which is exactly the loop the guard
    // exists to stop.
    xrpc.setListPages([
      StarterPackListMembersPage(cursor: "same", items: [Fixtures.listItem("did:plc:a", rkey: "a")]),
      StarterPackListMembersPage(cursor: "same", items: [Fixtures.listItem("did:plc:b", rkey: "b")]),
    ])
    let query = StarterPackMembersQuery(
      store: QueryStore(), xrpc: xrpc, listURI: Fixtures.listURI())

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    _ = try await query.loadMore()
    #expect(xrpc.calls.count == 2, "the echoed cursor must not be requested twice")
  }

  @Test("refreshing resets the walk so the chain can be re-read")
  func refreshResetsWalk() async throws {
    let xrpc = FakeStarterPackXrpc()
    // Two full walks' worth of pages, because a refresh re-reads page one.
    xrpc.setListPages([
      StarterPackListMembersPage(cursor: "c1", items: [Fixtures.listItem("did:plc:a", rkey: "a")]),
      StarterPackListMembersPage(items: [Fixtures.listItem("did:plc:b", rkey: "b")]),
      StarterPackListMembersPage(cursor: "c1", items: [Fixtures.listItem("did:plc:a", rkey: "a")]),
      StarterPackListMembersPage(items: [Fixtures.listItem("did:plc:b", rkey: "b")]),
    ])
    let query = StarterPackMembersQuery(
      store: QueryStore(), xrpc: xrpc, listURI: Fixtures.listURI())

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    // A refresh starts the chain over; the same cursor is admitted again.
    _ = try await query.loadFirstPage(force: true)
    _ = try await query.loadMore()

    let cursors = xrpc.calls.map { call -> String? in
      if case .getList(_, let cursor, _) = call { return cursor } else { return nil }
    }
    #expect(cursors == [nil, "c1", nil, "c1"])
  }

  @Test("a four-page search walk keeps de-duplicating across all of them")
  func searchWalkFourPages() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setSearchPages([
      StarterPackViewPage(cursor: "c1", starterPacks: [Fixtures.packView(rkey: "a")]),
      StarterPackViewPage(
        cursor: "c2", starterPacks: [Fixtures.packView(rkey: "a"), Fixtures.packView(rkey: "b")]),
      StarterPackViewPage(cursor: "c3", starterPacks: [Fixtures.packView(rkey: "c")]),
      StarterPackViewPage(starterPacks: [Fixtures.packView(rkey: "d")]),
    ])
    let query = StarterPackSearchQuery(store: QueryStore(), xrpc: xrpc, query: "art")

    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    _ = try await query.loadMore()
    let items = try await query.loadMore()
    #expect(items.map { StarterPackURI.parse($0.uri.rawValue)?.rkey } == ["a", "b", "c", "d"])
  }

  @Test("a three-page actor walk reaches the terminal page")
  func actorWalkThreePages() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setActorPages([
      StarterPackBasicPage(cursor: "c1", starterPacks: [Fixtures.packViewBasic(rkey: "a")]),
      StarterPackBasicPage(cursor: "c2", starterPacks: [Fixtures.packViewBasic(rkey: "b")]),
      StarterPackBasicPage(starterPacks: [Fixtures.packViewBasic(rkey: "c")]),
    ])
    let query = ActorStarterPacksQuery(
      store: QueryStore(), xrpc: xrpc, actor: Fixtures.authorDID)
    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    let packs = try await query.loadMore()
    #expect(packs.map { StarterPackURI.parse($0.uri.rawValue)?.rkey } == ["a", "b", "c"])
  }

  @Test("a three-page membership walk reaches the terminal page")
  func membershipWalkThreePages() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setMembershipPages([
      StarterPackWithMembershipPage(
        cursor: "c1", packs: [Fixtures.membershipRow(packURI: Fixtures.packURI(rkey: "a"), member: true)]),
      StarterPackWithMembershipPage(
        cursor: "c2", packs: [Fixtures.membershipRow(packURI: Fixtures.packURI(rkey: "b"), member: false)]),
      StarterPackWithMembershipPage(
        packs: [Fixtures.membershipRow(packURI: Fixtures.packURI(rkey: "c"), member: true)]),
    ])
    let query = ActorStarterPacksWithMembershipQuery(
      store: QueryStore(), xrpc: xrpc, actor: Fixtures.authorDID)
    _ = try await query.loadFirstPage()
    _ = try await query.loadMore()
    let rows = try await query.loadMore()
    #expect(rows.count == 3)
    #expect(
      ActorStarterPacksWithMembershipQuery.membershipPacks(rows).count == 2)
  }
}
