import Foundation

import Lexicons
import NotificationsLogic

/**
 The copy and the two derivations the notifications list needs on top of
 ``NotificationsLogic``.

 The logic package owns the row model (which reason a notification is, which
 rows group together, whether a row is read). This type owns what the RN
 `NotificationFeedItem` renders for each reason - the sentence, the author line,
 the pluralised "and N others" - so the SwiftUI rows stay pure draws and the
 strings have one home.
 */
public enum NotificationsCopy {
  /// How many distinct authors a grouped row shows before it condenses, the RN
  /// `MAX_AUTHORS`.
  public static let maxAuthors = 5

  /// The fallback author label when a notification carries no display name.
  public static func authorName(handle: String) -> String {
    NotificationStrings.authorName(handle: handle)
  }

  /// The sentence fragment a reason contributes, e.g. `liked your post`.
  ///
  /// A faithful port of the branch table in
  /// `~/bluesky/social-app/src/view/com/notifications/NotificationFeedItem.tsx`.
  /// The RN app normalises `like-via-repost` to `post-like` for the *lead* case
  /// (see `src/state/queries/notifications/util.ts`) but keeps the distinct
  /// wording for these additive cases; the port keeps that wording too.
  public static func verb(for type: NotificationType) -> String? {
    switch type {
    case .postLike, .feedgenLike, .likeViaRepost:
      // `feedgenLike` is split from `postLike` on the subject URI by the logic
      // package; its sentence names the feed, so it is handled below.
      "liked your post"
    case .repost, .repostViaRepost:
      "reposted your post"
    case .follow:
      "followed you"
    case .contactMatch:
      "is on Bluesky"
    case .starterpackJoined:
      "signed up with your Starter Pack"
    case .verified:
      "verified you"
    case .unverified:
      "removed their verification from your account"
    case .subscribedPost:
      "posted"
    case .mention, .reply, .quote:
      // These render the subject post itself rather than a sentence.
      nil
    case .unknown:
      // The RN item returns null for a reason it does not render; the list
      // skips such rows rather than showing an untranslated sentence.
      nil
    }
  }

  /// The longer sentence for the reasons whose wording is not
  /// `<author>` + `verb`.
  static func sentence(for type: NotificationType, postCount: Int) -> String? {
    switch type {
    case .feedgenLike:
      "liked your custom feed"
    case .subscribedPost:
      // RN: "New post from X" / "New 3 posts from X". The `N posts` half is
      // built by the caller, which has the author link.
      postCount == 1 ? "posted a new post" : "posted \(postCount) new posts"
    default:
      nil
    }
  }

  /**
   True when a row renders as a sentence row rather than as a post subject.

   Reply, mention and quote draw the subject ``UIComponents/PostFeedItem``; the
   other reasons draw an icon and a sentence.
   */
  public static func rendersAsSentence(_ type: NotificationType) -> Bool {
    switch type {
    case .reply, .mention, .quote, .unknown: false
    default: true
    }
  }

  /// The index of the tab in the RN pager, for UI-test addressing.
  public static let unreadBadgeCap = 30
}

/**
 The distinct authors of a grouped row, in the order the RN item builds them:
 the row's own author first, then each additional notification's author, keeping
 the first occurrence of a DID and stopping at ``NotificationsCopy/maxAuthors``.
 */
public struct NotificationRowAuthors: Sendable, Equatable {
  /// The authors, deduplicated by DID and capped.
  public let all: [App.Bsky.ActorDefs_ProfileView]

  /// The author of the row's newest notification.
  public var first: App.Bsky.ActorDefs_ProfileView { all[0] }

  /// The number of authors beyond the first, which drives the `and N others`
  /// branch.
  public var additionalCount: Int { max(0, all.count - 1) }

  /// True when the row is grouped.
  public var isGrouped: Bool { additionalCount > 0 }

  /// Builds the author list for a row.
  public init(row: FeedNotification) {
    var seen = Set<String>()
    var authors: [App.Bsky.ActorDefs_ProfileView] = []
    for notification in [row.notification] + row.additional {
      let author = notification.author
      guard seen.insert(author.did.rawValue).inserted else { continue }
      authors.append(author)
      if authors.count == NotificationsCopy.maxAuthors { break }
    }
    // A notification always carries an author, so the list is never empty.
    self.all = authors.isEmpty ? [row.notification.author] : authors
  }
}

extension FeedNotification {
  /**
   The sentence the row draws next to its icon.

   `<display name> liked your post`, or `<display name> and 3 others liked your
   post` for a grouped row. Replies, mentions and quotes have no sentence: they
   draw the subject post instead.
   */
  public func sentence() -> String {
    let authors = NotificationRowAuthors(row: self)
    let name = NotificationsCopy.displayName(authors.first)
    guard authors.isGrouped else {
      return "\(name) \(NotificationsCopy.verb(for: type) ?? "")"
        .trimmingCharacters(in: .whitespaces)
    }
    let others = NotificationStrings.othersCount(authors.additionalCount)
    switch type {
    case .feedgenLike:
      return "\(name) \(others) liked your custom feed"
    case .subscribedPost:
      return "New posts from \(name) \(others)"
    default:
      return "\(name) \(others) \(NotificationsCopy.verb(for: type) ?? "")"
        .trimmingCharacters(in: .whitespaces)
    }
  }

  /**
   The row's accessibility label: the sentence, the count of grouped
   notifications where relevant, and the relative timestamp.

   Mirrors the RN item, which appends ` · <timestamp>` to every label.
   */
  public func accessibilitySentence(relativeTime: String) -> String {
    let authors = NotificationRowAuthors(row: self)
    let name = NotificationsCopy.displayName(authors.first)
    let base: String
    switch type {
    case .subscribedPost:
      let postCount = 1 + additional.count
      base = authors.isGrouped
        ? "New posts from \(name) and \(NotificationStrings.othersCount(authors.additionalCount))"
        : "New \(postCount == 1 ? "post" : "\(postCount) posts") from \(name)"
    case .unknown:
      base = "New notification"
    default:
      base = sentence()
    }
    return relativeTime.isEmpty ? base : "\(base) · \(relativeTime)"
  }

  /// The adjectival clause for an unverified row, which is longer than the verb.
  public var isReplyShaped: Bool {
    type == .reply || type == .mention || type == .quote
  }
}

extension NotificationsCopy {
  /// The author's display name, sanitised, falling back to `@handle`.
  ///
  /// Ported from `sanitizeDisplayName` in the RN
  /// `src/lib/strings/display-names.ts`: check marks, control characters and
  /// runs of whitespace are stripped, because display names are user input and
  /// the ones that break layouts are the ones carrying them.
  public static func displayName(_ author: App.Bsky.ActorDefs_ProfileView) -> String {
    let raw = author.displayName ?? ""
    let name = sanitize(raw)
    return name.isEmpty ? authorName(handle: author.handle.rawValue) : name
  }

  /// Strips the characters that break a single-line label.
  static func sanitize(_ value: String) -> String {
    let stripped = value.unicodeScalars.filter { scalar in
      switch scalar.value {
      // Check marks and the variation selector that follows an emoji.
      case 0x2705, 0x2713, 0x2714, 0x2611, 0xFE0F: false
      // C0/C1 control characters.
      case 0x00...0x1F, 0x7F...0x9F: false
      default: true
      }
    }
    return String(String.UnicodeScalarView(stripped))
      .split(separator: " ", omittingEmptySubsequences: true)
      .joined(separator: " ")
  }
}
