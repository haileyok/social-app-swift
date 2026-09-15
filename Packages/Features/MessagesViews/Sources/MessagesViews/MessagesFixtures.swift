import Foundation
import Lexicons
import MessagesLogic
import SwiftAtproto

/// The fixture surfaces' scripted conversation.
///
/// This is the "surfaces" scope from the task: a scripted 1:1 conversation that
/// exercises every message treatment the UI renders - mine vs theirs, a date
/// separator boundary, reactions, an optimistic pending echo, and a failed send
/// with retry - without a session or a network. The values are built the way the
/// real wire values are (lexicon types, `FormatString` timestamps, a `MessageInput`
/// for the outbox), so the fixture path and the live path render through the
/// exact same views.
///
/// The fixtures deliberately live in the Views package rather than MessagesLogic:
/// the logic package's fixtures are `@testable` and not a product, and a preview
/// surface must render without a test target.
public enum MessagesFixtures {
  /// The signed-in account in the fixture conversation.
  public static let selfDid = "did:plc:fixture-self"
  /// The other member of the fixture conversation.
  public static let partnerDid = "did:plc:fixture-partner"
  /// The fixture conversation id.
  public static let convoId = "convo-fixture-1"

  /// Deterministic timestamps, anchored to a fixed day so the date separators
  /// are stable across runs and previews. Internal (not private) because they are
  /// referenced from this type's public functions' default arguments.
  static let day = "2026-08-30"
  static let nextDay = "2026-08-31"

  private static func did(_ value: String) -> FormatString<SwiftAtproto.DID> {
    FormatString<SwiftAtproto.DID>(rawValue: value)
  }

  private static func ts(_ value: String) -> FormatString<Date> {
    FormatString<Date>(rawValue: value)
  }

  /// The fixture profiles.
  public static func partnerProfile() -> Chat.Bsky.ActorDefs_ProfileViewBasic {
    Chat.Bsky.ActorDefs_ProfileViewBasic(
      did: did(partnerDid),
      displayName: "Robin Fixture",
      handle: FormatString<SwiftAtproto.Handle>(rawValue: "robin.fixture.test"))
  }

  /// The signed-in account's profile.
  public static func selfProfile() -> Chat.Bsky.ActorDefs_ProfileViewBasic {
    Chat.Bsky.ActorDefs_ProfileViewBasic(
      did: did(selfDid),
      displayName: "You",
      handle: FormatString<SwiftAtproto.Handle>(rawValue: "you.fixture.test"))
  }

  /// The fixture conversation view.
  public static func convo(
    unreadCount: Int = 2, muted: Bool = false
  ) -> Chat.Bsky.ConvoDefs_ConvoView {
    var view = Chat.Bsky.ConvoDefs_ConvoView(
      id: convoId,
      members: [partnerProfile(), selfProfile()],
      muted: muted,
      rev: "10",
      status: .accepted,
      unreadCount: unreadCount)
    view.kind = .convoDefsDirectConvo(.init())
    view.lastMessage = .convoDefsMessageView(theirs(id: "m4", text: "See you there!"))
    return view
  }

  /// A second fixture convo, for the inbox list.
  public static func secondConvo() -> Chat.Bsky.ConvoDefs_ConvoView {
    var view = Chat.Bsky.ConvoDefs_ConvoView(
      id: "convo-fixture-2",
      members: [
        Chat.Bsky.ActorDefs_ProfileViewBasic(
          did: did("did:plc:fixture-third"),
          displayName: "Sam Fixture",
          handle: FormatString<SwiftAtproto.Handle>(rawValue: "sam.fixture.test")),
        selfProfile(),
      ],
      muted: true,
      rev: "8",
      status: .accepted,
      unreadCount: 0)
    view.kind = .convoDefsDirectConvo(.init())
    view.lastMessage = .convoDefsMessageView(
      mine(id: "m2b", text: "Talk soon"))
    return view
  }

  /// A message from the partner.
  public static func theirs(
    id: String, text: String, at stamp: String = "\(day)T09:00:00.000Z",
    reactions: [Chat.Bsky.ConvoDefs_ReactionView]? = nil
  ) -> Chat.Bsky.ConvoDefs_MessageView {
    Chat.Bsky.ConvoDefs_MessageView(
      id: id,
      reactions: reactions,
      rev: id,
      sender: Chat.Bsky.ConvoDefs_MessageViewSender(did: did(partnerDid)),
      sentAt: ts(stamp),
      text: text)
  }

  /// A message from the signed-in account.
  public static func mine(
    id: String, text: String, at stamp: String = "\(day)T09:05:00.000Z",
    reactions: [Chat.Bsky.ConvoDefs_ReactionView]? = nil
  ) -> Chat.Bsky.ConvoDefs_MessageView {
    Chat.Bsky.ConvoDefs_MessageView(
      id: id,
      reactions: reactions,
      rev: id,
      sender: Chat.Bsky.ConvoDefs_MessageViewSender(did: did(selfDid)),
      sentAt: ts(stamp),
      text: text)
  }

  /// A reaction view.
  public static func reaction(
    _ value: String, from senderDid: String = selfDid
  ) -> Chat.Bsky.ConvoDefs_ReactionView {
    Chat.Bsky.ConvoDefs_ReactionView(
      createdAt: ts("\(day)T09:06:00.000Z"),
      sender: Chat.Bsky.ConvoDefs_ReactionViewSender(did: did(senderDid)),
      value: value)
  }

  /// The scripted history, oldest first: a two-day conversation with a reaction
  /// on the first message and a day boundary between the two groups.
  public static func history() -> [ConvoMessage] {
    [
      .message(theirs(id: "m1", text: "Hey! Are we still on for tomorrow?", at: "\(day)T09:00:00.000Z")),
      .message(
        mine(
          id: "m2", text: "Yes - 10am at the usual place",
          at: "\(day)T09:05:00.000Z",
          reactions: [reaction("👍", from: partnerDid)])),
      .message(theirs(id: "m3", text: "Perfect, I'll bring the tickets", at: "\(nextDay)T08:30:00.000Z")),
      .message(mine(id: "m4", text: "See you there!", at: "\(nextDay)T08:45:00.000Z")),
    ]
  }

  /// The outbox the fixture seeds: one pending echo (reconciled by the script)
  /// and one entry that stays failed so the retry affordance renders.
  public static func pendingInput(text: String) -> Chat.Bsky.ConvoDefs_MessageInput {
    Chat.Bsky.ConvoDefs_MessageInput(text: text)
  }

  /// The failed-send entry's text.
  public static let failedText = "Did you get the tickets?"

  /// A batch of log events that would drive the conversation live, for a caller
  /// wiring the fixture to the log path.
  public static func createEvent(
    rev: String, message: ConvoMessage, convoId id: String = convoId
  ) -> ChatLogEvent {
    .createMessage(rev: rev, convoId: id, message: message, relatedProfiles: [])
  }
}
