import ATProtoClient
import Foundation
import Lexicons

/// The live ``ChatXrpc`` over a proxy-routed chat ``XrpcClient``.
///
/// The client is built by `ATProtoClient.SessionClients` as `SessionClients.chat`
/// and already carries the `atproto-proxy: did:web:api.bsky.chat#bsky_chat`
/// header, the acceptor labelers and the bearer token. Nothing here re-implements
/// routing: it must be given the *chat* client, not the appview one, or every
/// call would go to the wrong service.
///
/// Every method forwards the same `authorization` token the session holds, so a
/// caller that refreshes the token only needs to rebuild this value.
public struct LiveChatXrpc: ChatXrpc {
  /// The signed-in chat client (`SessionClients.chat`).
  public let client: XrpcClient
  /// Authorization token, forwarded per request.
  public let authorization: String?

  public init(client: XrpcClient, authorization: String? = nil) {
    self.client = client
    self.authorization = authorization
  }

  public func listConvos(
    status: ConvoStatusFilter?, readState: ConvoReadStateFilter?,
    kind: ConvoKindFilter?, limit: Int, cursor: String?
  ) async throws -> ConvoListPage {
    let output: Chat.Bsky.ConvoListConvos_Output = try await client.get(
      Chat.Bsky.ConvoListConvos.id,
      params: [
        ("limit", String(limit)),
        ("cursor", cursor),
        ("readState", readState?.rawValue),
        ("kind", kind?.rawValue),
        ("status", status?.rawValue),
      ],
      authorization: authorization)
    return ConvoListPage(convos: output.convos, cursor: output.cursor)
  }

  public func getConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    let output: Chat.Bsky.ConvoGetConvo_Output = try await client.get(
      Chat.Bsky.ConvoGetConvo.id, params: [("convoId", convoId)],
      authorization: authorization)
    return output.convo
  }

  public func getConvoAvailability(
    members: [String]
  ) async throws -> Chat.Bsky.ConvoGetConvoAvailability_Output {
    try await client.get(
      Chat.Bsky.ConvoGetConvoAvailability.id,
      params: members.map { ("members", Optional($0)) },
      authorization: authorization)
  }

  public func getConvoForMembers(
    members: [String]
  ) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    let output: Chat.Bsky.ConvoGetConvoForMembers_Output = try await client.get(
      Chat.Bsky.ConvoGetConvoForMembers.id,
      params: members.map { ("members", Optional($0)) },
      authorization: authorization)
    return output.convo
  }

  public func getMessages(
    convoId: String, limit: Int, cursor: String?
  ) async throws -> ConvoMessagesPage {
    let output: Chat.Bsky.ConvoGetMessages_Output = try await client.get(
      Chat.Bsky.ConvoGetMessages.id,
      params: [
        ("convoId", convoId),
        ("limit", String(limit)),
        ("cursor", cursor),
      ],
      authorization: authorization)
    return ConvoMessagesPage(
      messages: output.messages.map(ConvoMessage.init),
      cursor: output.cursor,
      relatedProfiles: output.relatedProfiles ?? [])
  }

  public func getLog(cursor: String?) async throws -> ChatLogPage {
    let output: Chat.Bsky.ConvoGetLog_Output = try await client.get(
      Chat.Bsky.ConvoGetLog.id, params: [("cursor", cursor)],
      authorization: authorization)
    return ChatLogPage(
      logs: output.logs.map { ChatLogEvent($0) }, cursor: output.cursor)
  }

  public func sendMessage(
    convoId: String, message: Chat.Bsky.ConvoDefs_MessageInput
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView {
    try await client.procedure(
      Chat.Bsky.ConvoSendMessage.id,
      body: Chat.Bsky.ConvoSendMessage_Input(convoId: convoId, message: message),
      authorization: authorization)
  }

  public func sendMessageBatch(
    items: [(convoId: String, message: Chat.Bsky.ConvoDefs_MessageInput)]
  ) async throws -> [Chat.Bsky.ConvoDefs_MessageView] {
    let output: Chat.Bsky.ConvoSendMessageBatch_Output = try await client.procedure(
      Chat.Bsky.ConvoSendMessageBatch.id,
      body: Chat.Bsky.ConvoSendMessageBatch_Input(
        items: items.map {
          Chat.Bsky.ConvoSendMessageBatch_BatchItem(convoId: $0.convoId, message: $0.message)
        }),
      authorization: authorization)
    return output.items
  }

  public func addReaction(
    convoId: String, messageId: String, value: String
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView {
    let output: Chat.Bsky.ConvoAddReaction_Output = try await client.procedure(
      Chat.Bsky.ConvoAddReaction.id,
      body: Chat.Bsky.ConvoAddReaction_Input(
        convoId: convoId, messageId: messageId, value: value),
      authorization: authorization)
    return output.message
  }

  public func removeReaction(
    convoId: String, messageId: String, value: String
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView {
    let output: Chat.Bsky.ConvoRemoveReaction_Output = try await client.procedure(
      Chat.Bsky.ConvoRemoveReaction.id,
      body: Chat.Bsky.ConvoRemoveReaction_Input(
        convoId: convoId, messageId: messageId, value: value),
      authorization: authorization)
    return output.message
  }

  public func updateRead(
    convoId: String, messageId: String?
  ) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    let output: Chat.Bsky.ConvoUpdateRead_Output = try await client.procedure(
      Chat.Bsky.ConvoUpdateRead.id,
      body: Chat.Bsky.ConvoUpdateRead_Input(convoId: convoId, messageId: messageId),
      authorization: authorization)
    return output.convo
  }

  public func updateAllRead(status: ConvoStatusFilter?) async throws -> Int {
    let output: Chat.Bsky.ConvoUpdateAllRead_Output = try await client.procedure(
      Chat.Bsky.ConvoUpdateAllRead.id,
      body: Chat.Bsky.ConvoUpdateAllRead_Input(
        status: status.map { Chat.Bsky.ConvoUpdateAllRead_Input_Status(rawValue: $0.rawValue) }),
      authorization: authorization)
    return output.updatedCount
  }

  public func getUnreadCounts(includeGroupChats: Bool) async throws -> UnreadCounts {
    let output: Chat.Bsky.ConvoGetUnreadCounts_Output = try await client.get(
      Chat.Bsky.ConvoGetUnreadCounts.id,
      params: [("includeGroupChats", includeGroupChats ? "true" : "false")],
      authorization: authorization)
    return UnreadCounts(
      unreadAcceptedConvos: output.unreadAcceptedConvos,
      unreadRequestConvos: output.unreadRequestConvos)
  }

  public func muteConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    let output: Chat.Bsky.ConvoMuteConvo_Output = try await client.procedure(
      Chat.Bsky.ConvoMuteConvo.id,
      body: Chat.Bsky.ConvoMuteConvo_Input(convoId: convoId),
      authorization: authorization)
    return output.convo
  }

  public func unmuteConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    let output: Chat.Bsky.ConvoUnmuteConvo_Output = try await client.procedure(
      Chat.Bsky.ConvoUnmuteConvo.id,
      body: Chat.Bsky.ConvoUnmuteConvo_Input(convoId: convoId),
      authorization: authorization)
    return output.convo
  }

  public func acceptConvo(convoId: String) async throws {
    let _: Chat.Bsky.ConvoAcceptConvo_Output = try await client.procedure(
      Chat.Bsky.ConvoAcceptConvo.id,
      body: Chat.Bsky.ConvoAcceptConvo_Input(convoId: convoId),
      authorization: authorization)
  }

  public func leaveConvo(convoId: String) async throws -> ConvoLeaveResult {
    let output: Chat.Bsky.ConvoLeaveConvo_Output = try await client.procedure(
      Chat.Bsky.ConvoLeaveConvo.id,
      body: Chat.Bsky.ConvoLeaveConvo_Input(convoId: convoId),
      authorization: authorization)
    return ConvoLeaveResult(convoId: output.convoId, rev: output.rev)
  }

  public func deleteMessageForSelf(
    convoId: String, messageId: String
  ) async throws -> Chat.Bsky.ConvoDefs_DeletedMessageView {
    try await client.procedure(
      Chat.Bsky.ConvoDeleteMessageForSelf.id,
      body: Chat.Bsky.ConvoDeleteMessageForSelf_Input(
        convoId: convoId, messageId: messageId),
      authorization: authorization)
  }
}
