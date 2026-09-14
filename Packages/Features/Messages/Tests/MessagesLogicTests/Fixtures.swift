import Foundation
import Lexicons
import SwiftAtproto

@testable import MessagesLogic

/// Fixture builders shared by the messages suites.
enum Fixtures {
  /// The signed-in account.
  static let selfDid = "did:plc:self"
  /// The other member of the 1:1 convo.
  static let otherDid = "did:plc:other"
  /// An ISO-8601 timestamp the lexicon `FormatString<Date>` accepts.
  static let defaultDate = "2026-08-31T00:00:00.000Z"

  static func did(_ value: String) -> FormatString<SwiftAtproto.DID> {
    FormatString<SwiftAtproto.DID>(rawValue: value)
  }

  static func profile(_ did: String) -> Chat.Bsky.ActorDefs_ProfileViewBasic {
    Chat.Bsky.ActorDefs_ProfileViewBasic(
      did: self.did(did),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: "\(did.suffix(5)).test"))
  }

  /// A convo view with the given id and members.
  static func convo(
    id: String = "convo-1", members: [String] = [selfDid, otherDid],
    status: ConvoStatusFilter = .accepted, unreadCount: Int = 0, muted: Bool = false,
    rev: String = "1", lastMessage: Chat.Bsky.ConvoDefs_MessageView? = nil,
    group: Bool = false
  ) -> Chat.Bsky.ConvoDefs_ConvoView {
    var view = Chat.Bsky.ConvoDefs_ConvoView(
      id: id,
      members: members.map(profile),
      muted: muted,
      rev: rev,
      status: status == .accepted
        ? Chat.Bsky.ConvoDefs_ConvoStatus.accepted
        : Chat.Bsky.ConvoDefs_ConvoStatus.request,
      unreadCount: unreadCount)
    view.kind =
      group
      ? .convoDefsGroupConvo(FakeChatServer.groupConvo())
      : .convoDefsDirectConvo(.init())
    if let lastMessage { view.lastMessage = .convoDefsMessageView(lastMessage) }
    return view
  }

  /// A message view.
  static func message(
    id: String, rev: String = "1", text: String = "hi", sender: String = otherDid,
    sentAt: String = defaultDate,
    reactions: [Chat.Bsky.ConvoDefs_ReactionView]? = nil
  ) -> Chat.Bsky.ConvoDefs_MessageView {
    Chat.Bsky.ConvoDefs_MessageView(
      id: id,
      reactions: reactions,
      rev: rev,
      sender: Chat.Bsky.ConvoDefs_MessageViewSender(did: did(sender)),
      sentAt: FormatString<Date>(rawValue: sentAt),
      text: text)
  }

  /// A reaction view.
  static func reaction(
    _ value: String, sender: String = selfDid
  ) -> Chat.Bsky.ConvoDefs_ReactionView {
    Chat.Bsky.ConvoDefs_ReactionView(
      createdAt: FormatString<Date>(rawValue: defaultDate),
      sender: Chat.Bsky.ConvoDefs_ReactionViewSender(did: did(sender)),
      value: value)
  }

  /// A deleted-message tombstone.
  static func deletedMessage(
    id: String, rev: String = "1", sender: String = otherDid
  ) -> Chat.Bsky.ConvoDefs_DeletedMessageView {
    Chat.Bsky.ConvoDefs_DeletedMessageView(
      id: id, rev: rev,
      sender: Chat.Bsky.ConvoDefs_MessageViewSender(did: did(sender)),
      sentAt: FormatString<Date>(rawValue: defaultDate))
  }

  /// A message input.
  static func input(_ text: String) -> Chat.Bsky.ConvoDefs_MessageInput {
    Chat.Bsky.ConvoDefs_MessageInput(text: text)
  }

  /// A log batch containing the given events, wrapped in a page.
  static func logPage(_ events: [ChatLogEvent], cursor: String? = nil) -> ChatLogPage {
    ChatLogPage(logs: events, cursor: cursor)
  }

  /// A `logCreateMessage` event.
  static func createEvent(
    rev: String, convoId: String = "convo-1", message: ConvoMessage
  ) -> ChatLogEvent {
    .createMessage(rev: rev, convoId: convoId, message: message, relatedProfiles: [])
  }

  /// A `logDeleteMessage` event.
  static func deleteEvent(
    rev: String, convoId: String = "convo-1", message: ConvoMessage
  ) -> ChatLogEvent {
    .deleteMessage(rev: rev, convoId: convoId, message: message)
  }
}
