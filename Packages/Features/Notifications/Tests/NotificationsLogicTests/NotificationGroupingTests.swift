import Foundation
import Testing

import Lexicons
import NotificationsLogic
import SwiftAtproto

@Suite("Notification grouping")
struct NotificationGroupingTests {
  private func like(
    author did: String,
    at indexedAt: String,
    subject: String = Fixtures.postUri
  ) -> App.Bsky.NotificationListNotifications_Notification {
    Fixtures.notification(
      uri: "at://\(did)/app.bsky.feed.like/\(indexedAt)",
      reason: .like,
      author: Fixtures.profile(did),
      // The appview sets `reasonSubject` to the liked post, which is what the
      // grouping equality check compares.
      reasonSubject: subject,
      record: Fixtures.likeRecord(subject: subject),
      indexedAt: indexedAt
    )
  }

  /// Likes from different authors on the same post, close in time, fold into
  /// one row.
  @Test func likesGroup() {
    let rows = NotificationReasons.group([
      like(author: Fixtures.aliceDid, at: "2026-01-01T00:00:00.000Z"),
      like(author: Fixtures.bobDid, at: "2026-01-01T01:00:00.000Z"),
    ])
    #expect(rows.count == 1)
    #expect(rows[0].additional.count == 1)
    #expect(rows[0].notification.author.did.rawValue == Fixtures.aliceDid)
    #expect(rows[0].additional[0].author.did.rawValue == Fixtures.bobDid)
  }

  /// Likes more than two days apart do not fold.
  @Test func likesTooFarApartDoNotGroup() {
    let rows = NotificationReasons.group([
      like(author: Fixtures.aliceDid, at: "2026-01-01T00:00:00.000Z"),
      like(author: Fixtures.bobDid, at: "2026-01-05T00:00:00.000Z"),
    ])
    #expect(rows.count == 2)
  }

  /// Likes on different posts do not fold.
  @Test func differentSubjectsDoNotGroup() {
    let rows = NotificationReasons.group([
      like(author: Fixtures.aliceDid, at: "2026-01-01T00:00:00.000Z"),
      like(
        author: Fixtures.bobDid, at: "2026-01-01T01:00:00.000Z", subject: Fixtures.otherPostUri),
    ])
    #expect(rows.count == 2)
  }

  /// Two likes from the same author do not fold: a duplicate like of one post
  /// by one account reads as one action.
  @Test func sameAuthorDoesNotGroup() {
    let rows = NotificationReasons.group([
      like(author: Fixtures.aliceDid, at: "2026-01-01T00:00:00.000Z"),
      Fixtures.notification(
        uri: "at://did:plc:alice/app.bsky.feed.like/second",
        reason: .like,
        author: Fixtures.profile(Fixtures.aliceDid),
        record: Fixtures.likeRecord(subject: Fixtures.postUri),
        indexedAt: "2026-01-01T01:00:00.000Z"
      ),
    ])
    #expect(rows.count == 2)
  }

  /// A non-groupable reason never folds, even with a matching neighbor.
  @Test func nonGroupableReasonNeverGroups() {
    let rows = NotificationReasons.group([
      Fixtures.notification(
        uri: "at://did:plc:alice/app.bsky.feed.post/m1",
        reason: .mention,
        author: Fixtures.profile(Fixtures.aliceDid),
        record: Fixtures.postRecord(),
        indexedAt: "2026-01-01T00:00:00.000Z"
      ),
      Fixtures.notification(
        uri: "at://did:plc:bob/app.bsky.feed.post/m2",
        reason: .mention,
        author: Fixtures.profile(Fixtures.bobDid),
        record: Fixtures.postRecord(),
        indexedAt: "2026-01-01T01:00:00.000Z"
      ),
    ])
    #expect(rows.count == 2)
  }

  /// Follows from two accounts fold.
  @Test func followsGroup() {
    let rows = NotificationReasons.group([
      Fixtures.notification(
        uri: "at://did:plc:alice/app.bsky.graph.follow/1",
        reason: .follow,
        author: Fixtures.profile(Fixtures.aliceDid),
        record: Fixtures.followRecord(subject: Fixtures.aliceDid),
        indexedAt: "2026-01-01T00:00:00.000Z"
      ),
      Fixtures.notification(
        uri: "at://did:plc:bob/app.bsky.graph.follow/2",
        reason: .follow,
        author: Fixtures.profile(Fixtures.bobDid),
        record: Fixtures.followRecord(subject: Fixtures.bobDid),
        indexedAt: "2026-01-01T01:00:00.000Z"
      ),
    ])
    #expect(rows.count == 1)
    #expect(rows[0].additional.count == 1)
  }

  /// A follow-back breaks grouping: following the viewer back is a different
  /// event from a plain follow.
  @Test func followBackDoesNotGroup() {
    let rows = NotificationReasons.group([
      Fixtures.notification(
        uri: "at://did:plc:alice/app.bsky.graph.follow/1",
        reason: .follow,
        author: Fixtures.profile(Fixtures.aliceDid),
        record: Fixtures.followRecord(subject: Fixtures.aliceDid),
        indexedAt: "2026-01-01T00:00:00.000Z"
      ),
      Fixtures.notification(
        uri: "at://did:plc:bob/app.bsky.graph.follow/2",
        reason: .follow,
        author: Fixtures.profile(
          Fixtures.bobDid,
          following: "at://did:plc:me/app.bsky.graph.follow/f"),
        record: Fixtures.followRecord(subject: Fixtures.bobDid),
        indexedAt: "2026-01-01T01:00:00.000Z"
      ),
    ])
    #expect(rows.count == 2)
  }

  /// Ported 1:1 from `util.test.ts`:
  /// "does not group a Starter Pack follow with an organic follow".
  @Test func starterPackFollowDoesNotGroupWithOrganicFollow() {
    let pack = "at://did:plc:alice/app.bsky.graph.starterpack/a"
    let rows = NotificationReasons.group([
      followNotification(did: "did:plc:a"),
      followNotification(did: "did:plc:b", starterPack: pack),
    ])

    #expect(rows.count == 2)
    #expect(rows[0].notification.author.did.rawValue == "did:plc:a")
    #expect(rows[0].notification.starterPack == nil)
    #expect(rows[0].additional.isEmpty)
    #expect(rows[1].notification.author.did.rawValue == "did:plc:b")
    #expect(rows[1].notification.starterPack?.uri.rawValue == pack)
    #expect(rows[1].additional.isEmpty)
  }

  /// Ported 1:1 from `util.test.ts`: "groups follows by Starter Pack".
  @Test func groupsFollowsByStarterPack() {
    let packA = "at://did:plc:alice/app.bsky.graph.starterpack/a"
    let packB = "at://did:plc:bob/app.bsky.graph.starterpack/b"
    let rows = NotificationReasons.group([
      followNotification(did: "did:plc:a", starterPack: packA),
      followNotification(did: "did:plc:b", starterPack: packB),
      followNotification(did: "did:plc:c", starterPack: packA),
      followNotification(did: "did:plc:d"),
      followNotification(did: "did:plc:e", starterPack: packB),
      followNotification(did: "did:plc:f"),
    ])

    let shape = rows.map { row in
      [row.notification.author.did.rawValue] + row.additional.map { $0.author.did.rawValue }
    }
    #expect(
      shape == [
        ["did:plc:a", "did:plc:c"],
        ["did:plc:b", "did:plc:e"],
        ["did:plc:d", "did:plc:f"],
      ])
  }

  /// The RN fixture builder, ported: a follow notification with an optional
  /// starter pack and a fixed timestamp.
  private func followNotification(
    did: String,
    starterPack: String? = nil
  ) -> App.Bsky.NotificationListNotifications_Notification {
    Fixtures.notification(
      uri: "at://\(did)/app.bsky.graph.follow/follow",
      reason: .follow,
      author: Fixtures.profile(did),
      record: Fixtures.followRecord(subject: did),
      indexedAt: "2026-07-28T12:00:00.000Z",
      starterPack: starterPack.map(Fixtures.starterPack)
    )
  }

  /// Follows via different starter packs do not fold, matching the starter-pack
  /// equality guard.
  @Test func differentStarterPacksDoNotGroup() {
    let packA = Fixtures.starterPack(Fixtures.starterPackUri)
    let packB = Fixtures.starterPack("at://did:plc:bob/app.bsky.graph.starterpack/other")
    let rows = NotificationReasons.group([
      Fixtures.notification(
        uri: "at://did:plc:alice/app.bsky.graph.follow/1",
        reason: .follow,
        author: Fixtures.profile(Fixtures.aliceDid),
        record: Fixtures.followRecord(subject: Fixtures.aliceDid),
        indexedAt: "2026-01-01T00:00:00.000Z",
        starterPack: packA
      ),
      Fixtures.notification(
        uri: "at://did:plc:bob/app.bsky.graph.follow/2",
        reason: .follow,
        author: Fixtures.profile(Fixtures.bobDid),
        record: Fixtures.followRecord(subject: Fixtures.bobDid),
        indexedAt: "2026-01-01T01:00:00.000Z",
        starterPack: packB
      ),
    ])
    #expect(rows.count == 2)
  }
}

extension Fixtures {
  /// A starter-pack view, for grouping tests.
  static func starterPack(_ uri: String) -> App.Bsky.GraphDefs_StarterPackViewBasic {
    App.Bsky.GraphDefs_StarterPackViewBasic(
      cid: FormatString<LexLink>(rawValue: "bafy"),
      creator: App.Bsky.ActorDefs_ProfileViewBasic(
        did: FormatString<DID>(rawValue: aliceDid),
        handle: FormatString<Handle>(rawValue: "alice")),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      record: .record(
        App.Bsky.GraphStarterpack(
          createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
          list: FormatString<ATURI>(rawValue: "at://did:plc:alice/app.bsky.graph.list/l"),
          name: "pack"
        )),
      uri: FormatString<ATURI>(rawValue: uri)
    )
  }
}
