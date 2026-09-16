import Foundation
import Lexicons
import MessagesLogic
import SwiftAtproto

/// A `ChatXrpc` that answers from a fixed script, for the fixture surfaces.
///
/// `MessagesLogic`'s own fake chat server is a test target, not a product, so the
/// preview/fixture surfaces need one of their own. This client is deliberately
/// tiny: it records the calls it received and answers them from the fixture data,
/// which is enough to drive a conversation through history, a successful send, a
/// failed send, reactions and read state without a session or a network.
///
/// The failure is *scripted*, not random: the first `sendMessage` for the failed
/// text throws a 503, which ``ConversationModel`` classifies as a recoverable
/// failure and renders as a retryable outbox, and a later retry via
/// `sendMessageBatch` succeeds. That is what makes the fixture deterministic.
public actor ScriptedChatClient: ChatXrpc {
  /// The conversations this client serves, keyed by id.
  private var convos: [String: Chat.Bsky.ConvoDefs_ConvoView]
  /// History per conversation, oldest first.
  private var history: [String: [ConvoMessage]]
  /// The texts whose send fails on the first attempt.
  private var failingOnce: Set<String>
  /// Texts that have already failed once, so a retry succeeds.
  private var alreadyFailed: Set<String> = []
  /// The next temp message counter.
  private var counter = 0
  /// The call log, for assertions.
  private var calls: [String] = []

  /// Creates a scripted client.
  ///
  /// - Parameters:
  ///   - convos: the conversations to serve.
  ///   - history: per-conversation history, oldest first.
  ///   - failingOnce: send texts that fail on their first attempt.
  public init(
    convos: [Chat.Bsky.ConvoDefs_ConvoView],
    history: [String: [ConvoMessage]] = [:],
    failingOnce: Set<String> = []
  ) {
    self.convos = Dictionary(uniqueKeysWithValues: convos.map { ($0.id, $0) })
    self.history = history
    self.failingOnce = failingOnce
  }

  /// The calls received, in order.
  public func recordedCalls() -> [String] { calls }

  // MARK: - Convos

  public func listConvos(
    status: ConvoStatusFilter?, readState: ConvoReadStateFilter?,
    kind: ConvoKindFilter?, limit: Int, cursor: String?
  ) async throws -> ConvoListPage {
    calls.append("listConvos")
    var items = Array(convos.values).sorted { $0.rev > $1.rev }
    if let status {
      items = items.filter { $0.status?.rawValue == status.rawValue }
    }
    if let readState, readState == .unread {
      items = items.filter { $0.unreadCount > 0 }
    }
    if let kind, kind == .direct {
      items = items.filter(InboxQuery.isDirectConvo)
    }
    return ConvoListPage(convos: Array(items.prefix(limit)), cursor: nil)
  }

  public func getConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    calls.append("getConvo")
    guard let convo = convos[convoId] else { throw ScriptedError.notFound }
    return convo
  }

  public func getConvoAvailability(
    members: [String]
  ) async throws -> Chat.Bsky.ConvoGetConvoAvailability_Output {
    calls.append("getConvoAvailability")
    let convo = convos.values.first { value in
      members.allSatisfy { member in value.members.contains { $0.did.rawValue == member } }
    }
    return Chat.Bsky.ConvoGetConvoAvailability_Output(canChat: true, convo: convo)
  }

  public func getConvoForMembers(
    members: [String]
  ) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    calls.append("getConvoForMembers")
    guard let convo = convos.values.first(where: { value in
      members.allSatisfy { member in value.members.contains { $0.did.rawValue == member } }
    }) else { throw ScriptedError.notFound }
    return convo
  }

  public func getMessages(
    convoId: String, limit: Int, cursor: String?
  ) async throws -> ConvoMessagesPage {
    calls.append("getMessages")
    // The server returns newest first; the model re-orders into history.
    let all = (history[convoId] ?? []).reversed().map { $0 }
    return ConvoMessagesPage(messages: Array(all.prefix(limit)), cursor: nil)
  }

  public func getLog(cursor: String?) async throws -> ChatLogPage {
    calls.append("getLog")
    return ChatLogPage(logs: [], cursor: cursor ?? "seed")
  }

  // MARK: - Sending

  public func sendMessage(
    convoId: String, message: Chat.Bsky.ConvoDefs_MessageInput
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView {
    calls.append("sendMessage")
    if failingOnce.contains(message.text), !alreadyFailed.contains(message.text) {
      alreadyFailed.insert(message.text)
      throw ScriptedError.serverUnavailable
    }
    return try materialize(convoId: convoId, message: message)
  }

  public func sendMessageBatch(
    items: [(convoId: String, message: Chat.Bsky.ConvoDefs_MessageInput)]
  ) async throws -> [Chat.Bsky.ConvoDefs_MessageView] {
    calls.append("sendMessageBatch")
    return try items.map { try materialize(convoId: $0.convoId, message: $0.message) }
  }

  private func materialize(
    convoId: String, message: Chat.Bsky.ConvoDefs_MessageInput
  ) throws -> Chat.Bsky.ConvoDefs_MessageView {
    counter += 1
    let id = "srv-\(counter)"
    return ConvoMessage.optimisticMessageView(
      id: id, rev: id, senderDid: convos[convoId]?.members.first?.did.rawValue ?? "did:plc:self",
      sentAt: Date(), text: message.text, facets: message.facets)
  }

  // MARK: - Reactions

  public func addReaction(
    convoId: String, messageId: String, value: String
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView {
    calls.append("addReaction")
    guard let view = try message(convoId: convoId, messageId: messageId) else {
      throw ScriptedError.notFound
    }
    var copy = view
    copy.reactions = (view.reactions ?? []) + [
      Chat.Bsky.ConvoDefs_ReactionView(
        createdAt: FormatString<Date>(rawValue: MessagesDate.datetimeString(Date())),
        sender: Chat.Bsky.ConvoDefs_ReactionViewSender(
          did: copy.sender.did),
        value: value)
    ]
    return copy
  }

  public func removeReaction(
    convoId: String, messageId: String, value: String
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView {
    calls.append("removeReaction")
    guard let view = try message(convoId: convoId, messageId: messageId) else {
      throw ScriptedError.notFound
    }
    var copy = view
    copy.reactions = (view.reactions ?? []).filter { $0.value != value }
    return copy
  }

  /// The message view for an id, when the script holds one.
  private func message(convoId: String, messageId: String) throws -> Chat.Bsky.ConvoDefs_MessageView? {
    let element = (history[convoId] ?? []).first { $0.id == messageId }
    return element?.messageView
  }

  // MARK: - Read state, mute, leave

  public func updateRead(
    convoId: String, messageId: String?
  ) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    calls.append("updateRead")
    guard var convo = convos[convoId] else { throw ScriptedError.notFound }
    convo.unreadCount = 0
    convos[convoId] = convo
    return convo
  }

  public func updateAllRead(status: ConvoStatusFilter?) async throws -> Int {
    calls.append("updateAllRead")
    let unreadIds = convos.compactMap { $0.value.unreadCount > 0 ? $0.key : nil }
    for id in unreadIds {
      convos[id]?.unreadCount = 0
    }
    return unreadIds.count
  }

  public func getUnreadCounts(includeGroupChats: Bool) async throws -> UnreadCounts {
    calls.append("getUnreadCounts")
    return UnreadCounts(
      unreadAcceptedConvos: convos.values.reduce(0) { $0 + $1.unreadCount },
      unreadRequestConvos: 0)
  }

  public func muteConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    try setMuted(convoId: convoId, muted: true)
  }

  public func unmuteConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    try setMuted(convoId: convoId, muted: false)
  }

  private func setMuted(convoId: String, muted: Bool) throws -> Chat.Bsky.ConvoDefs_ConvoView {
    calls.append(muted ? "muteConvo" : "unmuteConvo")
    guard var convo = convos[convoId] else { throw ScriptedError.notFound }
    convo.muted = muted
    convos[convoId] = convo
    return convo
  }

  public func acceptConvo(convoId: String) async throws {}

  public func leaveConvo(convoId: String) async throws -> ConvoLeaveResult {
    calls.append("leaveConvo")
    convos.removeValue(forKey: convoId)
    return ConvoLeaveResult(convoId: convoId, rev: "leave")
  }

  public func deleteMessageForSelf(
    convoId: String, messageId: String
  ) async throws -> Chat.Bsky.ConvoDefs_DeletedMessageView {
    calls.append("deleteMessageForSelf")
    guard let view = try message(convoId: convoId, messageId: messageId) else {
      throw ScriptedError.notFound
    }
    return ConvoMessage.tombstone(view)
  }
}

/// The failures the scripted client raises.
public enum ScriptedError: Error, Sendable {
  /// The script holds no such convo/message.
  case notFound
  /// A 503, so ``ConversationModel`` classifies the send as recoverable.
  case serverUnavailable
}

extension ScriptedError: XrpcErrorLike {
  /// The status the model classifies on. 503 is in
  /// ``MessagesConstants/networkFailureStatuses``, so the outbox stays retryable.
  public var status: Int {
    switch self {
    case .notFound: 404
    case .serverUnavailable: 503
    }
  }
}
