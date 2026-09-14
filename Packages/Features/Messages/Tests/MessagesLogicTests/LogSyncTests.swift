import ATProtoClient
import Foundation
import Lexicons
import Testing

@testable import MessagesLogic

/// The log-sync engine: cursor seeding, rev de-duplication, failure phases and
/// incremental application.
@Suite("LogSync")
struct LogSyncTests {
  /// A live chat client over `server`.
  private func chat(_ server: FakeChatServer) -> LiveChatXrpc {
    LiveChatXrpc(
      client: XrpcClient(
        baseURL: "https://pds.example", proxyService: BlueskyAPI.chatService,
        transport: server),
      authorization: "tok")
  }

  @Test func initializeSeedsTheCursorWithoutEvents() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "existing", sender: Fixtures.otherDid)
    let sync = LogSync(client: chat(server))

    // The seed call carries no cursor.
    let cursor = try await sync.initialize()
    let request = try #require(server.requests(for: Chat.Bsky.ConvoGetLog.id).first)
    #expect(request.param("cursor") == nil)

    // The cursor is the newest rev, and history is *not* replayed.
    #expect(cursor == server.headRev)
    #expect(await sync.cursor == server.headRev)
    #expect(await sync.isInitialized)
  }

  @Test func pollReturnsOnlyEventsPastTheCursor() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "old", sender: Fixtures.otherDid)
    let sync = LogSync(client: chat(server))
    _ = try await sync.initialize()

    let fresh = server.addMessage(
      convoId: "convo-1", text: "new", sender: Fixtures.otherDid)
    let batch = try await sync.poll()

    #expect(batch.hasNewEvents)
    #expect(batch.events.count == 1)
    #expect(batch.events.first?.rev == fresh.rev)
    #expect(batch.events.first?.convoId == "convo-1")

    // The poll carried the seeded cursor.
    let pollRequest = try #require(server.requests(for: Chat.Bsky.ConvoGetLog.id).last)
    #expect(pollRequest.param("cursor") != nil)
  }

  @Test func pollWithNoNewEventsIsEmpty() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "old", sender: Fixtures.otherDid)
    let sync = LogSync(client: chat(server))
    _ = try await sync.initialize()

    let batch = try await sync.poll()
    #expect(!batch.hasNewEvents)
    #expect(batch.events.isEmpty)
  }

  @Test func repeatedPollsDoNotRedeliver() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "one", sender: Fixtures.otherDid)
    let sync = LogSync(client: chat(server))
    _ = try await sync.initialize()

    let fresh = server.addMessage(convoId: "convo-1", text: "two", sender: Fixtures.otherDid)
    let first = try await sync.poll()
    #expect(first.events.count == 1)
    // A second poll at the advanced cursor sees nothing:
    let second = try await sync.poll()
    #expect(second.events.isEmpty)
    #expect(await sync.cursor == fresh.rev)
  }

  @Test func batchesAreOrderedOldestFirst() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let sync = LogSync(client: chat(server))
    _ = try await sync.initialize()

    server.addMessage(convoId: "convo-1", text: "one", sender: Fixtures.otherDid)
    server.addMessage(convoId: "convo-1", text: "two", sender: Fixtures.otherDid)
    let batch = try await sync.poll()
    #expect(batch.events.count == 2)
    #expect(batch.events[0].rev! < batch.events[1].rev!)
  }

  @Test func initFailureReportsInitPhaseAndLeavesCursorUnset() async throws {
    let server = FakeChatServer()
    server.fail(
      Chat.Bsky.ConvoGetLog.id, status: 500, error: "InternalServerError", message: "boom")
    let sync = LogSync(client: chat(server))

    await #expect(throws: LogSyncError.self) {
      _ = try await sync.initialize()
    }
    #expect(await sync.cursor == nil)
    #expect(await sync.isInitialized == false)
  }

  @Test func pollFailureReportsPollPhaseAndKeepsTheCursor() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "old", sender: Fixtures.otherDid)
    let sync = LogSync(client: chat(server))
    let seeded = try await sync.initialize()

    server.fail(
      Chat.Bsky.ConvoGetLog.id, status: 503, error: "UpstreamFailure", message: "later")
    do {
      _ = try await sync.poll()
      Issue.record("expected a poll failure")
    } catch let error as LogSyncError {
      #expect(error.phase == .pollFailed)
    }
    // The cursor is untouched, so a resume does not skip events.
    #expect(await sync.cursor == seeded)
  }

  @Test func recoverResumesFromTheHeldCursorWithoutSkipping() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    // A first real event, so the seed has a rev to resume from.
    server.addMessage(convoId: "convo-1", text: "seed", sender: Fixtures.otherDid)
    let sync = LogSync(client: chat(server))
    _ = try await sync.initialize()

    // An event arrives while the poll is failing.
    server.fail(
      Chat.Bsky.ConvoGetLog.id, status: 503, error: "UpstreamFailure", message: "later")
    await #expect(throws: LogSyncError.self) { _ = try await sync.poll() }

    let missed = server.addMessage(
      convoId: "convo-1", text: "offline", sender: Fixtures.otherDid)
    server.clearFailure(Chat.Bsky.ConvoGetLog.id)

    let batch = try await sync.recover()
    #expect(batch.events.contains { $0.rev == missed.rev })
  }

  @Test func recoverFromAnUnseededBusReseeds() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "old", sender: Fixtures.otherDid)
    server.fail(
      Chat.Bsky.ConvoGetLog.id, status: 500, error: "InternalServerError", message: "boom")
    let sync = LogSync(client: chat(server))
    await #expect(throws: LogSyncError.self) { _ = try await sync.initialize() }

    server.clearFailure(Chat.Bsky.ConvoGetLog.id)
    let batch = try await sync.recover()
    #expect(batch.events.isEmpty)
    #expect(await sync.isInitialized)
  }

  @Test func reinitializeNeverRewindsTheCursor() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let sync = LogSync(client: chat(server))
    _ = try await sync.initialize()
    let advanced = server.addMessage(
      convoId: "convo-1", text: "one", sender: Fixtures.otherDid)
    _ = try await sync.poll()
    #expect(await sync.cursor == advanced.rev)

    // A fresh seed takes the max of the held rev and the server's head.
    let reseeded = try await sync.initialize()
    #expect(reseeded == advanced.rev)
    #expect(await sync.cursor == advanced.rev)
  }

  @Test func eventsWithoutARevDoNotAdvanceTheCursor() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "old", sender: Fixtures.otherDid)
    let sync = LogSync(client: chat(server))
    let seeded = try await sync.initialize()

    // An unrecognized event with no rev: decoded to `.other`, dropped by poll.
    server.emitLog(["$type": "chat.bsky.convo.defs#logSomethingNew", "convoId": "convo-1"])
    let batch = try await sync.poll()
    #expect(batch.events.isEmpty)
    #expect(await sync.cursor == seeded)
  }

  @Test func drivesTheConversationModelEndToEnd() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let client = chat(server)
    let sync = LogSync(client: client)
    let model = ConversationModel(
      convoId: "convo-1", client: client, senderDid: Fixtures.selfDid)

    _ = try await sync.initialize()
    _ = try await model.fetchMessageHistory()

    let message = server.addMessage(
      convoId: "convo-1", text: "live", sender: Fixtures.otherDid)
    let batch = try await sync.poll()
    await model.ingest(batch.events)

    #expect((await model.state().items).compactMap(\.renderedText) == ["live"])
    #expect(message.id == (await model.state().items.first)?.messageId)
  }

  @Test func cursorCanBeRestored() async throws {
    let server = FakeChatServer()
    let sync = LogSync(client: chat(server))
    await sync.setCursor("already-there")
    #expect(await sync.cursor == "already-there")
    #expect(await sync.isInitialized)
  }
}

/// Unknown-event and group-event tolerance: the wire shapes must decode without
/// throwing and be skipped at the data layer.
@Suite("Tolerance")
struct ToleranceTests {
  /// A live chat client over `server`.
  private func chat(_ server: FakeChatServer) -> LiveChatXrpc {
    LiveChatXrpc(
      client: XrpcClient(
        baseURL: "https://pds.example", proxyService: BlueskyAPI.chatService,
        transport: server),
      authorization: "tok")
  }

  @Test func unknownLogTypeDecodesWithoutThrowing() async throws {
    let server = FakeChatServer()
    server.emitLog([
      "$type": "chat.bsky.convo.defs#logFutureThing",
      "rev": "1",
      "convoId": "convo-1",
      "payload": ["whatever": true],
    ])
    let page = try await chat(server).getLog(cursor: nil)
    #expect(page.logs.count == 1)
    guard case .other(let type, _, _) = page.logs[0] else {
      Issue.record("expected a tolerated other event")
      return
    }
    #expect(type == "chat.bsky.convo.defs#logFutureThing")
    #expect(page.logs[0].isTolerated)
  }

  @Test func groupEventsDecodeAsGroupEvents() async throws {
    let server = FakeChatServer()
    let groupTypes = [
      "logAddMember", "logRemoveMember", "logMemberJoin", "logMemberLeave",
      "logLockConvo", "logUnlockConvo", "logLockConvoPermanently", "logEditGroup",
      "logCreateJoinLink", "logEditJoinLink", "logEnableJoinLink", "logDisableJoinLink",
      "logIncomingJoinRequest", "logApproveJoinRequest", "logRejectJoinRequest",
      "logOutgoingJoinRequest", "logWithdrawIncomingJoinRequest",
      "logWithdrawOutgoingJoinRequest", "logReadJoinRequests",
    ]
    for (index, name) in groupTypes.enumerated() {
      // The group log shapes require `message` (a system-message view) or
      // `member`, exactly as the lexicon declares; the service always sends them.
      var event: [String: Any] = [
        "$type": "chat.bsky.convo.defs#\(name)",
        "rev": "\(index + 1)",
        "convoId": "convo-g",
      ]
      let isMemberEvent =
        name.contains("JoinRequest") || name.contains("Approve")
        || name.contains("Reject") || name.contains("Withdraw")
      if isMemberEvent {
        event["member"] = ["did": Fixtures.otherDid, "handle": "other.test"]
      } else {
        event["relatedProfiles"] = []
        event["message"] = [
          "$type": "chat.bsky.convo.defs#systemMessageView",
          "id": "sys-\(index)",
          "rev": "\(index + 1)",
          "sentAt": Fixtures.defaultDate,
          "data": [
            "$type": "chat.bsky.convo.defs#systemMessageDataEditGroup",
            "name": "g",
            "memberCount": 3,
          ],
        ]
      }
      server.emitLog(event)
    }
    let page = try await chat(server).getLog(cursor: nil)
    #expect(page.logs.count == groupTypes.count)
    #expect(page.logs.allSatisfy { $0.isTolerated })
    for (index, event) in page.logs.enumerated() {
      guard case .groupEvent(let type, _, _) = event else {
        Issue.record("\(groupTypes[index]) did not map to a group event")
        continue
      }
      #expect(type == "chat.bsky.convo.defs#\(groupTypes[index])")
    }
  }

  @Test func groupEventsAreEmittedButSkippedAtTheDataLayer() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let client = chat(server)
    let sync = LogSync(client: client)
    let model = ConversationModel(
      convoId: "convo-1", client: client, senderDid: Fixtures.selfDid)
    _ = try await sync.initialize()

    server.emitLog([
      "$type": "chat.bsky.convo.defs#logEditGroup", "rev": "9000", "convoId": "convo-1",
      "message": [
        "$type": "chat.bsky.convo.defs#systemMessageView",
        "id": "sys-9000", "rev": "9000", "sentAt": Fixtures.defaultDate,
        "data": [
          "$type": "chat.bsky.convo.defs#systemMessageDataEditGroup",
          "name": "renamed", "memberCount": 3,
        ],
      ],
    ])

    // RN's poll advances the rev for *any* rev-bearing event ("update rev
    // regardless of if it's a type we care about"), and the event reaches
    // subscribers; the subscribers are what filter by type. This port keeps
    // that, so the sync engine emits the group event and moves the cursor.
    let batch = try await sync.poll()
    #expect(batch.events.count == 1)
    #expect(batch.events[0].isTolerated)
    #expect(await sync.cursor == "9000")

    // The data layer is where it is skipped.
    #expect(await model.ingest(batch.events) == false)
    #expect((await model.state().items).isEmpty)
  }

  @Test func modelSkipsToleratedEventsDirectly() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let model = ConversationModel(
      convoId: "convo-1", client: chat(server), senderDid: Fixtures.selfDid)

    let changed = await model.ingest([
      .groupEvent(type: "chat.bsky.convo.defs#logEditGroup", rev: "5", convoId: "convo-1"),
      .other(type: "chat.bsky.convo.defs#unknown", rev: "6", convoId: "convo-1"),
    ])
    #expect(changed == false)
    #expect((await model.state().items).isEmpty)
  }

  @Test func groupConvoKindIsDecoded() async throws {
    let server = FakeChatServer()
    server.addConvo(
      id: "group-1", members: [Fixtures.selfDid, Fixtures.otherDid], group: true)
    let convo = try await chat(server).getConvo(convoId: "group-1")
    guard case .convoDefsGroupConvo = convo.kind else {
      Issue.record("expected a group convo kind")
      return
    }
    #expect(!InboxQuery.isDirectConvo(convo))
  }

  @Test func unknownLogCreateMessagePayloadIsTolerated() async throws {
    let server = FakeChatServer()
    // A create whose `message` is a message type this client does not know.
    server.emitLog([
      "$type": "chat.bsky.convo.defs#logCreateMessage",
      "rev": "1",
      "convoId": "convo-1",
      "message": [
        "$type": "chat.bsky.convo.defs#futureMessageView",
        "id": "x",
      ],
    ])
    let page = try await chat(server).getLog(cursor: nil)
    guard case .createMessage(_, _, let message, _) = page.logs[0] else {
      Issue.record("expected a createMessage event")
      return
    }
    #expect(message.isUnknown)
  }

  @Test func unknownSystemMessageDataIsTolerated() async throws {
    let server = FakeChatServer()
    server.emitLog([
      "$type": "chat.bsky.convo.defs#logCreateMessage",
      "rev": "1",
      "convoId": "convo-1",
      "message": [
        "$type": "chat.bsky.convo.defs#systemMessageView",
        "id": "sys-1",
        "rev": "1",
        "sentAt": Fixtures.defaultDate,
        "data": ["$type": "chat.bsky.convo.defs#systemMessageDataFuture"],
      ],
    ])
    // Decoding must not throw. `logCreateMessage`'s message union only refs
    // `messageView`/`deletedMessageView`, so a system view arriving there is an
    // unknown union arm and is tolerated - the point being that it does not
    // crash the poll.
    let page = try await chat(server).getLog(cursor: nil)
    #expect(page.logs.count == 1)
    guard case .createMessage(_, _, let message, _) = page.logs[0] else {
      Issue.record("expected a createMessage event")
      return
    }
    #expect(message.isUnknown)
  }

  @Test func unknownMessageUnionInGetMessagesIsTolerated() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    server.addMessage(convoId: "convo-1", text: "known", sender: Fixtures.otherDid)
    let page = try await chat(server).getMessages(convoId: "convo-1", limit: 10, cursor: nil)
    #expect(page.messages.count == 1)
    #expect(!page.messages[0].isUnknown)
  }
}
