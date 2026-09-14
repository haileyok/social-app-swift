import Foundation
import Lexicons

/// The chat XRPC surface the 1:1 messages scope needs, behind a protocol so
/// tests can record and script exact calls.
///
/// Ported from the RN chat query modules under
/// `src/state/queries/messages/*` and `src/state/messages/*`. The live
/// implementation (``LiveChatXrpc``) runs over `ATProtoClient.XrpcClient`, so
/// the `atproto-proxy: did:web:api.bsky.chat#bsky_chat` routing header, the
/// acceptor labelers and the bearer token are emitted by the client exactly as
/// they are for every other feature.
///
/// ## Scope
///
/// This is the minimal 1:1 scope. Group, join-link and join-request procedures
/// (`chat.bsky.group.*`, `chat.bsky.convo.listConvoRequests`, `lockConvo`, ...)
/// are deliberately absent: the 1:1 product surface does not call them. Their
/// *wire shapes* are still decoded, tolerantly, by ``ChatLogEvent`` so a log
/// batch containing group events applies without throwing and is skipped at the
/// data layer.
public protocol ChatXrpc: Sendable {
  /// `chat.bsky.convo.listConvos`. Port of `useListConvosQuery`.
  func listConvos(
    status: ConvoStatusFilter?, readState: ConvoReadStateFilter?,
    kind: ConvoKindFilter?, limit: Int, cursor: String?
  ) async throws -> ConvoListPage

  /// `chat.bsky.convo.getConvo`. Port of `useConvoQuery`.
  func getConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView

  /// `chat.bsky.convo.getMessages`. Port of `fetchMessageHistory`.
  func getMessages(
    convoId: String, limit: Int, cursor: String?
  ) async throws -> ConvoMessagesPage

  /// `chat.bsky.convo.getLog`. Port of the events bus `init`/`poll`.
  func getLog(cursor: String?) async throws -> ChatLogPage

  /// `chat.bsky.convo.sendMessage`. Port of `processPendingMessages`.
  func sendMessage(
    convoId: String, message: Chat.Bsky.ConvoDefs_MessageInput
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView

  /// `chat.bsky.convo.sendMessageBatch`. Port of `batchRetryPendingMessages`.
  func sendMessageBatch(
    items: [(convoId: String, message: Chat.Bsky.ConvoDefs_MessageInput)]
  ) async throws -> [Chat.Bsky.ConvoDefs_MessageView]

  /// `chat.bsky.convo.addReaction`. Port of `addReaction`.
  func addReaction(
    convoId: String, messageId: String, value: String
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView

  /// `chat.bsky.convo.removeReaction`. Port of `removeReaction`.
  func removeReaction(
    convoId: String, messageId: String, value: String
  ) async throws -> Chat.Bsky.ConvoDefs_MessageView

  /// `chat.bsky.convo.updateRead`. Port of `useMarkAsReadMutation`.
  func updateRead(
    convoId: String, messageId: String?
  ) async throws -> Chat.Bsky.ConvoDefs_ConvoView

  /// `chat.bsky.convo.updateAllRead`. Port of `useUpdateAllRead`.
  func updateAllRead(status: ConvoStatusFilter?) async throws -> Int

  /// `chat.bsky.convo.getUnreadCounts`. Port of `useUnreadCountsQuery`.
  func getUnreadCounts(includeGroupChats: Bool) async throws -> UnreadCounts

  /// `chat.bsky.convo.muteConvo`. Port of `useMuteConvo`.
  func muteConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView

  /// `chat.bsky.convo.unmuteConvo`. Port of `useMuteConvo`.
  func unmuteConvo(convoId: String) async throws -> Chat.Bsky.ConvoDefs_ConvoView

  /// `chat.bsky.convo.leaveConvo`. Port of `useLeaveConvo`.
  func leaveConvo(convoId: String) async throws -> ConvoLeaveResult

  /// `chat.bsky.convo.deleteMessageForSelf`. Port of `deleteMessage`.
  func deleteMessageForSelf(
    convoId: String, messageId: String
  ) async throws
    -> Chat.Bsky.ConvoDefs_DeletedMessageView
}

/// The `status` filter `chat.bsky.convo.listConvos` accepts.
///
/// `request` is a real value on the wire; the 1:1 scope lists accepted convos,
/// but the type is open so request-inbox reads stay expressible.
public enum ConvoStatusFilter: String, Sendable, Hashable, CaseIterable {
  case request
  case accepted
}

/// The `readState` filter `chat.bsky.convo.listConvos` accepts.
public enum ConvoReadStateFilter: String, Sendable, Hashable {
  case unread
}

/// The `kind` filter `chat.bsky.convo.listConvos` accepts.
///
/// The 1:1 scope sends `direct`; `group` is expressible but its results are
/// skipped by the data layer.
public enum ConvoKindFilter: String, Sendable, Hashable {
  case direct
  case group
}

/// One page of `chat.bsky.convo.listConvos`.
public struct ConvoListPage: Sendable {
  /// The convos in this page, server-ordered by `rev` descending.
  public var convos: [Chat.Bsky.ConvoDefs_ConvoView]
  /// The cursor for the next page, or `nil` at the end.
  public var cursor: String?

  public init(convos: [Chat.Bsky.ConvoDefs_ConvoView] = [], cursor: String? = nil) {
    self.convos = convos
    self.cursor = cursor
  }
}

/// One page of `chat.bsky.convo.getMessages`.
public struct ConvoMessagesPage: Sendable {
  /// The messages in this page, newest first (the server walks backwards).
  public var messages: [ConvoMessage]
  /// The cursor for the next (older) page, or `nil` at the top of history.
  public var cursor: String?
  /// Profiles referred to by this page, merged into the convo's member set.
  public var relatedProfiles: [Chat.Bsky.ActorDefs_ProfileViewBasic]

  public init(
    messages: [ConvoMessage] = [], cursor: String? = nil,
    relatedProfiles: [Chat.Bsky.ActorDefs_ProfileViewBasic] = []
  ) {
    self.messages = messages
    self.cursor = cursor
    self.relatedProfiles = relatedProfiles
  }
}

/// One page of `chat.bsky.convo.getLog`.
///
/// The `logs` are ``ChatLogEvent`` values: a closed projection over the wire
/// union that keeps the event types the 1:1 scope acts on and represents
/// everything else (group, join-link, join-request, and future types) as
/// ``ChatLogEvent/other`` without throwing.
public struct ChatLogPage: Sendable {
  /// The log events, oldest first.
  public var logs: [ChatLogEvent]
  /// The server cursor: the newest `rev` at the time of the read. Seeds and
  /// advances the poll cursor.
  public var cursor: String?

  public init(logs: [ChatLogEvent] = [], cursor: String? = nil) {
    self.logs = logs
    self.cursor = cursor
  }
}

/// The output of `chat.bsky.convo.getUnreadCounts`.
///
/// The counts are server sentinel-capped at 100 ("more than 99"), so consumers
/// must not treat a value at the cap as exact. See ``UnreadCounts/cap``.
public struct UnreadCounts: Sendable, Equatable {
  /// Number of unread, unlocked accepted convos.
  public var unreadAcceptedConvos: Int
  /// Number of unread, unlocked request convos.
  public var unreadRequestConvos: Int

  /// The server sentinel cap for both counts (100 means "more than 99").
  public static let cap = 100

  public init(unreadAcceptedConvos: Int, unreadRequestConvos: Int) {
    self.unreadAcceptedConvos = unreadAcceptedConvos
    self.unreadRequestConvos = unreadRequestConvos
  }
}

/// The output of `chat.bsky.convo.leaveConvo`.
public struct ConvoLeaveResult: Sendable {
  /// The convo that was left.
  public var convoId: String
  /// The rev of the leave event.
  public var rev: String

  public init(convoId: String, rev: String) {
    self.convoId = convoId
    self.rev = rev
  }
}
