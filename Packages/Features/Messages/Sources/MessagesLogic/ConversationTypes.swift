import ATProtoClient
import Foundation
import Lexicons

/// The value types the conversation model exposes.
///
/// Split out of ``ConversationModel`` so the actor file stays focused on the
/// state machine; the types are the port of the `ConvoItem` / `ConvoState`
/// unions in `src/state/messages/convo/types.ts`.

public enum ConvoItem: Sendable, Hashable {
  /// A user-originated message.
  case message(Chat.Bsky.ConvoDefs_MessageView)
  /// A deleted-message tombstone.
  case deletedMessage(Chat.Bsky.ConvoDefs_DeletedMessageView)
  /// A system message.
  case systemMessage(Chat.Bsky.ConvoDefs_SystemMessageView)
  /// A locally echoed message awaiting a server id.
  case pendingMessage(PendingMessage)
  /// A retryable error row.
  case error(code: ConvoItemErrorCode)

  /// The list key. RN's `key`.
  public var key: String {
    switch self {
    case .message(let m): m.id
    case .deletedMessage(let m): m.id
    case .systemMessage(let m): m.id
    case .pendingMessage(let m): m.id
    case .error(let code): code.rawValue
    }
  }

  /// The message identity, for the deleted-set filter. Non-message rows are nil.
  public var messageId: String? {
    switch self {
    case .message(let m): m.id
    case .deletedMessage(let m): m.id
    case .systemMessage(let m): m.id
    case .pendingMessage(let m): m.id
    case .error: nil
    }
  }
}

/// Error rows a conversation can render.
public enum ConvoItemErrorCode: String, Sendable, Hashable {
  /// History fetching failed. RN: `ConvoItemError.HistoryFailed`.
  case historyFailed = "error-history-failed"
  /// The log firehose failed. RN: `ConvoItemError.FirehoseFailed`.
  case firehoseFailed = "error-firehose-failed"
}

/// A locally echoed message awaiting reconciliation.
///
/// RN keeps `{id: tempId, message: MessageInput}` in `pendingMessages` and
/// synthesizes a `messageView` at render time (`getItems`). This port keeps the
/// same split: the pending entry carries the input and the synthesized
/// placeholder carries the shape the list renders.
public struct PendingMessage: Sendable, Hashable {
  /// The temporary id, unique within the conversation.
  public var id: String
  /// The input the caller asked to send.
  public var message: Chat.Bsky.ConvoDefs_MessageInput
  /// Whether the whole pending queue is in a failed state.
  public var failed: Bool

  public init(id: String, message: Chat.Bsky.ConvoDefs_MessageInput, failed: Bool = false) {
    self.id = id
    self.message = message
    self.failed = failed
  }

  /// The placeholder message view the list renders for this pending entry.
  ///
  /// Port of the synthesized view in RN's `getItems`: a real-looking view whose
  /// rev is the sentinel `__fake__` so a log event carrying the real one
  /// replaces it cleanly.
  public func placeholderView(senderDid: String, sentAt: Date) -> Chat.Bsky.ConvoDefs_MessageView {
    ConvoMessage.optimisticMessageView(
      id: id, rev: ConvoMessage.fakeRev, senderDid: senderDid, sentAt: sentAt,
      text: message.text, facets: message.facets)
  }
}

extension ConvoMessage {
  /// The sentinel rev the RN agent stamps on a locally echoed message.
  public static let fakeRev = "__fake__"
}

/// How a send failure should be treated.
///
/// Port of `pendingMessageFailure` in `src/state/messages/convo/agent.ts`:
/// a 5xx-class failure is `recoverable` (the whole queue is retryable via
/// `sendMessageBatch`), anything else is `unrecoverable` and just renders as
/// failed.
public enum SendFailure: String, Sendable, Hashable {
  /// The server was unavailable; the queue can be retried as a batch.
  case recoverable
  /// The server rejected the message; retrying will not help.
  case unrecoverable
}

/// The state one conversation's model holds.
public struct ConversationState: Sendable, Equatable {
  /// The convo view, once loaded.
  public var convo: Chat.Bsky.ConvoDefs_ConvoView?
  /// The rendered items, in display order.
  public var items: [ConvoItem]
  /// True while an older history page is in flight.
  public var isFetchingHistory: Bool
  /// True when every older page has been read (RN's `oldestRev === null`).
  public var hasAllHistory: Bool
  /// The current send failure, if any.
  public var pendingMessageFailure: SendFailure?
  /// True when history fetching failed and a retry row is showing.
  public var historyFailed: Bool

  public init(
    convo: Chat.Bsky.ConvoDefs_ConvoView? = nil, items: [ConvoItem] = [],
    isFetchingHistory: Bool = false, hasAllHistory: Bool = false,
    pendingMessageFailure: SendFailure? = nil, historyFailed: Bool = false
  ) {
    self.convo = convo
    self.items = items
    self.isFetchingHistory = isFetchingHistory
    self.hasAllHistory = hasAllHistory
    self.pendingMessageFailure = pendingMessageFailure
    self.historyFailed = historyFailed
  }
}

public enum MessagesReaction {
  /// The maximum wire length of a reaction value, from the lexicon
  /// (`maxLength: 64`).
  public static let maxLength = 64

  /// True when `value` is a single grapheme cluster, the lexicon's
  /// `minGraphemes: 1, maxGraphemes: 1` rule.
  ///
  /// Unicode grapheme segmentation is what makes a multi-scalar emoji (a flag,
  /// a skin-toned hand, a ZWJ family) count as one.
  public static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maxLength else { return false }
    return value.count == 1
  }
}

/// Errors the reaction flow surfaces.
public enum ConvoReactionError: Error, Sendable, Hashable {
  /// The value was not a single grapheme.
  case invalidEmoji(String)
  /// The sender already holds ``MessagesConstants/maxReactionsPerSender``
  /// reactions on this message.
  case tooManyReactions
}

/// The status-carrying slice of an XRPC error, so the send path can classify a
/// failure without depending on the concrete error type.
public protocol XrpcErrorLike: Error {
  /// The HTTP status, or a negative value for a transport-level failure.
  var status: Int { get }
}
