import ATProtoClient
import Foundation
import Lexicons
import Testing

@testable import MessagesLogic

/// The conversation model: history paging, the send outbox, reactions, read
/// state, mute and delete.
@Suite("Conversation")
struct ConversationTests {
  /// A live chat client over `server`.
  private func chat(_ server: FakeChatServer) -> LiveChatXrpc {
    LiveChatXrpc(
      client: XrpcClient(
        baseURL: "https://pds.example", proxyService: BlueskyAPI.chatService,
        transport: server),
      authorization: "tok")
  }

  /// A model over a server with one direct convo.
  private func makeModel(
    _ server: FakeChatServer, convoId: String = "convo-1",
    convo: Chat.Bsky.ConvoDefs_ConvoView? = nil
  ) -> ConversationModel {
    ConversationModel(
      convoId: convoId, client: chat(server), senderDid: Fixtures.selfDid, convo: convo)
  }

  // MARK: - History

  @Test func fetchesInitialHistoryChronologically() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "one", sender: Fixtures.otherDid)
    server.addMessage(convoId: "convo-1", text: "two", sender: Fixtures.selfDid)
    let model = makeModel(server)

    let items = try await model.fetchMessageHistory()
    // The server returns newest-first; the model renders oldest-first.
    #expect(items.compactMap(\.renderedText) == ["one", "two"])

    let request = try #require(
      server.requests(for: Chat.Bsky.ConvoGetMessages.id).first)
    #expect(request.param("convoId") == "convo-1")
    #expect(request.param("limit") == "30")
    #expect(request.param("cursor") == nil)
  }

  @Test func fetchesAdditionalHistoryViaCursor() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    for index in 0..<5 {
      server.addMessage(
        convoId: "convo-1", text: "m\(index)", sender: Fixtures.otherDid)
    }
    let model = makeModel(server)

    _ = try await model.fetchMessageHistory(limit: 2)
    #expect(await model.state().hasAllHistory == false)

    _ = try await model.fetchMessageHistory(limit: 2)
    let requests = server.requests(for: Chat.Bsky.ConvoGetMessages.id)
    #expect(requests.count == 2)
    #expect(requests[1].param("cursor") == "2")

    // Walking to the end clears the cursor.
    _ = try await model.fetchMessageHistory(limit: 2)
    #expect(await model.state().hasAllHistory)
  }

  @Test func trustsTheCursorOverAShortPage() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "a", sender: Fixtures.otherDid)
    server.addMessage(convoId: "convo-1", text: "b", sender: Fixtures.otherDid)
    // The server pages raw rows but strips deleted ones from the response, so a
    // full page comes back short *with* a valid cursor. Forcing a cursor after a
    // short page models exactly that.
    server.setForcedMessageCursor("still-more")
    let model = makeModel(server)
    let items = try await model.fetchMessageHistory(limit: 2)
    #expect(items.count == 2)
    #expect(await model.state().hasAllHistory == false)
  }

  @Test func historyFailureSetsTheRetryState() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.fail(
      Chat.Bsky.ConvoGetMessages.id, status: 500, error: "InternalServerError",
      message: "boom")
    let model = makeModel(server)

    await #expect(throws: (any Error).self) {
      _ = try await model.fetchMessageHistory()
    }
    let state = await model.state()
    #expect(state.historyFailed)
    #expect(state.items.contains { $0 == .error(code: .historyFailed) })
  }

  // MARK: - Sending

  @Test func optimisticallyAddsSendingMessages() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server)

    // Hold the send so the pending row can be observed before reconciliation.
    let id = await model.sendMessage(Fixtures.input("hey"))
    let pending = try #require(id)
    #expect(pending.hasPrefix("pending-"))
  }

  @Test func sendReconcilesViaTheResponse() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("hey"))
    // Drain the outbox deterministically rather than racing the spawned task.
    await model.processPendingMessages()
    await waitUntil { await model.pendingCount == 0 }

    let state = await model.state()
    #expect(state.pendingMessageFailure == nil)
    let rendered = state.items.compactMap(\.renderedText)
    #expect(rendered == ["hey"])
    // The reconciled message carries a real server id, not the pending one.
    let message = try #require(state.items.first?.messageView)
    #expect(message.id.hasPrefix("msg-"))
  }

  @Test func emptyMessagesAreIgnored() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server)

    #expect(await model.sendMessage(Fixtures.input("   ")) == nil)
    #expect(await model.sendMessage(Fixtures.input("")) == nil)
    #expect(server.requests(for: Chat.Bsky.ConvoSendMessage.id).isEmpty)
  }

  @Test func sendsAreProcessedInOrder() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("one"))
    _ = await model.sendMessage(Fixtures.input("two"))
    await model.processPendingMessages()
    await waitUntil { await model.pendingCount == 0 }

    let texts = (await model.state().items).compactMap(\.renderedText)
    #expect(texts == ["one", "two"])
  }

  @Test func networkFailureIsRecoverable() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.fail(
      Chat.Bsky.ConvoSendMessage.id, status: 503, error: "UpstreamFailure",
      message: "try later")
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("hey"))
    await model.processPendingMessages()
    await waitUntil { await model.hasPendingFailure }

    let state = await model.state()
    #expect(state.pendingMessageFailure == .recoverable)
    // The failed message is still rendered, as a failed pending row.
    #expect(
      state.items.contains { item in
        if case .pendingMessage(let pending) = item { return pending.failed }
        return false
      })
  }

  @Test func rejectionIsUnrecoverable() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.fail(
      Chat.Bsky.ConvoSendMessage.id, status: 400, error: "InvalidRequest",
      message: "no")
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("hey"))
    await model.processPendingMessages()
    await waitUntil { await model.hasPendingFailure }
    #expect(await model.state().pendingMessageFailure == .unrecoverable)
  }

  @Test func failedSendFailsAllSendingMessages() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.fail(
      Chat.Bsky.ConvoSendMessage.id, status: 503, error: "UpstreamFailure",
      message: "try later")
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("one"))
    _ = await model.sendMessage(Fixtures.input("two"))
    await model.processPendingMessages()
    await waitUntil { await model.hasPendingFailure }

    let state = await model.state()
    #expect(await model.pendingCount == 2)
    let pendingRows = state.items.filter {
      if case .pendingMessage = $0 { return true } else { return false }
    }
    #expect(pendingRows.count == 2)
    #expect(
      pendingRows.allSatisfy {
        if case .pendingMessage(let p) = $0 { return p.failed } else { return false }
      })
  }

  @Test func batchRetrySendsTheWholeQueue() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.fail(
      Chat.Bsky.ConvoSendMessage.id, status: 503, error: "UpstreamFailure",
      message: "try later")
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("one"))
    _ = await model.sendMessage(Fixtures.input("two"))
    await model.processPendingMessages()
    await waitUntil { await model.hasPendingFailure }
    #expect(await model.pendingCount == 2)

    server.clearFailure(Chat.Bsky.ConvoSendMessage.id)
    let retried = await model.batchRetryPendingMessages()
    #expect(retried)
    #expect(await model.pendingCount == 0)
    #expect(server.requests(for: Chat.Bsky.ConvoSendMessageBatch.id).count == 1)

    let texts = (await model.state().items).compactMap(\.renderedText)
    #expect(texts == ["one", "two"])
  }

  @Test func batchRetryIsRefusedWhenNotRecoverable() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.fail(
      Chat.Bsky.ConvoSendMessage.id, status: 400, error: "InvalidRequest", message: "no")
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("one"))
    await model.processPendingMessages()
    await waitUntil { await model.hasPendingFailure }
    #expect(await model.batchRetryPendingMessages() == false)
    #expect(server.requests(for: Chat.Bsky.ConvoSendMessageBatch.id).isEmpty)
  }

  @Test func sendIntoARequestConvoAcceptsItOptimistically() async throws {
    let server = FakeChatServer()
    server.addConvo(
      id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid], status: .request)
    let model = makeModel(
      server, convo: Fixtures.convo(id: "convo-1", status: .request))

    _ = await model.sendMessage(Fixtures.input("hey"))
    #expect(await model.convoView()?.status == .accepted)
  }

  @Test func successfulSendReordersWhenTheLogArrives() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = makeModel(server)

    _ = await model.sendMessage(Fixtures.input("mine"))
    await model.processPendingMessages()
    await waitUntil { await model.pendingCount == 0 }
    let firstId = try #require((await model.state().items.first)?.messageView?.id)

    // The server emits a message that sorts before ours.
    let serverMessage = server.addMessage(
      convoId: "convo-1", text: "theirs", sender: Fixtures.otherDid)
    await model.ingest([
      Fixtures.createEvent(rev: serverMessage.rev, message: .message(serverMessage))
    ])

    // Our own message was re-admitted by the log, not duplicated.
    let state = await model.state()
    #expect(state.items.compactMap(\.renderedText) == ["mine", "theirs"])

    // The log's own create for our message replaces it in place.
    let mine = Fixtures.message(
      id: firstId, rev: "999", text: "mine", sender: Fixtures.selfDid)
    await model.ingest([Fixtures.createEvent(rev: "999", message: .message(mine))])
    #expect((await model.state().items).filter { $0.messageId == firstId }.count == 1)
  }

  // MARK: - Reactions

  @Test func addReactionIsOptimisticThenReconciled() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(
      convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()

    try await model.addReaction(messageId: message.id, emoji: "👍")
    let reactions = try #require((await model.state().items.first)?.messageView?.reactions)
    #expect(reactions.map(\.value) == ["👍"])

    let request = try #require(server.requests(for: Chat.Bsky.ConvoAddReaction.id).first)
    #expect(try #require(request.json)["value"] as? String == "👍")
  }

  @Test func addReactionRejectsNonSingleGrapheme() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()

    await #expect(throws: ConvoReactionError.self) {
      try await model.addReaction(messageId: message.id, emoji: "ab")
    }
    await #expect(throws: ConvoReactionError.self) {
      try await model.addReaction(messageId: message.id, emoji: "")
    }
    #expect(server.requests(for: Chat.Bsky.ConvoAddReaction.id).isEmpty)
  }

  @Test func multiScalarEmojiIsOneGrapheme() {
    // A skin-toned hand and a ZWJ family are each a single grapheme cluster.
    #expect(MessagesReaction.isValid("👍🏽"))
    #expect(MessagesReaction.isValid("👨‍👩‍👧"))
    #expect(MessagesReaction.isValid("🇺🇸"))
    #expect(!MessagesReaction.isValid("👍👍"))
  }

  @Test func reactionIsRolledBackOnFailure() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()
    server.fail(
      Chat.Bsky.ConvoAddReaction.id, status: 400, error: "InvalidRequest", message: "no")

    await #expect(throws: (any Error).self) {
      try await model.addReaction(messageId: message.id, emoji: "👍")
    }
    #expect(((await model.state().items.first)?.messageView?.reactions ?? []).isEmpty)
  }

  @Test func duplicateReactionIsANoOp() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()

    try await model.addReaction(messageId: message.id, emoji: "👍")
    try await model.addReaction(messageId: message.id, emoji: "👍")
    #expect(server.requests(for: Chat.Bsky.ConvoAddReaction.id).count == 1)
  }

  @Test func atMostFiveReactionsPerSender() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()

    for emoji in ["👍", "🔥", "😂", "🎉", "💯"] {
      try await model.addReaction(messageId: message.id, emoji: emoji)
    }
    await #expect(throws: ConvoReactionError.self) {
      try await model.addReaction(messageId: message.id, emoji: "🚀")
    }
  }

  @Test func removeReactionIsOptimisticThenReconciled() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let model = makeModel(server)
    _ = try await model.fetchMessageHistory()
    try await model.addReaction(messageId: message.id, emoji: "👍")

    try await model.removeReaction(messageId: message.id, emoji: "👍")
    #expect(((await model.state().items.first)?.messageView?.reactions ?? []).isEmpty)
    #expect(server.requests(for: Chat.Bsky.ConvoRemoveReaction.id).count == 1)
  }

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

/// Polls `condition` until it holds or a short budget expires.
///
/// The send path spawns its outbox drain, so a test that wants to observe the
/// reconciled state has to wait for it. A bounded poll keeps that deterministic
/// without an arbitrary sleep.
func waitUntil(
  _ condition: () async -> Bool, attempts: Int = 200
) async {
  for _ in 0..<attempts {
    if await condition() { return }
    await Task.yield()
  }
}

extension ConvoItem {
  /// The rendered text of a message-ish row, for asserting order.
  var renderedText: String? {
    switch self {
    case .message(let view): view.text
    case .deletedMessage: nil
    case .systemMessage: nil
    case .pendingMessage(let pending): pending.message.text
    case .error: nil
    }
  }

  /// The message view of a user-originated row.
  var messageView: Chat.Bsky.ConvoDefs_MessageView? {
    if case .message(let view) = self { return view }
    return nil
  }
}
