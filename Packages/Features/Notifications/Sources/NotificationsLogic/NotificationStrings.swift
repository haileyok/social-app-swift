import Foundation

public enum NotificationStrings {
  /// The badge label when thirty or more notifications are unread.
  ///
  /// Matches the RN broadcast value `'30+'`.
  public static let badgeMany = "30+"

  /// Fallback subject text for a notification whose subject could not be
  /// resolved, e.g. a deleted post.
  public static let missingSubject = "This post is unavailable"

  /// Fallback author text when the notification carries no display name.
  public static func authorName(handle: String) -> String { "@\(handle)" }

  /// A group of notifications beyond the first, e.g. "and 3 others".
  ///
  /// The RN layer groups like this in `NotificationFeedItem`; the count is
  /// exposed here so the view package does not have to re-derive it.
  public static func othersCount(_ count: Int) -> String {
    count == 1 ? "and 1 other" : "and \(count) others"
  }
}
