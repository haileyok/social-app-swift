import Foundation

import Lexicons
import NotificationsLogic
import SwiftAtproto

/**
 Representative notifications for the fixture surface and for previews.

 Pure and non-throwing: it builds the same lexicon types the appview sends, so
 the fixture exercises the real row path rather than a parallel one. The set
 covers one row per rendered reason plus a grouped row, so the surface shows
 every glyph, both row shapes (sentence and subject post) and the unread
 treatment on first launch.
 */
public enum NotificationsFixtures {
  /// A stable "now" so the relative timestamps in previews and screenshots do
  /// not drift between runs.
  public static let referenceDate = Date(timeIntervalSince1970: 1_760_000_000)

  /// The fixture rows, newest first.
  public static var rows: [FeedNotification] { rows(now: referenceDate) }

  /// The default fixture: one row per reason the list renders.
  public static func rows(now: Date = referenceDate) -> [FeedNotification] {
    [
      // A single like: sentence row, heart glyph, unread.
      sentence(
        reason: .like,
        author: profile(handle: "alice.bsky.social", displayName: "Alice", did: "did:plc:alice"),
        subject: post("The sunset over the bay tonight was unreal.", author: me),
        isRead: false,
        indexedAt: isoString(now, minutesAgo: 4)),

      // A grouped like: three authors, the "and 2 others" branch.
      groupedLike(now: now),

      // A repost of my post: green repost glyph plus a subject preview.
      sentence(
        reason: .repost,
        author: profile(handle: "carol.bsky.social", displayName: "Carol", did: "did:plc:carol"),
        subject: post("Shipped the notifications rewrite today.", author: me),
        isRead: true,
        indexedAt: isoString(now, minutesAgo: 42)),

      // A follow: person glyph, no subject.
      sentence(
        reason: .follow,
        author: profile(handle: "dave.bsky.social", displayName: "Dave", did: "did:plc:dave"),
        record: followRecord(now: now),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 2)),

      // A reply: subject-post row.
      postRow(
        reason: .reply,
        author: profile(handle: "erin.bsky.social", displayName: "Erin", did: "did:plc:erin"),
        subject: post("Do you have a link to the write-up?", author: erin),
        isRead: false,
        indexedAt: isoString(now, hoursAgo: 3)),

      // A mention: subject-post row.
      postRow(
        reason: .mention,
        author: profile(handle: "frank.bsky.social", displayName: "Frank", did: "did:plc:frank"),
        subject: post("@me this is exactly the bug I hit last week.", author: frank),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 5)),

      // A quote: subject-post row.
      postRow(
        reason: .quote,
        author: profile(handle: "grace.bsky.social", displayName: "Grace", did: "did:plc:grace"),
        subject: post("Quoting this because it deserves more reach.", author: grace),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 7)),

      // A custom-feed like: distinct wording, recognised through reasonSubject.
      sentence(
        reason: .like,
        author: profile(handle: "heidi.bsky.social", displayName: "Heidi", did: "did:plc:heidi"),
        reasonSubject: "at://did:plc:me/app.bsky.feed.generator/for-you",
        record: likeRecord(now: now),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 9)),

      // A like via repost: "liked your repost".
      sentence(
        reason: .likeViaRepost,
        author: profile(handle: "ivan.bsky.social", displayName: "Ivan", did: "did:plc:ivan"),
        subject: post("Shipped the notifications rewrite today.", author: me),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 11)),

      // A repost via repost: "reposted your repost".
      sentence(
        reason: .repostViaRepost,
        author: profile(handle: "judy.bsky.social", displayName: "Judy", did: "did:plc:judy"),
        subject: post("Shipped the notifications rewrite today.", author: me),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 13)),

      // A starter-pack signup: stack glyph.
      sentence(
        reason: .starterpackJoined,
        author: profile(handle: "mallory.bsky.social", displayName: "Mallory", did: "did:plc:mallory"),
        starterPack: starterPack(name: "Design Tools"),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 16)),

      // A contact match: the contacts glyph.
      sentence(
        reason: .contactMatch,
        author: profile(handle: "niaj.bsky.social", displayName: "Niaj", did: "did:plc:niaj"),
        record: followRecord(now: now),
        isRead: true,
        indexedAt: isoString(now, hoursAgo: 20)),

      // A verification: checkmark seal.
      sentence(
        reason: .verified,
        author: profile(handle: "olivia.bsky.social", displayName: "Olivia", did: "did:plc:olivia"),
        record: followRecord(now: now),
        isRead: true,
        indexedAt: isoString(now, daysAgo: 2)),

      // A removed verification: untinted seal.
      sentence(
        reason: .unverified,
        author: profile(handle: "peggy.bsky.social", displayName: "Peggy", did: "did:plc:peggy"),
        record: followRecord(now: now),
        isRead: true,
        indexedAt: isoString(now, daysAgo: 3)),

      // A subscribed post: bell glyph and a subject preview.
      sentence(
        reason: .subscribedPost,
        author: profile(handle: "quinn.bsky.social", displayName: "Quinn", did: "did:plc:quinn"),
        subject: post("A new post from an account you subscribed to.", author: quinn),
        isRead: true,
        indexedAt: isoString(now, daysAgo: 4)),

      // A reason this build does not know how to render.
      sentence(
        reason: ._other("something-new"),
        author: profile(handle: "rupert.bsky.social", displayName: "Rupert", did: "did:plc:rupert"),
        record: followRecord(now: now),
        isRead: true,
        indexedAt: isoString(now, daysAgo: 5)),
    ]
  }

  /// An empty page list, for the empty-state preview and the "nothing here"
  /// screenshot.
  public static var emptyModel: NotificationsListModel {
    NotificationsListModel(rows: [], state: .empty)
  }

  /// The model the fixture surface renders.
  public static var model: NotificationsListModel {
    NotificationsListModel(rows: rows)
  }

  // MARK: - Row builders

  /// A sentence row: a like, a follow, a system notice.
  static func sentence(
    reason: App.Bsky.NotificationListNotifications_Notification_Reason,
    author: App.Bsky.ActorDefs_ProfileView,
    reasonSubject: String? = nil,
    subject: App.Bsky.FeedDefs_PostView? = nil,
    record: UnknownATPValue? = nil,
    isRead: Bool = true,
    indexedAt: String,
    starterPack: App.Bsky.GraphDefs_StarterPackViewBasic? = nil
  ) -> FeedNotification {
    let row = NotificationReasons.makeRow(
      notification(
        reason: reason,
        author: author,
        reasonSubject: reasonSubject ?? subject?.uri.rawValue,
        record: record ?? postRecord(text: "your post", author: me),
        isRead: isRead,
        indexedAt: indexedAt,
        starterPack: starterPack))
    guard let subject else { return row }
    return withSubject(row, .post(subject))
  }

  /// A reply/mention/quote row, whose subject is a post the row draws.
  static func postRow(
    reason: App.Bsky.NotificationListNotifications_Notification_Reason,
    author: App.Bsky.ActorDefs_ProfileView,
    subject: App.Bsky.FeedDefs_PostView,
    isRead: Bool = true,
    indexedAt: String
  ) -> FeedNotification {
    let row = NotificationReasons.makeRow(
      notification(
        reason: reason,
        author: author,
        reasonSubject: subject.uri.rawValue,
        record: postRecord(text: "a reply", author: author),
        isRead: isRead,
        indexedAt: indexedAt))
    return withSubject(row, .post(subject))
  }

  /// A grouped like: three distinct authors folded into one row.
  static func groupedLike(now: Date) -> FeedNotification {
    let subject = post("Shipped the notifications rewrite today.", author: me)
    let first = notification(
      reason: .like,
      author: profile(handle: "alice.bsky.social", displayName: "Alice", did: "did:plc:alice"),
      reasonSubject: subject.uri.rawValue,
      record: likeRecord(now: now),
      isRead: false,
      indexedAt: isoString(now, minutesAgo: 30))
    let second = notification(
      reason: .like,
      author: profile(handle: "carol.bsky.social", displayName: "Carol", did: "did:plc:carol"),
      reasonSubject: subject.uri.rawValue,
      record: likeRecord(now: now),
      isRead: false,
      indexedAt: isoString(now, minutesAgo: 31))
    let third = notification(
      reason: .like,
      author: profile(handle: "heidi.bsky.social", displayName: "Heidi", did: "did:plc:heidi"),
      reasonSubject: subject.uri.rawValue,
      record: likeRecord(now: now),
      isRead: false,
      indexedAt: isoString(now, minutesAgo: 32))
    /*
     `groupNotifications` folds later notifications into the earlier row's
     `additional`, which is the shape the "and N others" branch reads. Grouping
     two-by-two keeps the fold explicit rather than depending on the order the
     grouping pass happens to produce for three.
     */
    let folded = NotificationReasons.group([first, second, third])
    guard let row = folded.first else {
      return withSubject(
        NotificationReasons.makeRow(first), .post(subject))
    }
    return withSubject(row, .post(subject))
  }

  /// Attaches a resolved subject, which the real feed attaches after its
  /// `getPosts` pass.
  static func withSubject(
    _ row: FeedNotification,
    _ subject: ResolvedSubject
  ) -> FeedNotification {
    var copy = row
    copy.subject = subject
    if copy.subjectUri == nil { copy.subjectUri = subject.uri }
    return copy
  }

  // MARK: - Lexicon builders

  /// The signed-in account, whose posts the fixture notifications point at.
  static let meDid = "did:plc:me"

  static let me = profile(handle: "me.bsky.social", displayName: "You", did: meDid)
  static let alice = profile(handle: "alice.bsky.social", displayName: "Alice", did: "did:plc:alice")
  static let carol = profile(handle: "carol.bsky.social", displayName: "Carol", did: "did:plc:carol")
  static let dave = profile(handle: "dave.bsky.social", displayName: "Dave", did: "did:plc:dave")
  static let erin = profile(handle: "erin.bsky.social", displayName: "Erin", did: "did:plc:erin")
  static let frank = profile(handle: "frank.bsky.social", displayName: "Frank", did: "did:plc:frank")
  static let grace = profile(handle: "grace.bsky.social", displayName: "Grace", did: "did:plc:grace")
  static let quinn = profile(handle: "quinn.bsky.social", displayName: "Quinn", did: "did:plc:quinn")

  /// A profile view. The handle is derived from the DID when not given, so the
  /// fixture never has to repeat it.
  static func profile(
    handle: String,
    displayName: String?,
    did: String,
    avatar: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      avatar: avatar.map { FormatString<URI>(rawValue: $0) },
      did: FormatString<DID>(rawValue: did),
      displayName: displayName,
      handle: FormatString<Handle>(rawValue: handle))
  }

  /// A post view, for a notification's resolved subject.
  static func post(
    _ text: String,
    author: App.Bsky.ActorDefs_ProfileView,
    indexedAt: String = "2026-01-01T00:00:00.000Z"
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: App.Bsky.ActorDefs_ProfileViewBasic(
        did: author.did,
        displayName: author.displayName,
        handle: author.handle),
      cid: FormatString<LexLink>(rawValue: "bafyfixturepost"),
      indexedAt: FormatString<Date>(rawValue: indexedAt),
      likeCount: 12,
      record: postRecord(text: text, author: author),
      replyCount: 3,
      repostCount: 2,
      uri: FormatString<ATURI>(rawValue: postUri(text)))
  }

  /// A deterministic post URI, so a fixture row's identity is stable.
  static func postUri(_ text: String) -> String {
    let slug = text.lowercased()
      .unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .prefix(12)
    return "at://\(meDid)/app.bsky.feed.post/\(slug)"
  }

  /// A post record for the `record` field of a notification.
  static func postRecord(text: String, author: App.Bsky.ActorDefs_ProfileView) -> UnknownATPValue {
    .record(
      App.Bsky.FeedPost(
        createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
        text: text))
  }

  /// A follow record, for follows and the system notices that carry one.
  static func followRecord(now: Date) -> UnknownATPValue {
    .record(
      App.Bsky.GraphFollow(
        createdAt: FormatString<Date>(rawValue: isoString(now, minutesAgo: 1)),
        subject: FormatString<DID>(rawValue: meDid)))
  }

  /// A like record, so a like row's record is the shape the lexicon declares.
  static func likeRecord(now: Date) -> UnknownATPValue {
    .record(
      App.Bsky.FeedLike(
        createdAt: FormatString<Date>(rawValue: isoString(now, minutesAgo: 2)),
        subject: Com.Atproto.RepoStrongRef(
          cid: FormatString<LexLink>(rawValue: "bafyfixturelike"),
          uri: FormatString<ATURI>(rawValue: "at://\(meDid)/app.bsky.feed.post/fixture"))))
  }

  /// A starter pack view, for the starter-pack signup row.
  static func starterPack(name: String) -> App.Bsky.GraphDefs_StarterPackViewBasic {
    App.Bsky.GraphDefs_StarterPackViewBasic(
      cid: FormatString<LexLink>(rawValue: "bafyfixturepack"),
      creator: App.Bsky.ActorDefs_ProfileViewBasic(
        did: me.did, displayName: me.displayName, handle: me.handle),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      joinedAllTimeCount: 42,
      listItemCount: 8,
      record: .any(StarterPackName(name: name)),
      uri: FormatString<ATURI>(rawValue: "at://\(meDid)/app.bsky.graph.starterpack/fixture"))
  }

  /// The one field of a starter-pack record the surface does not read today,
  /// carried so the fixture's record is a real value rather than an empty one.
  struct StarterPackName: Codable, Hashable, Sendable {
    let name: String
  }

  /// A notification row, the lexicon shape the appview sends.
  static func notification(
    reason: App.Bsky.NotificationListNotifications_Notification_Reason,
    author: App.Bsky.ActorDefs_ProfileView,
    reasonSubject: String? = nil,
    record: UnknownATPValue,
    isRead: Bool,
    indexedAt: String,
    starterPack: App.Bsky.GraphDefs_StarterPackViewBasic? = nil
  ) -> App.Bsky.NotificationListNotifications_Notification {
    App.Bsky.NotificationListNotifications_Notification(
      author: author,
      cid: FormatString<LexLink>(rawValue: "bafyfixturenotif"),
      indexedAt: FormatString<Date>(rawValue: indexedAt),
      isRead: isRead,
      reason: reason,
      reasonSubject: reasonSubject.map { FormatString<ATURI>(rawValue: $0) },
      record: record,
      starterPack: starterPack,
      uri: FormatString<ATURI>(rawValue: "at://\(author.did.rawValue)/app.bsky.notification/fixture"))
  }

  // MARK: - Dates

  /// An ISO-8601 timestamp relative to `now`, so previews read naturally.
  static func isoString(
    _ now: Date,
    minutesAgo: Int = 0,
    hoursAgo: Int = 0,
    daysAgo: Int = 0
  ) -> String {
    let offset = TimeInterval(-(minutesAgo * 60 + hoursAgo * 3600 + daysAgo * 86400))
    let date = now.addingTimeInterval(offset)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
