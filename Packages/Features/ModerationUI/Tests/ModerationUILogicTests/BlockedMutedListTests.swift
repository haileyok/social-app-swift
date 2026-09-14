import ATProtoClient
import Foundation
import Lexicons
import QueryStore
import Testing

@testable import ModerationUILogic

/// Port of the list queries in `src/state/queries/my-blocked-accounts.ts` and
/// `my-muted-accounts.ts`, plus the unblock/unmute writes behind
/// `src/view/screens/ModerationBlockedAccounts.tsx` and
/// `ModerationMutedAccounts.tsx`.
@Suite("Blocked and muted lists")
struct BlockedMutedListTests {

  /// A profile list page as the appview returns it.
  private func blocksPage(dids: [String], cursor: String?) -> String {
    let blocks = dids.map { did in
      #"{"did":"\#(did)","handle":"\#(Fixtures.handle(did))"}"#
    }.joined(separator: ",")
    let cursorMember = cursor.map { #","cursor":"\#($0)""# } ?? ""
    return #"{"blocks":[\#(blocks)]\#(cursorMember)}"#
  }

  /// A mute list page as the appview returns it.
  private func mutesPage(dids: [String], cursor: String?) -> String {
    let mutes = dids.map { did in
      #"{"did":"\#(did)","handle":"\#(Fixtures.handle(did))"}"#
    }.joined(separator: ",")
    let cursorMember = cursor.map { #","cursor":"\#($0)""# } ?? ""
    return #"{"mutes":[\#(mutes)]\#(cursorMember)}"#
  }

  // MARK: - Keys

  @Test("the blocked and muted roots match RN's RQKEY_ROOTs")
  func roots() {
    #expect(BlockedMutedList.blockedRoot == "my-blocked-accounts")
    #expect(BlockedMutedList.mutedRoot == "my-muted-accounts")
  }

  @Test("the page size matches RN's limit")
  func pageSize() {
    #expect(BlockedMutedList.pageSize == 30)
  }

  @Test("the two lists use different keys for the same account")
  func keysDiffer() {
    let args = BlockedMutedList.ListArgs(accountDid: "did:plc:me")
    #expect(BlockedMutedList.blockedKey(args) != BlockedMutedList.mutedKey(args))
  }

  @Test("the key is scoped to the account")
  func keyScopedToAccount() {
    let a = BlockedMutedList.blockedKey(.init(accountDid: "did:plc:a"))
    let b = BlockedMutedList.blockedKey(.init(accountDid: "did:plc:b"))
    #expect(a != b)
    #expect(a.scope == "did:plc:a")
  }

  // MARK: - Pagination

  @Test("the block list walks cursors and requests the RN limit")
  func blockedPagination() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.graph.getBlocks",
      json: blocksPage(dids: ["did:plc:1", "did:plc:2"], cursor: "c1"))
    server.respond(
      "app.bsky.graph.getBlocks",
      json: blocksPage(dids: ["did:plc:3"], cursor: nil))

    let store = QueryStore()
    let list = BlockedAccountsQuery(store: store, client: server.appviewClient())

    try await list.query.loadFirstPage()
    #expect(await list.query.items().map(\.did.rawValue) == ["did:plc:1", "did:plc:2"])
    #expect(await list.query.hasNextPage())

    try await list.query.loadMore()
    #expect(
      await list.query.items().map(\.did.rawValue) == ["did:plc:1", "did:plc:2", "did:plc:3"])
    #expect(!(await list.query.hasNextPage()))

    let requests = server.requests("app.bsky.graph.getBlocks")
    #expect(requests.count == 2)
    #expect(requests[0].params["limit"] == "30")
    #expect(requests[0].params["cursor"] == nil)
    #expect(requests[1].params["cursor"] == "c1")
  }

  @Test("the mute list walks cursors and requests the RN limit")
  func mutedPagination() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.graph.getMutes", json: mutesPage(dids: ["did:plc:1"], cursor: "c1"))
    server.respond("app.bsky.graph.getMutes", json: mutesPage(dids: ["did:plc:2"], cursor: nil))

    let store = QueryStore()
    let list = MutedAccountsQuery(store: store, client: server.appviewClient())

    try await list.query.loadFirstPage()
    try await list.query.loadMore()
    #expect(await list.query.items().map(\.did.rawValue) == ["did:plc:1", "did:plc:2"])

    #expect(server.requests("app.bsky.graph.getMutes")[0].params["limit"] == "30")
  }

  @Test("an empty first page leaves nothing to page")
  func emptyFirstPage() async throws {
    let server = ScriptedXRPC()
    server.respond("app.bsky.graph.getBlocks", json: blocksPage(dids: [], cursor: nil))
    let store = QueryStore()
    let list = BlockedAccountsQuery(store: store, client: server.appviewClient())

    try await list.query.loadFirstPage()
    #expect(await list.query.items().isEmpty)
    #expect(!(await list.query.hasNextPage()))
  }

  @Test("a repeated cursor stops the walk after one extra request")
  func repeatedCursor() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.graph.getBlocks", json: blocksPage(dids: ["did:plc:1"], cursor: "same"))
    server.respond(
      "app.bsky.graph.getBlocks", json: blocksPage(dids: ["did:plc:1"], cursor: "same"))
    server.respond(
      "app.bsky.graph.getBlocks", json: blocksPage(dids: ["did:plc:1"], cursor: "same"))

    let store = QueryStore()
    let list = BlockedAccountsQuery(store: store, client: server.appviewClient())
    try await list.query.loadFirstPage()
    try await list.query.loadMore()
    // The server echoed its cursor, so the store detects the repeat and refuses
    // the next request. This is the `repeatedCursor` guard's documented
    // behaviour: it catches the loop one request after it starts.
    try await list.query.loadMore()
    #expect(server.requests("app.bsky.graph.getBlocks").count == 2)
  }

  @Test("a page one failure propagates")
  func firstPageFailure() async throws {
    let server = ScriptedXRPC()
    server.fail(
      "app.bsky.graph.getBlocks", status: 502, error: "UpstreamFailure",
      message: "Upstream server responded with a 502 error")
    let store = QueryStore()
    let list = BlockedAccountsQuery(store: store, client: server.appviewClient())

    await #expect(throws: (any Error).self) {
      try await list.query.loadFirstPage()
    }
  }

  // MARK: - Optimistic removal

  @Test("removing a blocked actor ticks the row out of the store immediately")
  func optimisticBlockedRemoval() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.graph.getBlocks",
      json: blocksPage(dids: ["did:plc:1", "did:plc:2"], cursor: nil))
    let store = QueryStore()
    let list = BlockedAccountsQuery(store: store, client: server.appviewClient())
    try await list.query.loadFirstPage()

    let removed = await BlockedMutedOptimistic.removeBlocked(store, did: "did:plc:1")
    #expect(removed)
    #expect(await list.query.items().map(\.did.rawValue) == ["did:plc:2"])
  }

  @Test("removing a muted actor ticks the row out of the store immediately")
  func optimisticMutedRemoval() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.graph.getMutes", json: mutesPage(dids: ["did:plc:1", "did:plc:2"], cursor: nil))
    let store = QueryStore()
    let list = MutedAccountsQuery(store: store, client: server.appviewClient())
    try await list.query.loadFirstPage()

    let removed = await BlockedMutedOptimistic.removeMuted(store, did: "did:plc:2")
    #expect(removed)
    #expect(await list.query.items().map(\.did.rawValue) == ["did:plc:1"])
  }

  @Test("removing an absent actor reports no change")
  func optimisticRemovalAbsent() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.graph.getBlocks", json: blocksPage(dids: ["did:plc:1"], cursor: nil))
    let store = QueryStore()
    let list = BlockedAccountsQuery(store: store, client: server.appviewClient())
    try await list.query.loadFirstPage()

    #expect(!(await BlockedMutedOptimistic.removeBlocked(store, did: "did:plc:absent")))
    #expect(await list.query.items().count == 1)
  }

  @Test("removing from an unloaded list reports no change")
  func optimisticRemovalUnloaded() async {
    let store = QueryStore()
    #expect(!(await BlockedMutedOptimistic.removeBlocked(store, did: "did:plc:1")))
  }

  // MARK: - Removal wire calls

  @Test("an unblock deletes the block record by rkey")
  func unblockDeletesRecord() async throws {
    let server = ScriptedXRPC()
    server.respond("com.atproto.repo.deleteRecord", json: "{}")
    let removal = BlockedMutedRemoval(
      pds: server.pdsClient(), appview: server.appviewClient())

    try await removal.unblock(
      repoDid: "did:plc:me",
      blockUri: "at://did:plc:me/app.bsky.graph.block/3ka")

    let request = try #require(server.requests("com.atproto.repo.deleteRecord").first)
    let body = try #require(request.jsonBody)
    #expect(body["repo"]?.stringValue == "did:plc:me")
    #expect(body["collection"]?.stringValue == "app.bsky.graph.block")
    #expect(body["rkey"]?.stringValue == "3ka")
  }

  @Test("an unmute posts the actor did")
  func unmutePostsActor() async throws {
    let server = ScriptedXRPC()
    server.respond("app.bsky.graph.unmuteActor", json: "{}")
    let removal = BlockedMutedRemoval(
      pds: server.pdsClient(), appview: server.appviewClient())

    try await removal.unmute(did: "did:plc:them")

    let request = try #require(server.requests("app.bsky.graph.unmuteActor").first)
    let body = try #require(request.jsonBody)
    #expect(body["actor"]?.stringValue == "did:plc:them")
  }

  @Test("the unblock rkey extractor reads the last uri segment")
  func rkeyExtraction() {
    #expect(
      BlockedMutedRemoval.rkey(fromBlockUri: "at://did:plc:me/app.bsky.graph.block/3ka") == "3ka")
    #expect(BlockedMutedRemoval.rkey(fromBlockUri: "garbage") == "garbage")
  }
}
