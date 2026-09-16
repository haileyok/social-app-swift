import ATProtoClient
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

  /// `chat.bsky.convo.getConvoAvailability`. Checks whether a direct chat may start.
  func getConvoAvailability(
    members: [String]
  ) async throws -> Chat.Bsky.ConvoGetConvoAvailability_Output

  /// `chat.bsky.convo.getConvoForMembers`. Gets or creates the stable direct chat.
  func getConvoForMembers(
    members: [String]
  ) async throws -> Chat.Bsky.ConvoDefs_ConvoView

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

  /// `chat.bsky.convo.acceptConvo`. Accepts a pending chat request.
  func acceptConvo(convoId: String) async throws

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
/// Starts a direct conversation while enforcing the same eligibility gate as RN.
public struct NewConversationService: Sendable {
  private let client: any ChatXrpc
  private let currentAccountDid: String

  public init(client: any ChatXrpc, currentAccountDid: String) {
    self.client = client
    self.currentAccountDid = currentAccountDid
  }

  /// Returns an existing conversation when availability includes one; otherwise
  /// asks chat for the stable direct conversation. The signed-in account cannot
  /// be selected as its own recipient.
  public func start(with recipientDid: String) async throws
    -> Chat.Bsky.ConvoDefs_ConvoView {
    guard recipientDid != currentAccountDid else { throw NewConversationFailure.cannotMessageSelf }
    do {
      let availability = try await client.getConvoAvailability(members: [recipientDid])
      if let existing = availability.convo { return existing }
      guard availability.canChat else { throw NewConversationFailure.recipientUnavailable }
      return try await client.getConvoForMembers(members: [recipientDid])
    } catch let failure as NewConversationFailure {
      throw failure
    } catch let error as XrpcError {
      throw NewConversationFailure(xrpcCode: error.rawCode, status: error.status)
    } catch {
      throw NewConversationFailure.network
    }
  }
}

/// Stable, localized-ready failure reasons for starting a direct chat.
public enum NewConversationFailure: Error, Sendable, Equatable {
  case cannotMessageSelf
  case recipientUnavailable
  case accountSuspended
  case blockedActor
  case blockedSubject
  case messagesDisabled
  case notFollowedBySender
  case recipientNotFound
  case network
  case unknown

  public init(xrpcCode: String?, status: Int) {
    switch xrpcCode {
    case "AccountSuspended": self = .accountSuspended
    case "BlockedActor": self = .blockedActor
    case "BlockedSubject": self = .blockedSubject
    case "MessagesDisabled": self = .messagesDisabled
    case "NotFollowedBySender": self = .notFollowedBySender
    case "RecipientNotFound": self = .recipientNotFound
    default: self = status == 0 || status >= 500 ? .network : .unknown
    }
  }

  public var message: String {
    switch self {
    case .cannotMessageSelf: "You can't start a chat with yourself."
    case .recipientUnavailable: "This user can't be messaged."
    case .accountSuspended: "Suspended accounts cannot participate in chat."
    case .blockedActor: "This user has blocked you and cannot be messaged."
    case .blockedSubject: "You have blocked this user. Unblock them to start a chat."
    case .messagesDisabled: "This user has disabled chat and cannot be messaged."
    case .notFollowedBySender: "Chat recipient is not followed by the sender."
    case .recipientNotFound: "Unable to find the selected recipient."
    case .network: "A network error occurred. Please check your internet connection."
    case .unknown: "An issue occurred starting the chat. Please try again."
    }
  }
}

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
