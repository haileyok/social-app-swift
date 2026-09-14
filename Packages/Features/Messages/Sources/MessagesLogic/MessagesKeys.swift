import Foundation
import QueryStore

/// Query-key builders for messages.
///
/// Ports the RN key roots so a persisted snapshot and a live key agree:
/// `convo-list` (`RQKEY_ROOT` in `list-conversations.tsx`), `convo`
/// (`RQKEY_ROOT` in `conversation.ts`), and `convo-unread-counts`
/// (`RQKEY_ROOT` in `get-unread-counts.ts`).
public enum MessagesKeys {
  /// Root for the inbox list. RN: `RQKEY_ROOT = 'convo-list'`.
  public static let convoListRoot = "convo-list"
  /// Root for a single conversation view. RN: `'convo'`.
  public static let convoRoot = "convo"
  /// Root for the badge counts. RN: `'convo-unread-counts'`.
  public static let unreadCountsRoot = "convo-unread-counts"
  /// Root for a conversation's message history.
  public static let messagesRoot = "convo-messages"

  /// Args for an inbox-list key. RN encodes `status`, `readState`, `kind`,
  /// `lockStatus` and `limit` positionally in the key tuple; this port renders
  /// them as a struct so the identity is self-describing.
  ///
  /// `lockStatus` exists on the wire for group convos only and is always nil in
  /// the 1:1 scope; it is kept so the key shape matches RN and a persisted key
  /// round-trips.
  public struct ConvoListArgs: QueryArgs {
    /// `request`, `accepted`, or `all`.
    public let status: String
    /// `all` or `unread`.
    public let readState: String
    /// `all`, `direct` or `group`.
    public let kind: String
    /// `unlocked`, `locked`, `locked-permanently`, or nil.
    public let lockStatus: String?
    /// Page size.
    public let limit: Int

    public init(
      status: String = "accepted", readState: String = "all",
      kind: String = "all", lockStatus: String? = nil, limit: Int = MessagesConstants.inboxLimit
    ) {
      self.status = status
      self.readState = readState
      self.kind = kind
      self.lockStatus = lockStatus
      self.limit = limit
    }
  }

  /// The inbox-list key, ported from `RQKEY(status, readState, kind, lockStatus, limit)`.
  public static func convoList(
    status: ConvoStatusFilter? = nil, readState: ConvoReadStateFilter? = nil,
    kind: ConvoKindFilter? = nil, lockStatus: String? = nil,
    limit: Int = MessagesConstants.inboxLimit, scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      convoListRoot,
      ConvoListArgs(
        status: status?.rawValue ?? "all", readState: readState?.rawValue ?? "all",
        kind: kind?.rawValue ?? "all", lockStatus: lockStatus, limit: limit),
      options: QueryOptions(scope: scope))
  }

  /// Args for a single-conversation key.
  public struct ConvoArgs: QueryArgs {
    public let convoId: String

    public init(convoId: String) {
      self.convoId = convoId
    }
  }

  /// The single-conversation key, ported from `RQKEY(convoId) = ['convo', convoId]`.
  public static func convo(_ convoId: String, scope: String? = nil) -> QueryKey {
    QueryKey(
      convoRoot, ConvoArgs(convoId: convoId),
      options: QueryOptions(scope: scope))
  }

  /// The message-history key for a conversation. RN keeps history in the convo
  /// agent rather than a query; this port models it as one so paging, staleness
  /// and persistence go through the same machinery as every other list.
  public static func messages(_ convoId: String, scope: String? = nil) -> QueryKey {
    QueryKey(
      messagesRoot, ConvoArgs(convoId: convoId),
      options: QueryOptions(scope: scope))
  }

  /// Args for the badge-count key. RN: `RQKEY(includeGroupChats)`.
  public struct UnreadCountsArgs: QueryArgs {
    public let includeGroupChats: Bool

    public init(includeGroupChats: Bool) {
      self.includeGroupChats = includeGroupChats
    }
  }

  /// The badge-count key, ported from `RQKEY(includeGroupChats)`.
  public static func unreadCounts(
    includeGroupChats: Bool = true, scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      unreadCountsRoot, UnreadCountsArgs(includeGroupChats: includeGroupChats),
      options: QueryOptions(scope: scope))
  }
}

/// Tuning constants for the messages queries, ported from the RN defaults.
public enum MessagesConstants {
  /// Inbox page size. RN `DEFAULT_LIMIT = 10` in `list-conversations.tsx`.
  public static let inboxLimit = 10
  /// Message-history page size. RN uses 30 native / 60 web in `fetchMessageHistory`.
  public static let messageHistoryLimit = 30
  /// Badge-count staleness. RN: `STALE.SECONDS.FIFTEEN`.
  public static let unreadCountsStale = STALE.SECONDS.FIFTEEN
  /// Cap on distinct emoji a sender may leave on one message. RN: 5.
  public static let maxReactionsPerSender = 5
  /// Tolerant status codes for a send failure, ported from `NETWORK_FAILURE_STATUSES`.
  public static let networkFailureStatuses: Set<Int> = [502, 503, 504]
}
