import Foundation

/**
 Accessibility identifiers for the messages surfaces.

 Mirrors `LoginAccessibility`: the identifiers live in one enum so the app, its
 previews and a future XCUITest read the same literals instead of duplicating
 them. The RNW testID parity (e.g. `convoListItem-<id>`) is kept where the RN
 app has one.
 */
public enum MessagesAccessibility {
  /// The inbox list.
  public static let inbox = "messages.inbox"

  /// One conversation row, e.g. `messages.inbox.row.convo-1`.
  public static func inboxRow(_ convoId: String) -> String {
    "messages.inbox.row.\(convoId)"
  }

  /// The inbox empty state.
  public static let inboxEmpty = "messages.inbox.empty"

  /// The conversation screen.
  public static let conversation = "messages.conversation"

  /// The conversation's back/close control.
  public static let conversationBack = "messages.conversation.back"

  /// The send bar's text field.
  public static let composerField = "messages.composer.field"

  /// The send bar's send button.
  public static let composerSend = "messages.composer.send"

  /// The failed-send retry affordance.
  public static let composerRetry = "messages.composer.retry"

  /// One message bubble, e.g. `messages.bubble.<messageId>`.
  public static func bubble(_ messageId: String) -> String {
    "messages.bubble.\(messageId)"
  }

  /// One reaction chip, e.g. `messages.reaction.<messageId>.<emoji>`.
  public static func reaction(_ messageId: String, emoji: String) -> String {
    "messages.reaction.\(messageId).\(emoji)"
  }

  /// The reaction affordance on one message.
  public static func reactionButton(_ messageId: String) -> String {
    "messages.reaction.add.\(messageId)"
  }

  /// The "load older messages" control.
  public static let loadOlder = "messages.loadOlder"

  /// The scroll-to-bottom control.
  public static let scrollToBottom = "messages.scrollToBottom"
}
