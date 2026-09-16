import ATProtoClient
import Foundation
import Lexicons
import Testing

@testable import MessagesLogic

/// The chat client wiring: proxy routing, method/URL shape, params and bodies.
///
/// These drive ``LiveChatXrpc`` over the fake server, so the URL building, param
/// encoding, proxy header and JSON decoding are all exercised end to end.
@Suite("ChatClientWiring")
struct ChatClientWiringTests {
  /// Builds a live client pointed at the fake, with the chat proxy header.
  private func makeClient(
    _ server: FakeChatServer
  ) -> (LiveChatXrpc, XrpcClient) {
    let client = XrpcClient(
      baseURL: "https://pds.example", proxyService: BlueskyAPI.chatService,
      labelers: [BlueskyAPI.moderationDid + ";redact"],
      extraHeaders: ["Authorization": "Bearer tok"],
      transport: server)
    return (LiveChatXrpc(client: client, authorization: "tok"), client)
  }

  @Test func chatProxyHeaderIsEmittedOnEveryCall() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)

    _ = try await chat.listConvos(
      status: .accepted, readState: nil, kind: nil, limit: 10, cursor: nil)
    _ = try await chat.getConvo(convoId: "convo-1")
    _ = try await chat.getMessages(convoId: "convo-1", limit: 30, cursor: nil)
    _ = try await chat.getLog(cursor: nil)
    _ = try await chat.getUnreadCounts(includeGroupChats: true)

    #expect(server.requests.count == 5)
    for request in server.requests {
      #expect(
        request.headers["atproto-proxy"] == "did:web:api.bsky.chat#bsky_chat",
        "\(request.procedure) must carry the chat proxy header")
      #expect(request.headers["Authorization"] == "Bearer tok")
      #expect(
        request.headers["atproto-accept-labelers"] == "did:plc:ar7c4by46qjdydhdevvrndac;redact")
    }
  }

  @Test func chatProxyIsNotTheAppviewProxy() async throws {
    let server = FakeChatServer()
    let (chat, _) = makeClient(server)
    _ = try await chat.getLog(cursor: nil)
    let proxy = server.lastRequest?.headers["atproto-proxy"]
    #expect(proxy == BlueskyAPI.chatService)
    #expect(proxy != BlueskyAPI.appService)
  }

  @Test func listConvosEncodesQueryParams() async throws {
    let server = FakeChatServer()
    let (chat, _) = makeClient(server)
    _ = try await chat.listConvos(
      status: .accepted, readState: .unread, kind: .direct, limit: 25, cursor: "abc")

    let request = try #require(server.requests(for: Chat.Bsky.ConvoListConvos.id).first)
    #expect(request.method == "GET")
    #expect(request.param("status") == "accepted")
    #expect(request.param("readState") == "unread")
    #expect(request.param("kind") == "direct")
    #expect(request.param("limit") == "25")
    #expect(request.param("cursor") == "abc")
  }

  @Test func listConvosOmitsNilFilters() async throws {
    let server = FakeChatServer()
    let (chat, _) = makeClient(server)
    _ = try await chat.listConvos(
      status: nil, readState: nil, kind: nil, limit: 10, cursor: nil)

    let request = try #require(server.requests(for: Chat.Bsky.ConvoListConvos.id).first)
    #expect(request.param("status") == nil)
    #expect(request.param("readState") == nil)
    #expect(request.param("kind") == nil)
    #expect(request.param("cursor") == nil)
    #expect(request.param("limit") == "10")
  }

  @Test func listConvosDecodesConvosAndCursor() async throws {
    let server = FakeChatServer()
    for index in 0..<3 {
      server.addConvo(
        id: "convo-\(index)", members: [Fixtures.selfDid, Fixtures.otherDid])
    }
    let (chat, _) = makeClient(server)

    let first = try await chat.listConvos(
      status: nil, readState: nil, kind: nil, limit: 2, cursor: nil)
    #expect(first.convos.count == 2)
    #expect(first.cursor == "2")

    let second = try await chat.listConvos(
      status: nil, readState: nil, kind: nil, limit: 2, cursor: first.cursor)
    #expect(second.convos.count == 1)
    #expect(second.cursor == nil)
  }

  @Test func getMessagesEncodesConvoIdLimitCursor() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)
    _ = try await chat.getMessages(convoId: "convo-1", limit: 30, cursor: "c1")

    let request = try #require(server.requests(for: Chat.Bsky.ConvoGetMessages.id).first)
    #expect(request.param("convoId") == "convo-1")
    #expect(request.param("limit") == "30")
    #expect(request.param("cursor") == "c1")
  }

  @Test func getLogEncodesCursorOnly() async throws {
    let server = FakeChatServer()
    let (chat, _) = makeClient(server)
    _ = try await chat.getLog(cursor: "42")
    let request = try #require(server.requests(for: Chat.Bsky.ConvoGetLog.id).first)
    #expect(request.param("cursor") == "42")
    #expect(request.params.count == 1)

    _ = try await chat.getLog(cursor: nil)
    let bare = try #require(server.requests(for: Chat.Bsky.ConvoGetLog.id).last)
    #expect(bare.params.isEmpty)
  }

  @Test func sendMessagePostsExactInputBody() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)
    _ = try await chat.sendMessage(convoId: "convo-1", message: Fixtures.input("hello"))

    let request = try #require(server.requests(for: Chat.Bsky.ConvoSendMessage.id).first)
    #expect(request.method == "POST")
    let body = try #require(request.json)
    #expect(body["convoId"] as? String == "convo-1")
    let message = try #require(body["message"] as? [String: Any])
    #expect(message["text"] as? String == "hello")
    // `messageInput` is a plain ref, not a union member, so the generated input
    // carries no `$type` discriminator - unlike the log/view unions.
    #expect(message["$type"] == nil)
  }

  @Test func sendMessageBatchPostsItemsArray() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)
    let sent = try await chat.sendMessageBatch(items: [
      (convoId: "convo-1", message: Fixtures.input("one")),
      (convoId: "convo-1", message: Fixtures.input("two")),
    ])

    #expect(sent.count == 2)
    let request = try #require(server.requests(for: Chat.Bsky.ConvoSendMessageBatch.id).first)
    let body = try #require(request.json)
    let items = try #require(body["items"] as? [[String: Any]])
    #expect(items.count == 2)
    #expect((items[0]["message"] as? [String: Any])?["text"] as? String == "one")
    #expect(items[0]["convoId"] as? String == "convo-1")
  }

  @Test func addReactionPostsConvoMessageValue() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let (chat, _) = makeClient(server)

    let updated = try await chat.addReaction(
      convoId: "convo-1", messageId: message.id, value: "👍")
    #expect(updated.reactions?.count == 1)

    let request = try #require(server.requests(for: Chat.Bsky.ConvoAddReaction.id).first)
    let body = try #require(request.json)
    #expect(body["convoId"] as? String == "convo-1")
    #expect(body["messageId"] as? String == message.id)
    #expect(body["value"] as? String == "👍")
  }

  @Test func removeReactionPostsSameShape() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "hi", sender: Fixtures.otherDid)
    let (chat, _) = makeClient(server)
    _ = try await chat.addReaction(convoId: "convo-1", messageId: message.id, value: "🔥")
    let updated = try await chat.removeReaction(
      convoId: "convo-1", messageId: message.id, value: "🔥")

    #expect(updated.reactions?.isEmpty == true)
    let request = try #require(server.requests(for: Chat.Bsky.ConvoRemoveReaction.id).first)
    #expect(try #require(request.json)["value"] as? String == "🔥")
  }

  @Test func updateReadPostsConvoAndOptionalMessage() async throws {
    let server = FakeChatServer()
    server.addConvo(
      id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid], unreadCount: 3)
    let (chat, _) = makeClient(server)

    let withMessage = try await chat.updateRead(convoId: "convo-1", messageId: "m1")
    #expect(withMessage.unreadCount == 0)

    let request = try #require(server.requests(for: Chat.Bsky.ConvoUpdateRead.id).first)
    let body = try #require(request.json)
    #expect(body["convoId"] as? String == "convo-1")
    #expect(body["messageId"] as? String == "m1")

    _ = try await chat.updateRead(convoId: "convo-1", messageId: nil)
    let bare = try #require(server.requests(for: Chat.Bsky.ConvoUpdateRead.id).last)
    // A nil messageId must not be serialized as a key at all.
    #expect(try #require(bare.json)["messageId"] == nil || bare.json?["messageId"] is NSNull)
  }

  @Test func updateAllReadPostsStatus() async throws {
    let server = FakeChatServer()
    server.addConvo(
      id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid], unreadCount: 2)
    let (chat, _) = makeClient(server)

    let updated = try await chat.updateAllRead(status: .accepted)
    #expect(updated == 1)

    let request = try #require(server.requests(for: Chat.Bsky.ConvoUpdateAllRead.id).first)
    #expect(try #require(request.json)["status"] as? String == "accepted")
  }

  @Test func getUnreadCountsEncodesIncludeGroupChats() async throws {
    let server = FakeChatServer()
    server.setUnreadCounts(accepted: 4, request: 1)
    let (chat, _) = makeClient(server)

    #expect(try await chat.getUnreadCounts(includeGroupChats: false).unreadAcceptedConvos == 4)
    let request = try #require(server.requests(for: Chat.Bsky.ConvoGetUnreadCounts.id).first)
    #expect(request.param("includeGroupChats") == "false")

    // The sentinel cap is passed through, not clamped locally.
    server.setUnreadCounts(accepted: 100, request: 100)
    let capped = try await chat.getUnreadCounts(includeGroupChats: true)
    #expect(capped.unreadAcceptedConvos == UnreadCounts.cap)
    #expect(capped.unreadRequestConvos == UnreadCounts.cap)
  }

  @Test func muteAndUnmuteRouteToTheirProcedures() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)

    let muted = try await chat.muteConvo(convoId: "convo-1")
    #expect(muted.muted)
    #expect(server.requests(for: Chat.Bsky.ConvoMuteConvo.id).count == 1)

    let unmuted = try await chat.unmuteConvo(convoId: "convo-1")
    #expect(!unmuted.muted)
    #expect(server.requests(for: Chat.Bsky.ConvoUnmuteConvo.id).count == 1)
  }

  @Test func acceptConvoRoutesIdToProcedure() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)

    try await chat.acceptConvo(convoId: "convo-1")

    let request = try #require(server.requests(for: Chat.Bsky.ConvoAcceptConvo.id).first)
    #expect(request.json?["convoId"] as? String == "convo-1")
  }

  @Test func leaveConvoReturnsIdAndRev() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)

    let result = try await chat.leaveConvo(convoId: "convo-1")
    #expect(result.convoId == "convo-1")
    #expect(!result.rev.isEmpty)
    #expect(server.convo("convo-1") == nil)
  }

  @Test func deleteMessageForSelfDecodesDeletedView() async throws {
    let server = FakeChatServer()
    server.addConvo(id: "convo-1", members: [Fixtures.selfDid, Fixtures.otherDid])
    let message = server.addMessage(convoId: "convo-1", text: "bye", sender: Fixtures.selfDid)
    let (chat, _) = makeClient(server)

    let deleted = try await chat.deleteMessageForSelf(
      convoId: "convo-1", messageId: message.id)
    #expect(deleted.id == message.id)

    let request = try #require(
      server.requests(for: Chat.Bsky.ConvoDeleteMessageForSelf.id).first)
    let body = try #require(request.json)
    #expect(body["convoId"] as? String == "convo-1")
    #expect(body["messageId"] as? String == message.id)
  }

  @Test func newConversationUsesAvailabilityThenStableDirectLookup() async throws {
    let server = FakeChatServer()
    let (chat, _) = makeClient(server)
    let service = NewConversationService(client: chat, currentAccountDid: Fixtures.selfDid)

    let created = try await service.start(with: Fixtures.otherDid)

    #expect(created.members.contains { $0.did.rawValue == Fixtures.otherDid })
    let availability = try #require(
      server.requests(for: Chat.Bsky.ConvoGetConvoAvailability.id).first)
    #expect(availability.method == "GET")
    #expect(availability.params["members"] == [Fixtures.otherDid])
    let lookup = try #require(
      server.requests(for: Chat.Bsky.ConvoGetConvoForMembers.id).first)
    #expect(lookup.method == "GET")
    #expect(lookup.params["members"] == [Fixtures.otherDid])
  }

  @Test func newConversationReturnsExistingAvailabilityWithoutCreatingAgain() async throws {
    let server = FakeChatServer()
    let existing = server.addConvo(
      id: "existing", members: [Fixtures.selfDid, Fixtures.otherDid])
    let (chat, _) = makeClient(server)
    let service = NewConversationService(client: chat, currentAccountDid: Fixtures.selfDid)

    let opened = try await service.start(with: Fixtures.otherDid)

    #expect(opened.id == existing.id)
    #expect(server.requests(for: Chat.Bsky.ConvoGetConvoForMembers.id).isEmpty)
  }

  @Test func newConversationRejectsSelfWithoutNetwork() async throws {
    let server = FakeChatServer()
    let (chat, _) = makeClient(server)
    let service = NewConversationService(client: chat, currentAccountDid: Fixtures.selfDid)

    await #expect(throws: NewConversationFailure.cannotMessageSelf) {
      _ = try await service.start(with: Fixtures.selfDid)
    }
    #expect(server.requests.isEmpty)
  }

  @Test func newConversationFailuresMatchRNMessages() {
    let cases: [(String?, Int, NewConversationFailure)] = [
      ("AccountSuspended", 400, .accountSuspended),
      ("BlockedActor", 400, .blockedActor),
      ("BlockedSubject", 400, .blockedSubject),
      ("MessagesDisabled", 400, .messagesDisabled),
      ("NotFollowedBySender", 400, .notFollowedBySender),
      ("RecipientNotFound", 400, .recipientNotFound),
      (nil, 503, .network),
      ("Other", 400, .unknown),
    ]
    for (code, status, expected) in cases {
      let actual = NewConversationFailure(xrpcCode: code, status: status)
      #expect(actual == expected)
      #expect(!actual.message.isEmpty)
    }
  }

  @Test func serviceErrorsSurfaceAsXrpcErrors() async throws {
    let server = FakeChatServer()
    server.fail(
      Chat.Bsky.ConvoGetConvo.id, status: 400, error: "InvalidConvo", message: "no such convo")
    let (chat, _) = makeClient(server)

    await #expect(throws: XrpcError.self) {
      _ = try await chat.getConvo(convoId: "nope")
    }
  }
}
