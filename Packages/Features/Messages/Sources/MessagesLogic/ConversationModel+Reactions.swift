import Foundation
import Lexicons
import SwiftAtproto

/// Reaction and read/mute/delete mutations for ``ConversationModel``.
///
/// Split into an extension so the core actor file stays within a readable size.
/// The optimistic-then-reconcile-then-rollback shape is the port of
/// `addReaction` / `removeReaction` in `src/state/messages/convo/agent.ts`.
extension ConversationModel {
  // MARK: - Reactions

  /// Adds an emoji reaction, optimistically.
  ///
  /// Port of `addReaction`. The reaction must be exactly one grapheme, the
  /// sender may hold at most five distinct reactions on a message, and adding a
  /// duplicate is a no-op.
  ///
  /// - Throws: ``ConvoReactionError`` when the input is invalid or the server
  ///   rejects the call. The optimistic update is rolled back on failure.
  public func addReaction(messageId: String, emoji: String) async throws {
    guard MessagesReaction.isValid(emoji) else {
      throw ConvoReactionError.invalidEmoji(emoji)
    }

    let snapshot = reactionTarget(messageId)
    if let target = snapshot, target.messageView != nil {
      let mine = target.reactions.filter { $0.sender.did.rawValue == senderDid }
      if mine.contains(where: { $0.value == emoji }) {
        return
      }
      if mine.count >= MessagesConstants.maxReactionsPerSender {
        throw ConvoReactionError.tooManyReactions
      }
      writeMessage(
        id: messageId,
        with: appendReaction(
          target, value: emoji, senderDid: senderDid, at: now()))
    }

    do {
      let updated = try await client.addReaction(
        convoId: convoId, messageId: messageId, value: emoji)
      writeMessage(id: messageId, with: .message(updated))
    } catch {
      if let snapshot { writeMessage(id: messageId, with: snapshot) }
      throw error
    }
  }

  /// Removes an emoji reaction, optimistically.
  ///
  /// Port of `removeReaction`. The optimistic update is rolled back on failure.
  public func removeReaction(messageId: String, emoji: String) async throws {
    let snapshot = reactionTarget(messageId)
    if let target = snapshot, target.messageView != nil {
      writeMessage(
        id: messageId,
        with: removeReaction(target, value: emoji, senderDid: senderDid))
    }

    do {
      let updated = try await client.removeReaction(
        convoId: convoId, messageId: messageId, value: emoji)
      writeMessage(id: messageId, with: .message(updated))
    } catch {
      if let snapshot { writeMessage(id: messageId, with: snapshot) }
      throw error
    }
  }

  /// The current view of a message that can carry reactions.
  func reactionTarget(_ messageId: String) -> ConvoMessage? {
    if let past = pastMessages[messageId] { return past }
    return newMessages[messageId]
  }

  /// Writes a message view back into whichever collection holds it.
  func writeMessage(id: String, with message: ConvoMessage) {
    if pastMessages[id] != nil {
      pastMessages[id] = message
    } else if newMessages[id] != nil {
      newMessages[id] = message
    }
  }

  func appendReaction(
    _ message: ConvoMessage, value: String, senderDid: String, at date: Date
  ) -> ConvoMessage {
    guard case .message(let view) = message else { return message }
    var copy = view
    let reaction = Chat.Bsky.ConvoDefs_ReactionView(
      createdAt: FormatString<Date>(
        rawValue: MessagesDate.datetimeString(date)),
      sender: Chat.Bsky.ConvoDefs_ReactionViewSender(
        did: FormatString<SwiftAtproto.DID>(rawValue: senderDid)),
      value: value)
    copy.reactions = (view.reactions ?? []) + [reaction]
    return .message(copy)
  }

  func removeReaction(
    _ message: ConvoMessage, value: String, senderDid: String
  ) -> ConvoMessage {
    guard case .message(let view) = message else { return message }
    var copy = view
    copy.reactions = (view.reactions ?? []).filter {
      !($0.value == value && $0.sender.did.rawValue == senderDid)
    }
    return .message(copy)
  }
}
