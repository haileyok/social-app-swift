import Foundation

/**
 The localization seam for the messages surfaces.

 Every user-facing string is read through this enum, matching `LoginCopy`: no
 view carries a scattered literal, so replacing the statics with
 `String(localized:)` and adding a String Catalog is a one-file change.

 The English here is the RN copy from `src/screens/Messages` (the inbox empty
 state, the composer placeholder, the failed-send copy) where an equivalent
 exists; where the RN app has no string (the fixture surfaces, the load-older
 row) the wording is native.
 */
public enum MessagesCopy {
  /// The inbox navigation title. RN: `Messages`.
  public static let inboxTitle = "Chat"
  /// The inbox empty state.
  public static let inboxEmptyTitle = "No conversations yet"
  public static let inboxEmptyMessage =
    "When someone sends you a message, it will show up here."
  /// The inbox error state.
  public static let inboxErrorTitle = "Could not load chats"
  public static let inboxErrorMessage =
    "Something went wrong. Check your connection and try again."
  /// The retry label shared by the inbox states.
  public static let retry = "Retry"

  /// The unread badge's accessibility label.
  public static func unreadAccessibilityLabel(_ count: Int) -> String {
    count == 1 ? "1 unread message" : "\(count) unread messages"
  }
  /// The muted indicator's accessibility label.
  public static let mutedAccessibilityLabel = "Muted"
  /// A row with no messages yet.
  public static let noMessagesYet = "No messages yet"

  /// The conversation navigation fallback (a convo with no resolved name).
  public static let conversationFallbackTitle = "Conversation"
  /// The composer placeholder. RN: `Message`.
  public static let composerPlaceholder = "Message"
  /// The send button's accessibility label.
  public static let sendAccessibilityLabel = "Send"
  /// The retry label shown when the outbox is stuck.
  public static let sendFailed = "Message not sent"
  /// The retry affordance's accessibility label.
  public static let retrySendAccessibilityLabel = "Retry sending"
  /// A message still on its way.
  public static let sendingAccessibilityLabel = "Sending"
  /// The read receipt line.
  public static let readReceipt = "Read"
  /// The date separator for today.
  public static let today = "Today"
  /// The date separator for yesterday.
  public static let yesterday = "Yesterday"

  /// The load-older affordance.
  public static let loadOlder = "Load earlier messages"
  /// The end-of-history marker.
  public static let beginningOfConversation = "This is the beginning of your conversation"
  /// The scroll-to-bottom control label.
  public static let scrollToBottom = "Scroll to newest"
  /// A message deleted by its sender.
  public static let deletedMessage = "Message deleted"
  /// The reaction affordance's accessibility label.
  public static let addReactionAccessibilityLabel = "Add reaction"
  /// The default quick reaction set offered by the affordance.
  public static let quickReactions = ["❤️", "👍", "😂", "😮", "😢"]

  /// The fixture surfaces' gallery title.
  public static let surfacesTitle = "Chat"
}
