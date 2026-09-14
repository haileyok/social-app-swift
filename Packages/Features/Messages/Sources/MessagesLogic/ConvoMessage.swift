import Foundation
import Lexicons
import SwiftAtproto

/// A message in a conversation, projected from the wire message union.
///
/// The union (`messageView` / `deletedMessageView` / `systemMessageView`) is
/// carried as generated lexicon values so facets, embeds, reactions and system
/// data survive intact, with an ``other`` case for a message type this client
/// does not know about. Decoding never throws on an unknown type: the generated
/// union's `_other` arm maps here, and the data layer skips it.
///
/// Port of the `MessageView | DeletedMessageView | SystemMessageView` union the
/// RN `Convo` agent holds in `pastMessages` / `newMessages`.
public enum ConvoMessage: Sendable, Hashable {
  /// A user-originated message.
  case message(Chat.Bsky.ConvoDefs_MessageView)
  /// A tombstone for a deleted message.
  case deleted(Chat.Bsky.ConvoDefs_DeletedMessageView)
  /// A system message (member changes, group metadata events).
  case system(Chat.Bsky.ConvoDefs_SystemMessageView)
  /// A message type this client does not recognize. Tolerated, never rendered.
  case other(id: String?)

  /// The message identity, used as the list key and for reconciliation.
  public var id: String? {
    switch self {
    case .message(let view): view.id
    case .deleted(let view): view.id
    case .system(let view): view.id
    case .other(let id): id
    }
  }

  /// The sender's DID, when the message carries a sender.
  public var senderDid: String? {
    switch self {
    case .message(let view): view.sender.did.rawValue
    case .deleted(let view): view.sender.did.rawValue
    case .system: nil
    case .other: nil
    }
  }

  /// The text, for user-originated messages.
  public var text: String? {
    switch self {
    case .message(let view): view.text
    case .deleted, .system, .other: nil
    }
  }

  /// The reactions on this message, ascending by creation time.
  public var reactions: [Chat.Bsky.ConvoDefs_ReactionView] {
    switch self {
    case .message(let view): view.reactions ?? []
    case .deleted, .system, .other: []
    }
  }

  /// The full message view, when this is a user-originated message.
  public var messageView: Chat.Bsky.ConvoDefs_MessageView? {
    if case .message(let view) = self { return view }
    return nil
  }

  /// True for a deleted-message tombstone.
  public var isDeleted: Bool {
    if case .deleted = self { return true }
    return false
  }

  /// True for a system message.
  public var isSystem: Bool {
    if case .system = self { return true }
    return false
  }

  /// True when the type is unrecognized and the data layer should skip it.
  public var isUnknown: Bool {
    if case .other = self { return true }
    return false
  }

  /// Projects a `getMessages` wire union member into the model. Unknown members
  /// become ``other`` rather than throwing.
  public init(_ element: Chat.Bsky.ConvoGetMessages_Output_Messages_Elem) {
    switch element {
    case .convoDefsMessageView(let view): self = .message(view)
    case .convoDefsDeletedMessageView(let view): self = .deleted(view)
    case .convoDefsSystemMessageView(let view): self = .system(view)
    case ._other: self = .other(id: nil)
    }
  }

  /// Projects a message-bearing log union (`logCreateMessage`,
  /// `logDeleteMessage`, `logAddReaction`, `logRemoveReaction`). Unknown members
  /// become ``other``.
  public init(_ element: Chat.Bsky.ConvoDefs_LogCreateMessage_Message) {
    self = Self.project(element)
  }

  /// Projects a message-bearing log union (`logReadConvo`). Unknown members
  /// become ``other``.
  public init(_ element: Chat.Bsky.ConvoDefs_LogReadConvo_Message) {
    self = Self.project(element)
  }

  /// Projects a message-bearing log union (`logReadMessage`). Unknown members
  /// become ``other``.
  public init(_ element: Chat.Bsky.ConvoDefs_LogReadMessage_Message) {
    self = Self.project(element)
  }

  /// Projects a message-bearing log union (`logDeleteMessage`). Unknown members
  /// become ``other``.
  public init(_ element: Chat.Bsky.ConvoDefs_LogDeleteMessage_Message) {
    self = Self.project(element)
  }

  /// Projects a message-bearing log union (`logAddReaction`). Unknown members
  /// become ``other``.
  public init(_ element: Chat.Bsky.ConvoDefs_LogAddReaction_Message) {
    self = Self.project(element)
  }

  /// Projects a message-bearing log union (`logRemoveReaction`). Unknown
  /// members become ``other``.
  public init(_ element: Chat.Bsky.ConvoDefs_LogRemoveReaction_Message) {
    self = Self.project(element)
  }

  private static func project(_ element: Chat.Bsky.ConvoDefs_LogCreateMessage_Message) -> Self {
    switch element {
    case .convoDefsMessageView(let view): .message(view)
    case .convoDefsDeletedMessageView(let view): .deleted(view)
    case ._other: .other(id: nil)
    }
  }

  private static func project(_ element: Chat.Bsky.ConvoDefs_LogReadConvo_Message) -> Self {
    switch element {
    case .convoDefsMessageView(let view): .message(view)
    case .convoDefsDeletedMessageView(let view): .deleted(view)
    case .convoDefsSystemMessageView(let view): .system(view)
    case ._other: .other(id: nil)
    }
  }

  private static func project(_ element: Chat.Bsky.ConvoDefs_LogReadMessage_Message) -> Self {
    switch element {
    case .convoDefsMessageView(let view): .message(view)
    case .convoDefsDeletedMessageView(let view): .deleted(view)
    case .convoDefsSystemMessageView(let view): .system(view)
    case ._other: .other(id: nil)
    }
  }

  private static func project(_ element: Chat.Bsky.ConvoDefs_LogDeleteMessage_Message) -> Self {
    switch element {
    case .convoDefsMessageView(let view): .message(view)
    case .convoDefsDeletedMessageView(let view): .deleted(view)
    case ._other: .other(id: nil)
    }
  }

  private static func project(_ element: Chat.Bsky.ConvoDefs_LogAddReaction_Message) -> Self {
    switch element {
    case .convoDefsMessageView(let view): .message(view)
    case .convoDefsDeletedMessageView(let view): .deleted(view)
    case ._other: .other(id: nil)
    }
  }

  private static func project(_ element: Chat.Bsky.ConvoDefs_LogRemoveReaction_Message) -> Self {
    switch element {
    case .convoDefsMessageView(let view): .message(view)
    case .convoDefsDeletedMessageView(let view): .deleted(view)
    case ._other: .other(id: nil)
    }
  }

  /// Builds a `messageView` from parts. Used for the optimistic local echo,
  /// which needs the same shape the server returns minus a real id.
  public static func optimisticMessageView(
    id: String, rev: String, senderDid: String, sentAt: Date,
    text: String, facets: [App.Bsky.RichtextFacet]? = nil,
    replyTo: Chat.Bsky.ConvoDefs_MessageView_ReplyTo? = nil
  ) -> Chat.Bsky.ConvoDefs_MessageView {
    Chat.Bsky.ConvoDefs_MessageView(
      facets: facets,
      id: id,
      replyTo: replyTo,
      rev: rev,
      sender: Chat.Bsky.ConvoDefs_MessageViewSender(
        did: FormatString<SwiftAtproto.DID>(rawValue: senderDid)),
      sentAt: FormatString<Date>(rawValue: MessagesDate.datetimeString(sentAt)),
      text: text)
  }

  /// Derives a deleted-message tombstone from a message view, preserving the
  /// fields the deleted view carries so a reply can still render it as deleted.
  /// Port of `toDeletedMessageView`.
  public static func tombstone(
    _ view: Chat.Bsky.ConvoDefs_MessageView
  ) -> Chat.Bsky.ConvoDefs_DeletedMessageView {
    Chat.Bsky.ConvoDefs_DeletedMessageView(
      id: view.id, rev: view.rev, sender: view.sender, sentAt: view.sentAt)
  }
}
