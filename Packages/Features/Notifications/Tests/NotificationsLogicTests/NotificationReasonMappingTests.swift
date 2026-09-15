import Foundation
import Testing

import Lexicons
import Moderation
import NotificationsLogic
import SwiftAtproto

@Suite("Notification reason mapping")
struct NotificationReasonMappingTests {
  /// Every known reason maps to its type.
  @Test(
    "known reasons map to their types",
    arguments: [
      (App.Bsky.NotificationListNotifications_Notification_Reason.like, NotificationType.postLike),
      (.repost, .repost),
      (.mention, .mention),
      (.reply, .reply),
      (.quote, .quote),
      (.follow, .follow),
      (.starterpackJoined, .starterpackJoined),
      (.verified, .verified),
      (.unverified, .unverified),
      (.likeViaRepost, .likeViaRepost),
      (.repostViaRepost, .repostViaRepost),
      (.subscribedPost, .subscribedPost),
      (.contactMatch, .contactMatch),
    ]
  )
  func knownReasons(
    reason: App.Bsky.NotificationListNotifications_Notification_Reason,
    expected: NotificationType
  ) {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: reason,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.postRecord()
    )
    #expect(NotificationReasons.type(for: notification) == expected)
  }

  /// An unknown reason becomes `.unknown` rather than throwing, matching
  /// `toKnownType`'s fallthrough.
  @Test func unknownReasonMapsToUnknown() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: ._other("someFutureReason"),
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.postRecord()
    )
    #expect(NotificationReasons.type(for: notification) == .unknown)
    #expect(NotificationReasons.type(forReason: "someFutureReason") == .unknown)
  }

  /// A like whose subject is a feed generator splits into `feedgen-like`.
  @Test func feedGeneratorLikeSplits() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .like,
      author: Fixtures.profile(Fixtures.bobDid),
      reasonSubject: Fixtures.feedGenUri,
      record: Fixtures.likeRecord(subject: Fixtures.postUri)
    )
    #expect(NotificationReasons.type(for: notification) == .feedgenLike)
    #expect(
      NotificationReasons.subjectUri(
        type: .feedgenLike, notification: notification) == Fixtures.feedGenUri)
  }

  /// Subject URIs per reason, ported from `getSubjectUri`.
  @Test func subjectUris() {
    let reply = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .reply,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.postRecord()
    )
    #expect(
      NotificationReasons.subjectUri(type: .reply, notification: reply) == Fixtures.postUri)

    let like = Fixtures.notification(
      uri: "at://did:plc:bob/app.bsky.feed.like/l1",
      reason: .like,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.likeRecord(subject: Fixtures.postUri)
    )
    #expect(NotificationReasons.subjectUri(type: .postLike, notification: like) == Fixtures.postUri)

    let repost = Fixtures.notification(
      uri: "at://did:plc:bob/app.bsky.feed.repost/r1",
      reason: .repost,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.repostRecord(subject: Fixtures.postUri)
    )
    #expect(
      NotificationReasons.subjectUri(type: .repost, notification: repost) == Fixtures.postUri)

    let follow = Fixtures.notification(
      uri: "at://did:plc:bob/app.bsky.graph.follow/f1",
      reason: .follow,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.followRecord(subject: Fixtures.aliceDid)
    )
    // A follow has no subject post.
    #expect(NotificationReasons.subjectUri(type: .follow, notification: follow) == nil)
  }

  /// A starter-pack join points at its own notification URI, ported from the
  /// `starterpack-joined` branch of `groupNotifications`.
  @Test func starterPackSubjectIsOwnUri() {
    let notification = Fixtures.notification(
      uri: Fixtures.starterPackUri,
      reason: .starterpackJoined,
      author: Fixtures.profile(Fixtures.bobDid),
      reasonSubject: Fixtures.starterPackUri,
      record: Fixtures.followRecord(subject: Fixtures.aliceDid)
    )
    let row = NotificationReasons.makeRow(notification)
    #expect(row.type == .starterpackJoined)
    #expect(row.subjectUri == Fixtures.starterPackUri)
    #expect(row.reactKey == "notif-\(Fixtures.starterPackUri)-starterpack-joined")
  }

  /// `shouldFilter` drops an author carrying a `!hide` label regardless of
  /// moderation options.
  @Test func hideLabelFilters() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .follow,
      author: Fixtures.profile(Fixtures.bobDid, labels: [Fixtures.label("!hide")]),
      record: Fixtures.followRecord(subject: Fixtures.aliceDid)
    )
    #expect(NotificationReasons.shouldFilter(notification, moderationOpts: nil))
    #expect(NotificationReasons.labelIsHideableOffense(Fixtures.label("!takedown")))
    #expect(!NotificationReasons.labelIsHideableOffense(Fixtures.label("porn")))
  }

  /// With no moderation options and no hideable labels, nothing is filtered.
  @Test func noModerationKeepsEverything() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .follow,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.followRecord(subject: Fixtures.aliceDid)
    )
    #expect(!NotificationReasons.shouldFilter(notification, moderationOpts: nil))
  }

  /// A followed author is kept even when the account/profile decision would
  /// filter, matching the `notif.author.viewer?.following` early return.
  @Test func followedAuthorBypassesModeration() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .follow,
      author: Fixtures.profile(
        Fixtures.bobDid,
        following: "at://did:plc:me/app.bsky.graph.follow/f"),
      record: Fixtures.followRecord(subject: Fixtures.aliceDid)
    )
    let opts = ModerationOpts(userDid: "did:plc:me", prefs: ModerationPrefs())
    #expect(!NotificationReasons.shouldFilter(notification, moderationOpts: opts))
  }

  /// A moderator's `!hide` label on the notification content drops it when
  /// moderation options are present and the author is not followed.
  ///
  /// The labeler has to be in `prefs.labelers` for the engine to consider its
  /// labels at all.
  @Test func moderationTintedNotificationIsFiltered() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .reply,
      author: Fixtures.profile(Fixtures.bobDid),
      record: Fixtures.postRecord(),
      labels: [Fixtures.label("!hide")]
    )
    let opts = ModerationOpts(
      userDid: "did:plc:me",
      prefs: ModerationPrefs(labelers: [LabelerPrefs(did: Fixtures.aliceDid)])
    )
    #expect(NotificationReasons.shouldFilter(notification, moderationOpts: opts))
  }

  /// The same label on a followed author's notification does not filter, since
  /// the follow bypasses the content decision.
  @Test func moderationTintBypassedForFollowedAuthor() {
    let notification = Fixtures.notification(
      uri: Fixtures.postUri,
      reason: .reply,
      author: Fixtures.profile(
        Fixtures.bobDid,
        following: "at://did:plc:me/app.bsky.graph.follow/f"),
      record: Fixtures.postRecord(),
      labels: [Fixtures.label("!hide")]
    )
    let opts = ModerationOpts(
      userDid: "did:plc:me",
      prefs: ModerationPrefs(labelers: [LabelerPrefs(did: Fixtures.aliceDid)])
    )
    #expect(!NotificationReasons.shouldFilter(notification, moderationOpts: opts))
  }
}
