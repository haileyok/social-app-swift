import ATProtoClient
import Foundation
import Lexicons
import QueryStore
import Testing

@testable import MessagesLogic

/// The inbox, unread counts and the convo-list key shape.
@Suite("Inbox")
struct InboxTests {
  /// A live chat client over `server`.
  private func chat(_ server: FakeChatServer) -> LiveChatXrpc {
    LiveChatXrpc(
      client: XrpcClient(
        baseURL: "https://pds.example", proxyService: BlueskyAPI.chatService,
        transport: server),
      authorization: "tok")
  }

  @Test func keyRootsMatchRN() {
    #expect(MessagesKeys.convoListRoot == "convo-list")
    #expect(MessagesKeys.convoRoot == "convo")
    #expect(MessagesKeys.unreadCountsRoot == "convo-unread-counts")
  }

  @Test func keyDistinguishesFilters() {
    let accepted = MessagesKeys.convoList(status: .accepted, limit: 10)
    let request = MessagesKeys.convoList(status: .request, limit: 10)
    let unread = MessagesKeys.convoList(status: .accepted, readState: .unread, limit: 10)
    let bigger = MessagesKeys.convoList(status: .accepted, limit: 20)

    #expect(accepted != request)
    #expect(accepted != unread)
    #expect(accepted != bigger)
    #expect(accepted.root == "convo-list")
  }

  @Test func keyCarriesScope() {
    let scoped = MessagesKeys.convoList(status: .accepted, scope: "did:plc:me")
    let bare = MessagesKeys.convoList(status: .accepted)
    #expect(scoped != bare)
    #expect(scoped.scope == "did:plc:me")
  }

  @Test func loadsFirstPageInRevOrder() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-a", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addConvo(id: "convo-b", members: [Fixtures.selfDid, Fixtures.otherDid])
    let store = QueryStore()
    let inbox = InboxQuery(store: store, client: chat(server), status: .accepted)

    let convos = try await inbox.loadFirstPage()
    #expect(convos.map(\.id) == ["convo-a", "convo-b"])

    let request = try #require(
      server.requests(for: Chat.Bsky.ConvoListConvos.id).first)
    #expect(request.param("status") == "accepted")
    #expect(request.param("limit") == "10")
  }

  @Test func pagesThroughCursors() async throws {
    let server = FakeChatServer()
    for index in 0..<3 {
      server.addConvo(id: "convo-\(index)", members: [Fixtures.selfDid, Fixtures.otherDid])
    }
    let store = QueryStore()
    let inbox = InboxQuery(store: store, client: chat(server), status: .accepted, limit: 2)

    #expect(try await inbox.loadFirstPage().count == 2)
    let all = try await inbox.loadMore()
    #expect(all.count == 3)
    #expect(await store.paginationState(for: inbox.key).pageCount == 2)

    // The second request carried the cursor the first page returned.
    let requests = server.requests(for: Chat.Bsky.ConvoListConvos.id)
    #expect(requests.count == 2)
    #expect(requests[0].param("cursor") == nil)
    #expect(requests[1].param("cursor") == "2")
  }

  @Test func unreadCountSumsAcrossPages() async throws {
    let server = FakeChatServer()
    server.addConvo(
      id: "convo-a", members: [Fixtures.selfDid, Fixtures.otherDid], unreadCount: 2)
    server.addConvo(
      id: "convo-b", members: [Fixtures.selfDid, Fixtures.otherDid], unreadCount: 3)
    let store = QueryStore()
    let inbox = InboxQuery(store: store, client: chat(server), status: .accepted)

    _ = try await inbox.loadFirstPage()
    #expect(await inbox.unreadCount() == 5)
  }

  @Test func groupConvosAreSkippedAtTheDataLayer() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "direct-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addConvo(
      id: "group-1", members: [Fixtures.selfDid, Fixtures.otherDid], group: true)
    let store = QueryStore()
    let inbox = InboxQuery(store: store, client: chat(server), status: .accepted)

    let convos = try await inbox.loadFirstPage()
    #expect(convos.map(\.id) == ["direct-1"])
  }

  @Test func unreadOnlyFilterIsSent() async throws {
    let server = FakeChatServer()
    let store = QueryStore()
    let inbox = InboxQuery(
      store: store, client: chat(server), status: .accepted, readState: .unread)
    _ = try await inbox.loadFirstPage()
    let request = try #require(server.requests(for: Chat.Bsky.ConvoListConvos.id).first)
    #expect(request.param("readState") == "unread")
  }

  @Test func refreshTruncatesToFirstPage() async throws {
    let server = FakeChatServer()
    for index in 0..<3 {
      server.addConvo(id: "convo-\(index)", members: [Fixtures.selfDid, Fixtures.otherDid])
    }
    let store = QueryStore()
    let inbox = InboxQuery(store: store, client: chat(server), status: .accepted, limit: 2)
    _ = try await inbox.loadFirstPage()
    _ = try await inbox.loadMore()
    #expect(await store.paginationState(for: inbox.key).pageCount == 2)

    _ = try await inbox.refresh()
    #expect(await store.paginationState(for: inbox.key).pageCount == 1)
  }

  @Test func subscribesToConvoChanges() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-a", members: [Fixtures.selfDid, Fixtures.otherDid])
    let store = QueryStore()
    let inbox = InboxQuery(store: store, client: chat(server), status: .accepted)

    let seen = Locked<[[String]]>([])
    let subscription = await inbox.subscribe { convos in
      seen.withLock { $0.append(convos.map(\.id)) }
    }
    _ = try await inbox.loadFirstPage()
    #expect(seen.value.last == ["convo-a"])

    await subscription.cancel()
  }

  @Test func unreadCountsQueryHas15sStaleTime() async throws {
    let server = FakeChatServer()
    server.setUnreadCounts(accepted: 7, request: 2)
    let store = QueryStore()
    let query = UnreadCountsQuery(store: store, client: chat(server))

    let counts = try await query.load()
    #expect(counts.unreadAcceptedConvos == 7)
    #expect(counts.unreadRequestConvos == 2)
    #expect(await store.staleTime(for: query.key) == 15)

    let request = try #require(
      server.requests(for: Chat.Bsky.ConvoGetUnreadCounts.id).first)
    #expect(request.param("includeGroupChats") == "true")
  }

  @Test func unreadCountsInvalidateRefetches() async throws {
    let server = FakeChatServer()
    server.setUnreadCounts(accepted: 1, request: 0)
    let store = QueryStore()
    let query = UnreadCountsQuery(store: store, client: chat(server))
    _ = try await query.load()

    server.setUnreadCounts(accepted: 5, request: 0)
    let refreshed = await query.invalidate()
    #expect(refreshed.unreadAcceptedConvos == 5)
    #expect(server.requests(for: Chat.Bsky.ConvoGetUnreadCounts.id).count == 2)
  }

  @Test func convoQueryPrecachesWithoutARequest() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-a", members: [Fixtures.selfDid, Fixtures.otherDid])
    let store = QueryStore()
    let query = ConvoQuery(store: store, client: chat(server), convoId: "convo-a")

    await query.precache(Fixtures.convo(id: "convo-a"))
    #expect(await query.data()?.id == "convo-a")
    #expect(server.requests.isEmpty)

    // A precached convo is fresh, so the follow-up load is served from cache -
    // the point of precaching (RN's `precacheConvoQuery` + `STALE.INFINITY`).
    #expect(try await query.load().id == "convo-a")
    #expect(server.requests(for: Chat.Bsky.ConvoGetConvo.id).isEmpty)

    _ = try await query.load(force: true)
    #expect(server.requests(for: Chat.Bsky.ConvoGetConvo.id).count == 1)
  }

  @Test func convoQueryIsNeverTimeStale() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-a", members: [Fixtures.selfDid, Fixtures.otherDid])
    let store = QueryStore()
    let query = ConvoQuery(store: store, client: chat(server), convoId: "convo-a")
    _ = try await query.load()
    #expect(await store.staleTime(for: query.key) == STALE.INFINITY)
    // A second load does not refetch, because the entry is not stale.
    _ = try await query.load()
    #expect(server.requests(for: Chat.Bsky.ConvoGetConvo.id).count == 1)
  }
}

/// A tiny lock-guarded box for capturing subscriber output.
final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Value

  init(_ value: Value) { self.storage = value }

  var value: Value {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func withLock(_ body: (inout Value) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    body(&storage)
  }
}
