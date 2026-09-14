import Foundation
import Lexicons
import SwiftAtproto

/// A `rev` + `convoId` pair, the shape shared by every conversation-scoped log
/// event (`logBeginConvo`, `logAcceptConvo`, `logLeaveConvo`, `logMuteConvo`,
/// `logUnmuteConvo`, and the group-management events).
public struct ChatRevEvent: Sendable, Hashable {
  /// The event's monotonic revision on the chat service.
  public var rev: String
  /// The conversation the event belongs to.
  public var convoId: String

  public init(rev: String, convoId: String) {
    self.rev = rev
    self.convoId = convoId
  }
}

/// A closed projection over the `chat.bsky.convo.getLog` event union.
///
/// The wire union is open (`$type`-discriminated, with a 30-member ref list that
/// grows as the service adds group features). This enum draws the boundary the
/// 1:1 scope cares about: the event types the inbox and the conversation act on,
/// plus a ``groupEvent`` case for group/link/request events and an ``other``
/// case for anything unrecognized. Neither of those last two throws or renders;
/// ``LogSync`` advances the cursor past them and the data layer skips them.
///
/// Port of the `bsky.isType(...)` ladder in
/// `src/state/queries/messages/list-conversations.tsx` and
/// `src/state/messages/convo/agent.ts`.
public enum ChatLogEvent: Sendable, Hashable {
  /// `logBeginConvo`: the viewer was added to a convo.
  case beginConvo(ChatRevEvent)
  /// `logAcceptConvo`: the viewer accepted a convo, moving it out of requests.
  case acceptConvo(ChatRevEvent)
  /// `logLeaveConvo`: the viewer left a convo.
  case leaveConvo(ChatRevEvent)
  /// `logMuteConvo`: the viewer muted a convo.
  case muteConvo(ChatRevEvent)
  /// `logUnmuteConvo`: the viewer unmuted a convo.
  case unmuteConvo(ChatRevEvent)
  /// `logReadConvo`: the viewer read the convo up to `message`.
  case readConvo(rev: String, convoId: String, message: ConvoMessage)
  /// `logReadMessage`: deprecated predecessor of `logReadConvo`. Same handling.
  case readMessage(rev: String, convoId: String, message: ConvoMessage)
  /// `logCreateMessage`: a user-originated message was created.
  case createMessage(
    rev: String, convoId: String, message: ConvoMessage,
    relatedProfiles: [Chat.Bsky.ActorDefs_ProfileViewBasic])
  /// `logDeleteMessage`: a user-originated message was deleted.
  case deleteMessage(rev: String, convoId: String, message: ConvoMessage)
  /// `logAddReaction`: a reaction was added (the message carries the new
  /// reaction list).
  case addReaction(
    rev: String, convoId: String, message: ConvoMessage,
    reaction: Chat.Bsky.ConvoDefs_ReactionView)
  /// `logRemoveReaction`: a reaction was removed.
  case removeReaction(
    rev: String, convoId: String, message: ConvoMessage,
    reaction: Chat.Bsky.ConvoDefs_ReactionView)
  /// A group / join-link / join-request event. Decoded, never applied.
  case groupEvent(type: String, rev: String, convoId: String)
  /// An event type this client does not recognize. Decoded, never applied.
  case other(type: String?, rev: String?, convoId: String?)

  /// The event's `rev`, when it carries one.
  public var rev: String? {
    switch self {
    case .beginConvo(let e): e.rev
    case .acceptConvo(let e): e.rev
    case .leaveConvo(let e): e.rev
    case .muteConvo(let e): e.rev
    case .unmuteConvo(let e): e.rev
    case .readConvo(let rev, _, _): rev
    case .readMessage(let rev, _, _): rev
    case .createMessage(let rev, _, _, _): rev
    case .deleteMessage(let rev, _, _): rev
    case .addReaction(let rev, _, _, _): rev
    case .removeReaction(let rev, _, _, _): rev
    case .groupEvent(_, let rev, _): rev
    case .other(_, let rev, _): rev
    }
  }

  /// The event's `convoId`, when it carries one.
  public var convoId: String? {
    switch self {
    case .beginConvo(let e): e.convoId
    case .acceptConvo(let e): e.convoId
    case .leaveConvo(let e): e.convoId
    case .muteConvo(let e): e.convoId
    case .unmuteConvo(let e): e.convoId
    case .readConvo(_, let convoId, _): convoId
    case .readMessage(_, let convoId, _): convoId
    case .createMessage(_, let convoId, _, _): convoId
    case .deleteMessage(_, let convoId, _): convoId
    case .addReaction(_, let convoId, _, _): convoId
    case .removeReaction(_, let convoId, _, _): convoId
    case .groupEvent(_, _, let convoId): convoId
    case .other(_, _, let convoId): convoId
    }
  }

  /// True for the two tolerant cases, which the data layer skips.
  public var isTolerated: Bool {
    switch self {
    case .groupEvent, .other: true
    default: false
    }
  }

  /// Projects one wire log entry. Never throws: unknown `$type`s and unknown
  /// *payload* variants both land on the tolerant cases.
  public init(_ element: Chat.Bsky.ConvoGetLog_Output_Logs_Elem) {
    switch element {
    case .convoDefsLogBeginConvo(let e):
      self = .beginConvo(ChatRevEvent(rev: e.rev, convoId: e.convoId))
    case .convoDefsLogAcceptConvo(let e):
      self = .acceptConvo(ChatRevEvent(rev: e.rev, convoId: e.convoId))
    case .convoDefsLogLeaveConvo(let e):
      self = .leaveConvo(ChatRevEvent(rev: e.rev, convoId: e.convoId))
    case .convoDefsLogMuteConvo(let e):
      self = .muteConvo(ChatRevEvent(rev: e.rev, convoId: e.convoId))
    case .convoDefsLogUnmuteConvo(let e):
      self = .unmuteConvo(ChatRevEvent(rev: e.rev, convoId: e.convoId))
    case .convoDefsLogReadConvo(let e):
      self = .readConvo(
        rev: e.rev, convoId: e.convoId, message: ConvoMessage(e.message))
    case .convoDefsLogReadMessage(let e):
      self = .readMessage(
        rev: e.rev, convoId: e.convoId, message: ConvoMessage(e.message))
    case .convoDefsLogCreateMessage(let e):
      self = .createMessage(
        rev: e.rev, convoId: e.convoId, message: ConvoMessage(e.message),
        relatedProfiles: e.relatedProfiles ?? [])
    case .convoDefsLogDeleteMessage(let e):
      self = .deleteMessage(
        rev: e.rev, convoId: e.convoId, message: ConvoMessage(e.message))
    case .convoDefsLogAddReaction(let e):
      self = .addReaction(
        rev: e.rev, convoId: e.convoId, message: ConvoMessage(e.message),
        reaction: e.reaction)
    case .convoDefsLogRemoveReaction(let e):
      self = .removeReaction(
        rev: e.rev, convoId: e.convoId, message: ConvoMessage(e.message),
        reaction: e.reaction)
    default:
      // Every remaining arm is a group / join-link / join-request event, mapped
      // by the helpers below. They all carry the same `rev` + `convoId` shape
      // and none is applied by the 1:1 scope.
      self = Self.tolerant(element)
    }
  }

  /// Dispatches a group / join-link / join-request arm, or an unknown `$type`.
  ///
  /// Split across two switch helpers because the union has 19 such arms: one
  /// function would exceed the repo's cyclomatic-complexity and body-length
  /// budgets for no readability gain.
  private static func tolerant(
    _ element: Chat.Bsky.ConvoGetLog_Output_Logs_Elem
  ) -> ChatLogEvent {
    if let event = membershipEvent(element) { return event }
    if let event = linkAndRequestEvent(element) { return event }
    if case ._other(let record) = element {
      return .other(type: record.type, rev: nil, convoId: nil)
    }
    return .other(type: nil, rev: nil, convoId: nil)
  }

  /// The membership- and lock-shaped group arms.
  private static func membershipEvent(
    _ element: Chat.Bsky.ConvoGetLog_Output_Logs_Elem
  ) -> ChatLogEvent? {
    switch element {
    case .convoDefsLogAddMember(let e):
      return .groupEvent(type: groupType(.addMember), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogRemoveMember(let e):
      return .groupEvent(type: groupType(.removeMember), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogMemberJoin(let e):
      return .groupEvent(type: groupType(.memberJoin), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogMemberLeave(let e):
      return .groupEvent(type: groupType(.memberLeave), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogLockConvo(let e):
      return .groupEvent(type: groupType(.lockConvo), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogUnlockConvo(let e):
      return .groupEvent(type: groupType(.unlockConvo), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogLockConvoPermanently(let e):
      return .groupEvent(
        type: groupType(.lockConvoPermanently), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogEditGroup(let e):
      return .groupEvent(type: groupType(.editGroup), rev: e.rev, convoId: e.convoId)
    default:
      return nil
    }
  }

  /// The join-link and join-request group arms.
  private static func linkAndRequestEvent(
    _ element: Chat.Bsky.ConvoGetLog_Output_Logs_Elem
  ) -> ChatLogEvent? {
    switch element {
    case .convoDefsLogCreateJoinLink(let e):
      return .groupEvent(type: groupType(.createJoinLink), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogEditJoinLink(let e):
      return .groupEvent(type: groupType(.editJoinLink), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogEnableJoinLink(let e):
      return .groupEvent(type: groupType(.enableJoinLink), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogDisableJoinLink(let e):
      return .groupEvent(type: groupType(.disableJoinLink), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogIncomingJoinRequest(let e):
      return .groupEvent(
        type: groupType(.incomingJoinRequest), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogApproveJoinRequest(let e):
      return .groupEvent(
        type: groupType(.approveJoinRequest), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogRejectJoinRequest(let e):
      return .groupEvent(
        type: groupType(.rejectJoinRequest), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogOutgoingJoinRequest(let e):
      return .groupEvent(
        type: groupType(.outgoingJoinRequest), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogWithdrawIncomingJoinRequest(let e):
      return .groupEvent(
        type: groupType(.withdrawIncomingJoinRequest), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogWithdrawOutgoingJoinRequest(let e):
      return .groupEvent(
        type: groupType(.withdrawOutgoingJoinRequest), rev: e.rev, convoId: e.convoId)
    case .convoDefsLogReadJoinRequests(let e):
      return .groupEvent(
        type: groupType(.readJoinRequests), rev: e.rev, convoId: e.convoId)
    default:
      return nil
    }
  }

  /// The group/link/request event families, so their wire `$type` strings are
  /// spelled once.
  private enum GroupKind {
    case addMember, removeMember, memberJoin, memberLeave
    case lockConvo, unlockConvo, lockConvoPermanently, editGroup
    case createJoinLink, editJoinLink, enableJoinLink, disableJoinLink
    case incomingJoinRequest, approveJoinRequest, rejectJoinRequest
    case outgoingJoinRequest, withdrawIncomingJoinRequest, withdrawOutgoingJoinRequest
    case readJoinRequests

    /// The `chat.bsky.convo.defs#...` `$type` value.
    var rawValue: String {
      let name =
        switch self {
        case .addMember: "logAddMember"
        case .removeMember: "logRemoveMember"
        case .memberJoin: "logMemberJoin"
        case .memberLeave: "logMemberLeave"
        case .lockConvo: "logLockConvo"
        case .unlockConvo: "logUnlockConvo"
        case .lockConvoPermanently: "logLockConvoPermanently"
        case .editGroup: "logEditGroup"
        case .createJoinLink: "logCreateJoinLink"
        case .editJoinLink: "logEditJoinLink"
        case .enableJoinLink: "logEnableJoinLink"
        case .disableJoinLink: "logDisableJoinLink"
        case .incomingJoinRequest: "logIncomingJoinRequest"
        case .approveJoinRequest: "logApproveJoinRequest"
        case .rejectJoinRequest: "logRejectJoinRequest"
        case .outgoingJoinRequest: "logOutgoingJoinRequest"
        case .withdrawIncomingJoinRequest: "logWithdrawIncomingJoinRequest"
        case .withdrawOutgoingJoinRequest: "logWithdrawOutgoingJoinRequest"
        case .readJoinRequests: "logReadJoinRequests"
        }
      return "chat.bsky.convo.defs#\(name)"
    }
  }

  private static func groupType(_ kind: GroupKind) -> String { kind.rawValue }
}
