import Foundation

import Lexicons
import NotificationsLogic
import SwiftAtproto

final class FakeNotificationClient: NotificationClient, @unchecked Sendable {
  /// One recorded call.
  enum Call: Sendable, Equatable {
    case listNotifications(cursor: String?, limit: Int?, priority: Bool?, reasons: [String]?)
    case getPosts(uris: [String])
    case getStarterPacks(uris: [String])
    case listActivitySubscriptions(cursor: String?, limit: Int?)
    case putActivitySubscription(subject: String, post: Bool, reply: Bool)
    case getNotificationPreferences
    case putNotificationPreferences
    case updateSeen(seenAt: Date)
  }

  private let lock = NSLock()
  private var _calls: [Call] = []

  /// Pages keyed by the cursor that requested them; `nil` key is page one.
  var pages: [String?: App.Bsky.NotificationListNotifications_Output] = [:]
  /// Posts returned by `getPosts`, keyed by URI.
  var posts: [String: App.Bsky.FeedDefs_PostView] = [:]
  /// Starter packs returned by `getStarterPacks`, keyed by URI.
  var starterPacks: [String: App.Bsky.GraphDefs_StarterPackViewBasic] = [:]
  /// Activity subscription pages keyed by cursor.
  var subscriptions: [String?: App.Bsky.NotificationListActivitySubscriptions_Output] = [:]
  /// The value `putActivitySubscription` echoes back.
  var putResult: App.Bsky.NotificationPutActivitySubscription_Output?
  /// The preferences `getNotificationPreferences` returns.
  var notificationPreferences: App.Bsky.NotificationDefs_Preferences?
  /// The value `putNotificationPreferences` echoes back.
  var putPreferencesResult: App.Bsky.NotificationDefs_Preferences?
  /// When set, every call throws this.
  var error: (any Error)?

  var calls: [Call] { withLock { _calls } }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private func record(_ call: Call) {
    withLock { _calls.append(call) }
  }

  /// Calls of one kind, for targeted assertions.
  func calls(of kind: String) -> [Call] {
    calls.filter { call in
      switch (call, kind) {
      case (.listNotifications, "listNotifications"): return true
      case (.getPosts, "getPosts"): return true
      case (.getStarterPacks, "getStarterPacks"): return true
      case (.listActivitySubscriptions, "listActivitySubscriptions"): return true
      case (.putActivitySubscription, "putActivitySubscription"): return true
      case (.getNotificationPreferences, "getNotificationPreferences"): return true
      case (.putNotificationPreferences, "putNotificationPreferences"): return true
      case (.updateSeen, "updateSeen"): return true
      default: return false
      }
    }
  }

  func listNotifications(
    cursor: String?, limit: Int?, priority: Bool?, reasons: [String]?
  ) async throws -> App.Bsky.NotificationListNotifications_Output {
    record(.listNotifications(cursor: cursor, limit: limit, priority: priority, reasons: reasons))
    if let error { throw error }
    // An exhausted script returns an empty page rather than throwing, which is
    // what the appview does at the end of a list.
    return pages[cursor] ?? App.Bsky.NotificationListNotifications_Output(notifications: [])
  }

  func getPosts(uris: [String]) async throws -> App.Bsky.FeedGetPosts_Output {
    record(.getPosts(uris: uris))
    if let error { throw error }
    return App.Bsky.FeedGetPosts_Output(posts: uris.compactMap { posts[$0] })
  }

  func getStarterPacks(uris: [String]) async throws -> App.Bsky.GraphGetStarterPacks_Output {
    record(.getStarterPacks(uris: uris))
    if let error { throw error }
    return App.Bsky.GraphGetStarterPacks_Output(
      starterPacks: uris.compactMap { starterPacks[$0] })
  }

  func listActivitySubscriptions(
    cursor: String?, limit: Int?
  ) async throws -> App.Bsky.NotificationListActivitySubscriptions_Output {
    record(.listActivitySubscriptions(cursor: cursor, limit: limit))
    if let error { throw error }
    return subscriptions[cursor]
      ?? App.Bsky.NotificationListActivitySubscriptions_Output(subscriptions: [])
  }

  func putActivitySubscription(
    subject: String, post: Bool, reply: Bool
  ) async throws -> App.Bsky.NotificationPutActivitySubscription_Output {
    record(.putActivitySubscription(subject: subject, post: post, reply: reply))
    if let error { throw error }
    return putResult
      ?? App.Bsky.NotificationPutActivitySubscription_Output(
        activitySubscription: App.Bsky.NotificationDefs_ActivitySubscription(
          post: post, reply: reply),
        subject: FormatString<DID>(rawValue: subject))
  }

  func getNotificationPreferences() async throws
    -> App.Bsky.NotificationGetPreferences_Output {
    record(.getNotificationPreferences)
    if let error { throw error }
    guard let notificationPreferences else {
      throw FakeError.missingFixture("notificationPreferences")
    }
    return App.Bsky.NotificationGetPreferences_Output(preferences: notificationPreferences)
  }

  func putNotificationPreferences(
    _ preferences: App.Bsky.NotificationDefs_Preferences
  ) async throws -> App.Bsky.NotificationPutPreferencesV2_Output {
    record(.putNotificationPreferences)
    if let error { throw error }
    return App.Bsky.NotificationPutPreferencesV2_Output(
      preferences: putPreferencesResult ?? preferences)
  }

  func updateSeen(seenAt: Date) async throws {
    record(.updateSeen(seenAt: seenAt))
    if let error { throw error }
  }
}

/// Errors the fakes raise for missing fixtures.
enum FakeError: Error, Equatable {
  case missingFixture(String)
}

// MARK: - Fixture builders

/// Small, deterministic notification fixtures.
enum Fixtures {
  static let aliceDid = "did:plc:alice"
  static let bobDid = "did:plc:bob"
  static let carolDid = "did:plc:carol"
  static let postUri = "at://did:plc:alice/app.bsky.feed.post/abc"
  static let otherPostUri = "at://did:plc:bob/app.bsky.feed.post/def"
  static let starterPackUri = "at://did:plc:alice/app.bsky.graph.starterpack/sp1"
  static let feedGenUri = "at://did:plc:feedgen/app.bsky.feed.generator/whats-hot"

  static func profile(
    _ did: String,
    following: String? = nil,
    labels: [Com.Atproto.LabelDefs_Label]? = nil
  ) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      did: FormatString<DID>(rawValue: did),
      handle: FormatString<Handle>(rawValue: did.replacingOccurrences(of: "did:plc:", with: "")),
      labels: labels,
      viewer: following.map {
        App.Bsky.ActorDefs_ViewerState(
          following: FormatString<ATURI>(rawValue: $0))
      }
    )
  }

  static func label(_ val: String, src: String = aliceDid) -> Com.Atproto.LabelDefs_Label {
    Com.Atproto.LabelDefs_Label(
      cts: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      src: FormatString<DID>(rawValue: src),
      uri: FormatString<URI>(rawValue: postUri),
      val: val
    )
  }

  /// A post record, for the `record` field of a notification.
  static func postRecord(text: String = "hello") -> UnknownATPValue {
    .record(
      App.Bsky.FeedPost(
        createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
        text: text
      ))
  }

  /// A like record whose subject is `uri`.
  static func likeRecord(subject uri: String) -> UnknownATPValue {
    .record(
      App.Bsky.FeedLike(
        createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
        subject: Com.Atproto.RepoStrongRef(
          cid: FormatString<LexLink>(rawValue: "bafy"),
          uri: FormatString<ATURI>(rawValue: uri)
        )
      ))
  }

  /// A repost record whose subject is `uri`.
  static func repostRecord(subject uri: String) -> UnknownATPValue {
    .record(
      App.Bsky.FeedRepost(
        createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
        subject: Com.Atproto.RepoStrongRef(
          cid: FormatString<LexLink>(rawValue: "bafy"),
          uri: FormatString<ATURI>(rawValue: uri)
        )
      ))
  }

  /// A follow record.
  static func followRecord(subject did: String) -> UnknownATPValue {
    .record(
      App.Bsky.GraphFollow(
        createdAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
        subject: FormatString<DID>(rawValue: did)
      ))
  }

  /// A notification.
  static func notification(
    uri: String,
    reason: App.Bsky.NotificationListNotifications_Notification_Reason,
    author: App.Bsky.ActorDefs_ProfileView,
    reasonSubject: String? = nil,
    record: UnknownATPValue,
    isRead: Bool = false,
    indexedAt: String = "2026-01-01T00:00:00.000Z",
    labels: [Com.Atproto.LabelDefs_Label]? = nil,
    starterPack: App.Bsky.GraphDefs_StarterPackViewBasic? = nil
  ) -> App.Bsky.NotificationListNotifications_Notification {
    App.Bsky.NotificationListNotifications_Notification(
      author: author,
      cid: FormatString<LexLink>(rawValue: "bafy"),
      indexedAt: FormatString<Date>(rawValue: indexedAt),
      isRead: isRead,
      labels: labels,
      reason: reason,
      reasonSubject: reasonSubject.map { FormatString<ATURI>(rawValue: $0) },
      record: record,
      starterPack: starterPack,
      uri: FormatString<ATURI>(rawValue: uri)
    )
  }

  /// A post view, for `getPosts` results.
  static func postView(
    uri: String,
    author: App.Bsky.ActorDefs_ProfileViewBasic? = nil,
    labels: [Com.Atproto.LabelDefs_Label]? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: author
        ?? App.Bsky.ActorDefs_ProfileViewBasic(
          did: FormatString<DID>(rawValue: aliceDid),
          handle: FormatString<Handle>(rawValue: "alice")),
      cid: FormatString<LexLink>(rawValue: "bafy"),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      labels: labels,
      record: postRecord(),
      uri: FormatString<ATURI>(rawValue: uri)
    )
  }

  /// A listNotifications page.
  static func page(
    _ notifications: [App.Bsky.NotificationListNotifications_Notification],
    cursor: String? = nil,
    seenAt: String? = "2026-01-01T00:00:00.000Z",
    priority: Bool? = nil
  ) -> App.Bsky.NotificationListNotifications_Output {
    App.Bsky.NotificationListNotifications_Output(
      cursor: cursor,
      notifications: notifications,
      priority: priority,
      seenAt: seenAt.map { FormatString<Date>(rawValue: $0) }
    )
  }
}
