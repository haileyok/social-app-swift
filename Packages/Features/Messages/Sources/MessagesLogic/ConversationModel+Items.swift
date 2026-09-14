import Foundation
import Lexicons

/// Item assembly for ``ConversationModel``: the port of `getItems`.
extension ConversationModel {
  func buildItems() -> [ConvoItem] {
    var items: [ConvoItem] = []

    for id in pastOrder {
      guard let message = pastMessages[id] else { continue }
      items.append(item(for: message, fromHistory: true))
    }

    if historyFailed {
      items.append(.error(code: .historyFailed))
    }

    for id in newOrder {
      guard let message = newMessages[id] else { continue }
      items.append(item(for: message, fromHistory: false))
    }

    for pending in pendingMessages {
      items.append(
        .pendingMessage(
          PendingMessage(
            id: pending.id, message: pending.message,
            failed: pendingFailure != nil)))
    }

    if pendingFailure != nil {
      items.append(.error(code: .firehoseFailed))
    }

    return items.filter { item in
      guard let id = item.messageId else { return true }
      return !deletedMessages.contains(id)
    }
  }

  func item(for message: ConvoMessage, fromHistory: Bool) -> ConvoItem {
    switch message {
    case .message(let view):
      // A message that quotes the deleted one keeps rendering a tombstone.
      let isReplyToDeleted =
        if case .convoDefsMessageView(let replyTo) = view.replyTo {
          deletedMessages.contains(replyTo.id)
        } else {
          false
        }
      if isReplyToDeleted, case .convoDefsMessageView(let replyTo) = view.replyTo {
        var copy = view
        copy.replyTo = .convoDefsDeletedMessageView(ConvoMessage.tombstone(replyTo))
        return .message(copy)
      }
      return .message(view)
    case .deleted(let view): return .deletedMessage(view)
    case .system(let view): return .systemMessage(view)
    case .other: return .error(code: fromHistory ? .historyFailed : .firehoseFailed)
    }
  }
}
