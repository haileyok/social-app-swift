import ATProtoClient
import Foundation
import Lexicons
import Testing

@testable import MessagesLogic

/// Read state, mute, leave and delete for the conversation model.
///
/// Split from ``ConversationTests`` so neither file exceeds the repo's
/// type-body budget; the fixtures and the tiny chat helper are shared.
extension ConversationTests {
  // MARK: - Read state, mute, delete

  @Test func updateReadZeroesUnreadAndReturnsTheConvo() async throws {
    let server = FakeChatServer()
    server.addConvo(
      id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid], unreadCount: 4)
    let model = makeModel(server)

    let view = try await model.updateRead(messageId: "m1")
    #expect(view.unreadCount == 0)
    #expect(await model.convoView()?.unreadCount == 0)

    let request = try #require(server.requests(for: Chat.Bsky.ConvoUpdateRead.id).first)
    #expect(try #require(request.json)["messageId"] as? String == "m1")
  }

  @Test func muteIsOptimisticAndRollsBackOnFailure() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server, convo: Fixtures.convo(id: "convo-1"))
    #expect(await model.convoView()?.muted == false)

    let muted = try await model.setMuted(true)
    #expect(muted.muted)
    #expect(await model.convoView()?.muted == true)

    server.fail(
      Chat.Bsky.ConvoUnmuteConvo.id, status: 400, error: "InvalidConvo", message: "no")
    await #expect(throws: (any Error).self) {
      _ = try await model.setMuted(false)
    }
    // Rolled back to the restored (muted) view.
    #expect(await model.convoView()?.muted == true)
  }

  @Test func leaveClearsTheConvoAndRestoresOnFailure() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server, convo: Fixtures.convo(id: "convo-1"))

    server.fail(
      Chat.Bsky.ConvoLeaveConvo.id, status: 400, error: "InvalidConvo", message: "no")
    await #expect(throws: (any Error).self) {
      _ = try await model.leaveConvo()
    }
    #expect(await model.convoView() != nil)

    server.clearFailure(Chat.Bsky.ConvoLeaveConvo.id)
    let result = try await model.leaveConvo()
    #expect(result.convoId == "convo-1")
    #expect(await model.convoView() == nil)
  }

  @Test func deleteIsOptimisticAndHidesTheMessage() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(
      convoId: "convo-1", text: "bye", sender: Fixtures.selfDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()
    #expect((await model.state().items).count == 1)

    try await model.deleteMessage(message.id)
    #expect((await model.state().items).isEmpty)
    #expect(await model.isDeleted(message.id))

    // A stale view arriving afterwards does not resurrect it.
    await model.ingest([
      Fixtures.createEvent(rev: "900", message: .message(message))
    ])
    #expect((await model.state().items).isEmpty)
  }

  @Test func deleteViaLogRemovesAndTombstones() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(
      convoId: "convo-1", text: "bye", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()

    await model.ingest([
      Fixtures.deleteEvent(
        rev: "500", message: .deleted(ConvoMessage.tombstone(message)))
    ])
    #expect((await model.state().items).isEmpty)
    #expect(await model.isDeleted(message.id))
  }

  // MARK: - Item ordering

  @Test func itemsArePastThenNewThenPending() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let past = server.addMessage(convoId: "convo-1", text: "past", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()

    let fresh = Fixtures.message(id: "new-1", rev: "200", text: "new", sender: Fixtures.otherDid)
    await model.ingest([Fixtures.createEvent(rev: "200", message: .message(fresh))])

    #expect(
      (await model.state().items).compactMap(\.renderedText) == ["past", "new"])

    // Now hold a pending row by failing the send.
    server.fail(
      Chat.Bsky.ConvoSendMessage.id, status: 503, error: "UpstreamFailure", message: "later")
    _ = await model.sendMessage(Fixtures.input("pending"))
    await model.processPendingMessages()
    await waitUntil { await model.hasPendingFailure }

    let texts = (await model.state().items).compactMap(\.renderedText)
    #expect(texts == ["past", "new", "pending"])
    #expect(past.id != fresh.id)
  }

  @Test func logEventsOnlyAffectThisConvo() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()

    let other = Fixtures.message(id: "other-1", text: "other convo", sender: Fixtures.otherDid)
    await model.ingest([
      ChatLogEvent.createMessage(
        rev: "300", convoId: "convo-2", message: .message(other), relatedProfiles: [])
    ])
    // The model applies whatever it is handed; convo filtering is the caller's
    // (the sync bus subscribes per convo). Assert the model did not crash and
    // still holds its own (empty) history.
    #expect((await model.state().items).isEmpty)
  }

  @Test func revAdvancesToTheNewestEvent() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server, convo: Fixtures.convo(id: "convo-1", rev: "1"))

    let a = Fixtures.message(id: "a", rev: "5", sender: Fixtures.otherDid)
    let b = Fixtures.message(id: "b", rev: "9", sender: Fixtures.otherDid)
    await model.ingest([
      Fixtures.createEvent(rev: "5", message: .message(a)),
      Fixtures.createEvent(rev: "9", message: .message(b)),
    ])
    #expect(await model.convoView()?.rev == "9")
  }
}
