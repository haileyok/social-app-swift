import Foundation

import Lexicons

public typealias RawNotification = App.Bsky.NotificationListNotifications_Notification

/// The lexicon `reason` union, kept open so a reason this build does not know
/// about still decodes and still renders.
///
/// The generated `NotificationListNotifications_Notification_Reason` already
/// carries the unknown case as `._other(String)`; this alias documents the
/// intent at the call sites that read a reason.
public typealias RawNotificationReason = App.Bsky.NotificationListNotifications_Notification_Reason

/// The notification kind the feed layer works with.
///
/// Ported from `NotificationType` in
/// `src/state/queries/notifications/types.ts`. The lexicon sends `like` for both
/// post likes and feed-generator likes, so the split into `postLike` and
/// `feedgenLike` happens here, on the `reasonSubject`.
public enum NotificationType: String, Sendable, Hashable, CaseIterable {
  case starterpackJoined = "starterpack-joined"
  case postLike = "post-like"
  case repost
  case mention
  case reply
  case quote
  case follow
  case feedgenLike = "feedgen-like"
  case verified
  case unverified
  case likeViaRepost = "like-via-repost"
  case repostViaRepost = "repost-via-repost"
  case subscribedPost = "subscribed-post"
  case contactMatch = "contact-match"
  /// Any reason this build does not recognize.
  case unknown
}

/// The feed's server-side filter, matching the RN `filter: 'all' | 'mentions'`.
public enum NotificationFeedFilter: String, Sendable, Hashable, CaseIterable {
  case all
  case mentions

  /// The `reasons` query parameter sent for this filter.
  ///
  /// `all` sends no reasons (the server decides); `mentions` asks for anything
  /// that lands on the viewer's own posts.
  public var reasons: [String] {
    switch self {
    case .all: []
    case .mentions: ["mention", "reply", "quote"]
    }
  }
}

/// A single row in the notifications feed.
///
/// This is the RN `FeedNotification` without `_reactKey`'s React coupling: the
/// key is a stable string the feed layer can use for identity. `additional`
/// holds the notifications folded into this row by ``groupNotifications``.
public struct FeedNotification: Sendable, Hashable {
  /// Stable row identity, `notif-<uri>-<reason>`.
  public var reactKey: String
  /// The kind this row renders as.
  public var type: NotificationType
  /// The newest notification in the group.
  public var notification: RawNotification
  /// The notifications grouped behind ``notification``.
  public var additional: [RawNotification]
  /// The subject post (or starter pack) URI this row resolves to.
  public var subjectUri: String?
  /// The resolved subject, when additional data was fetched.
  public var subject: ResolvedSubject?

  public init(
    reactKey: String,
    type: NotificationType,
    notification: RawNotification,
    additional: [RawNotification] = [],
    subjectUri: String? = nil,
    subject: ResolvedSubject? = nil
  ) {
    self.reactKey = reactKey
    self.type = type
    self.notification = notification
    self.additional = additional
    self.subjectUri = subjectUri
    self.subject = subject
  }
}

/// The subject a notification points at, resolved to the view the UI needs.
///
/// The RN layer narrows `subject` to a `PostView` for every reason except
/// `starterpack-joined`, which points at a starter pack.
public enum ResolvedSubject: Sendable, Hashable {
  case post(App.Bsky.FeedDefs_PostView)
  case starterPack(App.Bsky.GraphDefs_StarterPackViewBasic)

  /// The subject's AT URI, whichever case it is.
  public var uri: String {
    switch self {
    case .post(let post): post.uri.rawValue
    case .starterPack(let pack): pack.uri.rawValue
    }
  }
}

/// One page of the notifications feed.
///
/// `seenAt` is the server's read watermark for the page and is what the feed
/// layer uses to recompute `isRead` locally; `priority` carries the appview's
/// "these are the important ones" flag.
public struct NotificationFeedPage: Sendable, Hashable {
  public var cursor: String?
  public var seenAt: Date
  public var items: [FeedNotification]
  public var priority: Bool

  public init(
    cursor: String? = nil,
    seenAt: Date,
    items: [FeedNotification],
    priority: Bool = false
  ) {
    self.cursor = cursor
    self.seenAt = seenAt
    self.items = items
    self.priority = priority
  }
}

/// The unread counter the UI shows.
///
/// Ported from the `'' | '1'..'29' | '30+'` state string in
/// `src/state/queries/notifications/unread.tsx`, kept as an enum so callers
/// cannot invent an out-of-range value.
public enum UnreadCount: Sendable, Hashable {
  /// No unread notifications. Renders as an empty badge.
  case none
  /// Between 1 and 29 unread notifications.
  case some(Int)
  /// Thirty or more, rendered as `30+`.
  case many

  /// Builds the value from a raw count, applying the `30+` cap.
  public init(count: Int) {
    switch count {
    // Thirty or more saturates, matching the RN `30+` badge.
    case 30...: self = .many
    case 1...: self = .some(count)
    default: self = .none
    }
  }

  /// The wire string the app broadcasts: `''`, a number, or `30+`.
  public var rawValue: String {
    switch self {
    case .none: ""
    case .some(let n): String(n)
    case .many: "30+"
    }
  }

  /// The count to poll against, mirroring the RN cache's numeric field.
  public var count: Int {
    switch self {
    case .none: 0
    case .some(let n): n
    case .many: 30
    }
  }
}
