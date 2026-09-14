import Foundation
import Lexicons
import QueryStore
import Testing

@testable import MessagesLogic

/// Applying log events to the inbox caches: the RN `messagesBus.on` handler.
@Suite("InboxReducer")
struct InboxReducerTests {
  /// A store seeded with one accepted-list cache holding `convos`.
  private func seed(
    _ convos: [Chat.Bsky.ConvoDefs_ConvoView],
    status: ConvoStatusFilter = .accepted
  ) async -> (QueryStore, QueryKey) {
    let store = QueryStore()
    let key = MessagesKeys.convoList(status: status)
    await store.setQueryData(
      InfiniteQueryData(pages: [QueryPage(items: convos, cursor: nil)]), for: key)
    return (store, key)
  }

  private func convos(
    _ store: QueryStore, _ key: QueryKey
  ) async
    -> [Chat.Bsky.ConvoDefs_ConvoView]
  {
    (try? await store.payload(key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self))?
      .items ?? []
  }

  @Test func createMessageBumpsToTopAndCountsUnread() async throws {
    let existing = Fixtures.convo(id: "convo-1", unreadCount: 0, rev: "10")
    let (store, key) = await seed([existing])
    let other = Fixtures.convo(id: "convo-2", rev: "5")
    await store.updateQueryData(
      key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self
    ) { data in
      InfiniteQueryData(pages: [QueryPage(items: data.items + [other], cursor: nil)])
    }

    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "11", text: "new", sender: Fixtures.otherDid))
    await reducer.apply([Fixtures.createEvent(rev: "11", message: message)])

    let result = await convos(store, key)
    #expect(result.first?.id == "convo-1")
    #expect(result.count == 2)
    let updated = try #require(result.first)
    #expect(updated.rev == "11")
    #expect(updated.unreadCount == 1)
    #expect(updated.lastMessage.map(InboxReducer.lastMessageId) == "m1")
  }

  @Test func createMessageForTheOpenConvoStaysRead() async throws {
    let existing = Fixtures.convo(id: "convo-1", unreadCount: 3, rev: "10")
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(
      store: store, currentAccountDid: Fixtures.selfDid, currentConvoId: "convo-1")
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "11", sender: Fixtures.otherDid))
    await reducer.apply([Fixtures.createEvent(rev: "11", message: message)])

    #expect((await convos(store, key)).first?.unreadCount == 0)
  }

  @Test func ownMessageDoesNotIncrementUnread() async throws {
    let existing = Fixtures.convo(id: "convo-1", unreadCount: 0, rev: "10")
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "11", sender: Fixtures.selfDid))
    await reducer.apply([Fixtures.createEvent(rev: "11", message: message)])

    #expect((await convos(store, key)).first?.unreadCount == 0)
  }

  @Test func createMessageMergesRelatedProfiles() async throws {
    let existing = Fixtures.convo(id: "convo-1", rev: "10")
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "11", sender: Fixtures.otherDid))
    await reducer.apply([
      .createMessage(
        rev: "11", convoId: "convo-1", message: message,
        relatedProfiles: [
          Fixtures.profile("did:plc:third"),
          Fixtures.profile(Fixtures.otherDid),  // already a member: deduped
        ])
    ])

    let members = try #require((await convos(store, key)).first?.members)
    #expect(members.count == 3)
    #expect(
      members.map { $0.did.rawValue } == [Fixtures.selfDid, Fixtures.otherDid, "did:plc:third"])
  }

  @Test func revGuardIgnoresStaleEvents() async throws {
    // Chat revs are fixed-width, lexicographically-ordered strings, and the
    // guard compares them with `>` exactly as RN does. Equal-width values make
    // that a numeric comparison; the test uses them so it reflects the wire.
    let existing = Fixtures.convo(id: "convo-1", unreadCount: 0, rev: "0000000100")
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "0000000050", sender: Fixtures.otherDid))
    await reducer.apply([Fixtures.createEvent(rev: "0000000050", message: message)])

    let result = try #require((await convos(store, key)).first)
    #expect(result.rev == "0000000100")
    #expect(result.unreadCount == 0)
    #expect(result.lastMessage == nil)
  }

  @Test func unknownConvoFlagsARefetch() async throws {
    let (store, _) = await seed([])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "5", sender: Fixtures.otherDid))

    let needsRefetch = await reducer.apply([
      Fixtures.createEvent(rev: "5", convoId: "convo-unknown", message: message)
    ])
    #expect(needsRefetch)
    #expect(await reducer.needsRefetch())

    await reducer.clearRefetch()
    #expect(await reducer.needsRefetch() == false)
  }

  @Test func deleteMessageRewritesLastMessageOnlyWhenItMatches() async throws {
    let last = Fixtures.message(id: "m1", rev: "10", text: "last", sender: Fixtures.otherDid)
    let existing = Fixtures.convo(id: "convo-1", rev: "10", lastMessage: last)
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)

    // A delete of a different message leaves the row alone.
    let other = Fixtures.message(id: "m0", rev: "9", text: "other", sender: Fixtures.otherDid)
    await reducer.apply([
      Fixtures.deleteEvent(rev: "11", message: .deleted(ConvoMessage.tombstone(other)))
    ])
    #expect((await convos(store, key)).first?.rev == "10")

    // A delete of the last message rewrites it.
    await reducer.apply([
      Fixtures.deleteEvent(rev: "12", message: .deleted(ConvoMessage.tombstone(last)))
    ])
    let updated = try #require((await convos(store, key)).first)
    #expect(updated.rev == "12")
    guard case .convoDefsDeletedMessageView(let deleted) = updated.lastMessage else {
      Issue.record("expected a deleted last message")
      return
    }
    #expect(deleted.id == "m1")
  }

  @Test func readEventsZeroUnreadWithRevGuard() async throws {
    let existing = Fixtures.convo(id: "convo-1", unreadCount: 4, rev: "10")
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "11", sender: Fixtures.otherDid))

    let readEvent: ChatLogEvent = .readConvo(rev: "11", convoId: "convo-1", message: message)
    await reducer.apply([readEvent])
    var updated = try #require((await convos(store, key)).first)
    #expect(updated.unreadCount == 0)
    #expect(updated.rev == "11")

    // The deprecated logReadMessage behaves identically.
    var withUnread = updated
    withUnread.unreadCount = 5
    let restored = withUnread
    await store.updateQueryData(
      key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self
    ) { _ in InfiniteQueryData(pages: [QueryPage(items: [restored], cursor: nil)]) }
    let readMessageEvent: ChatLogEvent = .readMessage(
      rev: "12", convoId: "convo-1", message: message)
    await reducer.apply([readMessageEvent])
    #expect((await convos(store, key)).first?.unreadCount == 0)
  }

  @Test func muteAndUnmuteFlipTheFlag() async throws {
    let existing = Fixtures.convo(id: "convo-1", rev: "10")
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)

    await reducer.apply([
      .muteConvo(ChatRevEvent(rev: "11", convoId: "convo-1"))
    ])
    #expect((await convos(store, key)).first?.muted == true)

    await reducer.apply([
      .unmuteConvo(ChatRevEvent(rev: "12", convoId: "convo-1"))
    ])
    #expect((await convos(store, key)).first?.muted == false)
  }

  @Test func leaveRemovesTheConvoFromAllLists() async throws {
    let existing = Fixtures.convo(id: "convo-1", rev: "10")
    let other = Fixtures.convo(id: "convo-2", rev: "9")
    let (store, key) = await seed([existing, other])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)

    await reducer.apply([
      .leaveConvo(ChatRevEvent(rev: "11", convoId: "convo-1"))
    ])
    #expect((await convos(store, key)).map(\.id) == ["convo-2"])
  }

  @Test func acceptConvoMovesItFromRequestToAccepted() async throws {
    let request = Fixtures.convo(id: "convo-1", status: .request, unreadCount: 2, rev: "10")
    let store = QueryStore()
    let requestKey = MessagesKeys.convoList(status: .request)
    let acceptedKey = MessagesKeys.convoList(status: .accepted)
    await store.setQueryData(
      InfiniteQueryData(pages: [QueryPage(items: [request], cursor: nil)]), for: requestKey)
    await store.setQueryData(
      InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>(
        pages: [QueryPage(items: [], cursor: nil)]), for: acceptedKey)
    await store.setQueryData(
      Fixtures.convo(id: "convo-1", status: .request), for: MessagesKeys.convo("convo-1"))

    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)
    await reducer.apply([
      .acceptConvo(ChatRevEvent(rev: "11", convoId: "convo-1"))
    ])

    #expect(await convos(store, requestKey).isEmpty)
    let accepted = await convos(store, acceptedKey)
    #expect(accepted.first?.id == "convo-1")
    #expect(accepted.first?.status == .accepted)
    #expect(accepted.first?.rev == "11")
  }

  @Test func toleratedEventsAreIgnored() async throws {
    let existing = Fixtures.convo(id: "convo-1", rev: "10")
    let (store, key) = await seed([existing])
    let reducer = InboxReducer(store: store, currentAccountDid: Fixtures.selfDid)

    await reducer.apply([
      .groupEvent(type: "chat.bsky.convo.defs#logEditGroup", rev: "99", convoId: "convo-1"),
      .other(type: nil, rev: "100", convoId: "convo-1"),
    ])
    #expect((await convos(store, key)).first?.rev == "10")
  }

  @Test func writeTouchesTheSingleConvoCache() async throws {
    let existing = Fixtures.convo(id: "convo-1", unreadCount: 2, rev: "10")
    let (store, key) = await seed([existing])
    await store.setQueryData(existing, for: MessagesKeys.convo("convo-1"))
    let reducer = InboxReducer(
      store: store, currentAccountDid: Fixtures.selfDid, currentConvoId: "convo-1")
    let message = ConvoMessage.message(
      Fixtures.message(id: "m1", rev: "11", sender: Fixtures.otherDid))
    await reducer.apply([Fixtures.createEvent(rev: "11", message: message)])

    let single = try? await store.payload(
      MessagesKeys.convo("convo-1"), as: Chat.Bsky.ConvoDefs_ConvoView.self)
    #expect(single?.rev == "11")
    #expect((await convos(store, key)).first?.rev == "11")
  }

  @Test func matchesEncodesTheListFilters() {
    let direct = Fixtures.convo(id: "convo-1", unreadCount: 1)
    let read = Fixtures.convo(id: "convo-2", unreadCount: 0)
    let request = Fixtures.convo(id: "convo-3", status: .request, unreadCount: 1)

    #expect(
      InboxReducer.matches(direct, key: MessagesKeys.convoList(status: .accepted)))
    #expect(
      !InboxReducer.matches(request, key: MessagesKeys.convoList(status: .accepted)))
    #expect(
      !InboxReducer.matches(read, key: MessagesKeys.convoList(readState: .unread)))
    #expect(
      InboxReducer.matches(direct, key: MessagesKeys.convoList(kind: .direct)))
    // The 1:1 scope never admits a group-filtered list.
    #expect(
      !InboxReducer.matches(direct, key: MessagesKeys.convoList(kind: .group)))
  }

  @Test func removingAndPrependingPreservePagination() {
    let a = Fixtures.convo(id: "a")
    let b = Fixtures.convo(id: "b")
    let c = Fixtures.convo(id: "c")
    let data = InfiniteQueryData(pages: [
      QueryPage(items: [a, b], cursor: "c1"),
      QueryPage(items: [c], cursor: nil),
    ])

    let removed = try? #require(InboxReducer.removing("c", from: data))
    #expect(removed?.items.map(\.id) == ["a", "b"])
    #expect(removed?.pages.count == 2)
    // A no-op removal returns nil, so callers can skip the write.
    #expect(InboxReducer.removing("nope", from: data) == nil)

    let prepended = InboxReducer.prepending(c, to: data)
    #expect(prepended.items.map(\.id) == ["c", "a", "b"])
    #expect(prepended.pages.count == 2)
    #expect(prepended.pages[0].cursor == "c1")
  }
}
