import Foundation

import Lexicons
import Moderation

public enum NotificationReasons {
  /// Reasons that fold into a single row when they are close in time and share
  /// a subject. Ported from `GROUPABLE_REASONS`.
  public static let groupableReasons: Set<String> = [
    "like",
    "repost",
    "follow",
    "like-via-repost",
    "repost-via-repost",
    "subscribed-post",
  ]

  /// The window within which two groupable notifications fold together.
  /// Ported from `MS_2DAY`.
  public static let groupingWindow: TimeInterval = 48 * 60 * 60

  /// Maps a raw notification's `reason` to the feed's ``NotificationType``.
  ///
  /// `like` splits on the subject: a like whose `reasonSubject` names a feed
  /// generator is a ``NotificationType/feedgenLike``, everything else is a
  /// ``NotificationType/postLike``. Any reason this build does not know becomes
  /// ``NotificationType/unknown`` rather than throwing, matching
  /// `toKnownType`'s fallthrough.
  public static func type(for notification: RawNotification) -> NotificationType {
    switch notification.reason {
    case .like:
      if notification.reasonSubject?.rawValue.contains("feed.generator") == true {
        return .feedgenLike
      }
      return .postLike
    case .repost: return .repost
    case .mention: return .mention
    case .reply: return .reply
    case .quote: return .quote
    case .follow: return .follow
    case .starterpackJoined: return .starterpackJoined
    case .verified: return .verified
    case .unverified: return .unverified
    case .likeViaRepost: return .likeViaRepost
    case .repostViaRepost: return .repostViaRepost
    case .subscribedPost: return .subscribedPost
    case .contactMatch: return .contactMatch
    case ._other: return .unknown
    }
  }

  /// Maps a raw `reason` string to a ``NotificationType``, for callers that
  /// only have the wire string.
  public static func type(forReason reason: String) -> NotificationType {
    NotificationType(rawValue: reason) ?? .unknown
  }

  /// The subject URI a row points at, ported from `getSubjectUri`.
  ///
  /// Replies, quotes, mentions and subscribed-post notifications point at the
  /// notification's own URI (the post the user's action produced). Likes and
  /// reposts point at the record's `subject.uri`, read out of the raw record.
  /// Feed-generator likes point at `reasonSubject`.
  public static func subjectUri(
    type: NotificationType,
    notification: RawNotification
  ) -> String? {
    switch type {
    case .reply, .quote, .mention, .subscribedPost:
      return notification.uri.rawValue
    case .postLike, .repost, .likeViaRepost, .repostViaRepost:
      return recordSubjectUri(notification.record)
    case .feedgenLike:
      return notification.reasonSubject?.rawValue
    default:
      return nil
    }
  }

  /// Reads `subject.uri` out of a like or repost record.
  ///
  /// The record arrives as an open ``UnknownATPValue``. The generated `like`
  /// and `repost` records each expose a strong ref under `subject`; an unknown
  /// record type yields `nil`.
  public static func recordSubjectUri(_ record: UnknownATPValue) -> String? {
    switch record {
    case .record(let value):
      if let like = value as? App.Bsky.FeedLike {
        return like.subject.uri.rawValue
      }
      if let repost = value as? App.Bsky.FeedRepost {
        return repost.subject.uri.rawValue
      }
      return nil
    case .any:
      return nil
    }
  }

  /// The starter-pack URI a `starterpack-joined` notification points at.
  public static func starterPackUri(_ notification: RawNotification) -> String? {
    notification.reasonSubject?.rawValue
  }

  // MARK: - Grouping

  /// Folds similar notifications into single rows, ported from
  /// `groupNotifications`.
  ///
  /// A notification joins the first earlier row it is "groupable" with:
  /// same reason, same subject, within ``groupingWindow``, a different author
  /// (or the same author on a `subscribed-post`), matching starter pack for
  /// follows, and neither side a follow-back. Rows keep the order they arrived
  /// in, and the grouped notifications go on the row's `additional` list.
  public static func group(_ notifications: [RawNotification]) -> [FeedNotification] {
    var grouped: [FeedNotification] = []
    for notification in notifications {
      let time = indexedDate(notification)
      var didGroup = false
      if groupableReasons.contains(notification.reason.rawValue) {
        for index in grouped.indices {
          guard canGroup(notification, into: grouped[index], at: time) else { continue }
          let nextIsFollowBack =
            notification.reason == .follow && notification.author.viewer?.following != nil
          let prevIsFollowBack =
            grouped[index].notification.reason == .follow
            && grouped[index].notification.author.viewer?.following != nil
          // A follow-back never folds into a row: the two read differently.
          guard !nextIsFollowBack, !prevIsFollowBack else { continue }
          grouped[index].additional.append(notification)
          didGroup = true
          break
        }
      }
      if !didGroup {
        grouped.append(makeRow(notification))
      }
    }
    return grouped
  }

  /// One ungrouped row, with its identity and subject URI derived.
  public static func makeRow(_ notification: RawNotification) -> FeedNotification {
    let type = type(for: notification)
    let subjectUri =
      type == .starterpackJoined
      ? notification.uri.rawValue
      : subjectUri(type: type, notification: notification)
    return FeedNotification(
      reactKey: "notif-\(notification.uri.rawValue)-\(notification.reason.rawValue)",
      type: type,
      notification: notification,
      subjectUri: subjectUri
    )
  }

  /// True when `notification` may fold into `row` per the grouping rules.
  private static func canGroup(
    _ notification: RawNotification,
    into row: FeedNotification,
    at time: Date
  ) -> Bool {
    let other = row.notification
    let delta = abs(indexedDate(other).timeIntervalSince(time))
    guard delta < groupingWindow else { return false }
    guard notification.reason == other.reason else { return false }
    guard notification.reasonSubject?.rawValue == other.reasonSubject?.rawValue else {
      return false
    }
    if notification.reason == .follow {
      guard notification.starterPack?.uri.rawValue == other.starterPack?.uri.rawValue else {
        return false
      }
    }
    // Same author folds only for subscribed-post, where a batch of posts from
    // one account reads as one row.
    if notification.author.did.rawValue == other.author.did.rawValue
      && notification.reason != .subscribedPost {
      return false
    }
    return true
  }

  /// A notification's `indexedAt` as a `Date`, falling back to the epoch when
  /// the wire string does not parse.
  public static func indexedDate(_ notification: RawNotification) -> Date {
    parseATProtoDate(notification.indexedAt.rawValue) ?? Date(timeIntervalSince1970: 0)
  }

  // MARK: - Filtering

  /// True when a notification should be dropped before grouping.
  ///
  /// Ported from `shouldFilterNotif`: an `!hide`/`!takedown` label on the
  /// author drops the row unconditionally; a `subscribed-post` whose text
  /// matches a muted word is dropped; a followed author is kept regardless of
  /// the account/profile decision; anything else is decided by
  /// `moderateNotification(...).ui('contentList').filter`.
  public static func shouldFilter(
    _ notification: RawNotification,
    moderationOpts: ModerationOpts?
  ) -> Bool {
    if notification.author.labels?.contains(where: labelIsHideableOffense) == true {
      return true
    }
    guard let moderationOpts else { return false }
    if notification.reason == .subscribedPost, case .record(let record) = notification.record,
      let post = record as? App.Bsky.FeedPost {
      let muted = hasMutedWord(
        mutedWords: moderationOpts.prefs.mutedWords,
        text: post.text,
        facets: nil,
        outlineTags: post.tags,
        languages: post.langs?.map(\.rawValue),
        actor: authorViewBasic(notification)
      )
      if muted { return true }
    }
    if notification.author.viewer?.following != nil { return false }
    return moderateNotification(
      notificationView(notification),
      opts: moderationOpts
    ).ui(.contentList).filter
  }

  /// True for the system labels that hide content outright, ported from
  /// `labelIsHideableOffense`.
  public static func labelIsHideableOffense(_ label: Com.Atproto.LabelDefs_Label) -> Bool {
    label.val == "!hide" || label.val == "!takedown"
  }
  // MARK: - Moderation bridging

  /// Projects a lexicon notification onto the engine's `NotificationView`.
  public static func notificationView(_ notification: RawNotification) -> NotificationView {
    NotificationView(
      type: "app.bsky.notification.listNotifications#notification",
      uri: notification.uri.rawValue,
      cid: notification.cid.rawValue,
      author: authorViewBasic(notification),
      reason: notification.reason.rawValue,
      record: postRecord(notification.record),
      labels: notification.labels.map(convertLabels),
      indexedAt: notification.indexedAt.rawValue
    )
  }

  /// The engine's account/profile shape for a notification author.
  public static func authorViewBasic(_ notification: RawNotification) -> ProfileViewBasic {
    let author = notification.author
    return ProfileViewBasic(
      did: author.did.rawValue,
      handle: author.handle.rawValue,
      displayName: author.displayName,
      avatar: author.avatar?.rawValue,
      viewer: author.viewer.map(actorViewerState),
      labels: (author.labels ?? []).map(convertLabels)
    )
  }

  /// The engine's viewer state for a notification author.
  public static func actorViewerState(
    _ viewer: App.Bsky.ActorDefs_ViewerState
  ) -> Moderation.ActorViewerState {
    Moderation.ActorViewerState(
      muted: viewer.muted,
      blockedBy: viewer.blockedBy,
      blocking: viewer.blocking?.rawValue,
      following: viewer.following?.rawValue
    )
  }

  /// Converts lexicon labels to the engine's label shape.
  public static func convertLabels(
    _ labels: [Com.Atproto.LabelDefs_Label]
  ) -> [Moderation.Label] {
    labels.map { label in
      Moderation.Label(
        ver: label.ver,
        src: label.src.rawValue,
        uri: label.uri.rawValue,
        cid: label.cid?.rawValue,
        val: label.val,
        neg: label.neg,
        cts: label.cts.rawValue
      )
    }
  }

  /// The engine's post record, when the notification's record is a post.
  ///
  /// Returns `nil` for likes, reposts, follows and unknown record types, which
  /// is what the engine expects: only post-shaped records carry text to scan.
  public static func postRecord(_ record: UnknownATPValue) -> FeedPostRecord? {
    guard case .record(let value) = record, let post = value as? App.Bsky.FeedPost else {
      return nil
    }
    return FeedPostRecord(
      type: "app.bsky.feed.post",
      text: post.text,
      facets: post.facets.map(convertFacets),
      tags: post.tags,
      langs: post.langs?.map(\.rawValue)
    )
  }
  /// Converts lexicon facets to the engine's facet shape.
  ///
  /// `Moderation.RichTextFacet` exposes no public initializer, so the
  /// conversion goes through the wire shape both types already share: the
  /// generated facet is encoded and decoded into the engine's type, which
  /// carries the same `{index, features}` JSON and reads only the tag feature.
  public static func convertFacets(
    _ facets: [App.Bsky.RichtextFacet]
  ) -> [Moderation.RichTextFacet] {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    return facets.compactMap { facet in
      guard let data = try? encoder.encode(facet) else { return nil }
      return try? decoder.decode(Moderation.RichTextFacet.self, from: data)
    }
  }

  // MARK: - Moderation-tinted feed rows

  /// Applies the feed's post-moderation pass, ported from the `select`
  /// callback's second filter.
  ///
  /// A reply, mention or quote whose subject resolves to a post is dropped when
  /// `moderatePost(subject).ui('contentList').filter` says so. Notifications
  /// with no resolved subject, or with a non-post subject, are kept.
  public static func isFilteredBySubjectModeration(
    _ item: FeedNotification,
    moderationOpts: ModerationOpts?
  ) -> Bool {
    guard let moderationOpts else { return false }
    guard item.type == .reply || item.type == .mention || item.type == .quote else {
      return false
    }
    guard case .post(let post) = item.subject else { return false }
    return moderatePost(postView(post), opts: moderationOpts).ui(.contentList).filter
  }

  /// Projects a lexicon post view onto the engine's `PostView`.
  public static func postView(_ post: App.Bsky.FeedDefs_PostView) -> Moderation.PostView {
    Moderation.PostView(
      type: "app.bsky.feed.defs#postView",
      uri: post.uri.rawValue,
      cid: post.cid.rawValue,
      author: postAuthorBasic(post),
      record: recordOf(post.record),
      labels: post.labels.map(convertLabels),
      indexedAt: post.indexedAt.rawValue
    )
  }

  /// The engine's author shape for a post view.
  public static func postAuthorBasic(_ post: App.Bsky.FeedDefs_PostView) -> ProfileViewBasic {
    let author = post.author
    return ProfileViewBasic(
      did: author.did.rawValue,
      handle: author.handle.rawValue,
      displayName: author.displayName,
      avatar: author.avatar?.rawValue,
      viewer: author.viewer.map(actorViewerState),
      labels: (author.labels ?? []).map(convertLabels)
    )
  }

  /// The engine's post record for a lexicon post view, when it is a post.
  public static func recordOf(_ record: UnknownATPValue) -> FeedPostRecord? {
    postRecord(record)
  }

  // MARK: - Dates

  /// Parses an AT Protocol datetime, trying the fractional-seconds form the
  /// appview sends first and falling back to the whole-second form.
  public static func parseATProtoDate(_ raw: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: raw) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: raw)
  }
}
