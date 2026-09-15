import Foundation
import Testing

import Lexicons
import NotificationsLogic
import QueryStore
import SwiftAtproto

@Suite("Activity subscriptions")
struct ActivitySubscriptionsTests {
  private func makeStore() -> QueryStore {
    QueryStore(clock: ManualQueryClock())
  }

  private func subscriptionsPage(
    _ dids: [String],
    cursor: String? = nil
  ) -> App.Bsky.NotificationListActivitySubscriptions_Output {
    App.Bsky.NotificationListActivitySubscriptions_Output(
      cursor: cursor,
      subscriptions: dids.map {
        App.Bsky.ActorDefs_ProfileView(
          did: FormatString<DID>(rawValue: $0),
          handle: FormatString<Handle>(rawValue: $0.replacingOccurrences(of: "did:plc:", with: "")),
          viewer: App.Bsky.ActorDefs_ViewerState(
            activitySubscription: App.Bsky.NotificationDefs_ActivitySubscription(
              post: true, reply: false))
        )
      }
    )
  }

  /// The list query pages and flattens, keyed by DID.
  @Test func listsSubscriptions() async throws {
    let client = FakeNotificationClient()
    client.subscriptions[nil] = subscriptionsPage([Fixtures.aliceDid], cursor: "c1")
    client.subscriptions["c1"] = subscriptionsPage([Fixtures.bobDid], cursor: nil)

    let api = ActivitySubscriptionsAPI(client: client)
    let query = api.query(store: makeStore())

    try await query.loadFirstPage()
    try await query.loadMore()

    let all = await query.items()
    #expect(all.count == 2)
    #expect(all.map(\.did.rawValue) == [Fixtures.aliceDid, Fixtures.bobDid])
    #expect(await query.hasNextPage() == false)
  }

  /// The key root matches the RN `RQKEY_getActivitySubscriptions`.
  @Test func keyRootMatchesRN() {
    #expect(ActivitySubscriptionsAPI(client: FakeNotificationClient()).key.keyRoot
      == "activity-subscriptions")
  }

  /// A write sends the subscription and echoes back what the server returned.
  @Test func writesSubscription() async throws {
    let client = FakeNotificationClient()
    let api = ActivitySubscriptionsAPI(client: client)

    let written = try await api.put(
      subject: Fixtures.aliceDid,
      subscription: ActivitySubscription(post: true, reply: true)
    )

    guard case .putActivitySubscription(let subject, let post, let reply) =
      client.calls(of: "putActivitySubscription").first
    else {
      Issue.record("expected a putActivitySubscription call")
      return
    }
    #expect(subject == Fixtures.aliceDid)
    #expect(post)
    #expect(reply)
    #expect(written == ActivitySubscription(post: true, reply: true))
  }

  /// A subscription with neither channel on is the unsubscribe the endpoint
  /// expects (it has no delete verb).
  @Test func emptySubscriptionIsUnsubscribe() async throws {
    let client = FakeNotificationClient()
    let api = ActivitySubscriptionsAPI(client: client)
    _ = try await api.put(
      subject: Fixtures.aliceDid,
      subscription: ActivitySubscription()
    )

    guard case .putActivitySubscription(_, let post, let reply) =
      client.calls(of: "putActivitySubscription").first
    else {
      Issue.record("expected a putActivitySubscription call")
      return
    }
    #expect(!post)
    #expect(!reply)
    #expect(ActivitySubscription().isEmpty)
  }

  /// The subscription on a profile's viewer state is read back.
  @Test func readsSubscriptionFromViewerState() {
    let viewer = App.Bsky.ActorDefs_ViewerState(
      activitySubscription: App.Bsky.NotificationDefs_ActivitySubscription(
        post: true, reply: false))
    #expect(ActivitySubscription.from(viewer) == ActivitySubscription(post: true, reply: false))
    #expect(ActivitySubscription.from(nil) == nil)
  }

  /// The subscribed DIDs are collected across pages.
  @Test func collectsSubscribedDids() async {
    let client = FakeNotificationClient()
    client.subscriptions[nil] = subscriptionsPage([Fixtures.aliceDid], cursor: nil)
    let api = ActivitySubscriptionsAPI(client: client)

    let dids = await api.subscribedDids(store: makeStore())
    #expect(dids == [Fixtures.aliceDid])
  }
}

/// Notification settings: the v2 preferences read and patch write.
@Suite("Notification settings")
struct NotificationSettingsTests {
  private func defaults() -> App.Bsky.NotificationDefs_Preferences {
    App.Bsky.NotificationDefs_Preferences(
      chat: App.Bsky.NotificationDefs_ChatPreference(
        include: .all, push: true),
      follow: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      like: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: false),
      likeViaRepost: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: false),
      mention: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      quote: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      reply: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      repost: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      repostViaRepost: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: false),
      starterpackJoined: App.Bsky.NotificationDefs_Preference(list: false, push: true),
      subscribedPost: App.Bsky.NotificationDefs_Preference(list: true, push: true),
      unverified: App.Bsky.NotificationDefs_Preference(list: true, push: false),
      verified: App.Bsky.NotificationDefs_Preference(list: true, push: false)
    )
  }

  /// The settings key root matches the RN `RQKEY_APP`.
  @Test func keyRootMatchesRN() {
    #expect(NotificationSettingsAPI(client: FakeNotificationClient()).key.keyRoot
      == "notification-settings-app")
  }

  /// Reading returns the preferences the server sent.
  @Test func readsPreferences() async throws {
    let client = FakeNotificationClient()
    client.notificationPreferences = defaults()
    let store = QueryStore(clock: ManualQueryClock())
    let api = NotificationSettingsAPI(client: client)

    let prefs = try await api.fetch(store: store)
    #expect(prefs.like.list)
    #expect(!prefs.like.push)
    #expect(client.calls(of: "getNotificationPreferences").count == 1)

    // A second read is served from the cache within the stale window.
    _ = try await api.fetch(store: store)
    #expect(client.calls(of: "getNotificationPreferences").count == 1)
  }

  /// A patch merges into the current preferences and writes the whole value.
  @Test func patchWritesMergedPreferences() async throws {
    let client = FakeNotificationClient()
    client.notificationPreferences = defaults()
    client.putPreferencesResult = defaults()
    let store = QueryStore(clock: ManualQueryClock())
    let api = NotificationSettingsAPI(client: client)

    var patch = NotificationSettingsPatch()
    patch.like = App.Bsky.NotificationDefs_FilterablePreference(
      include: .all, list: false, push: false)
    #expect(!patch.isEmpty)

    _ = try await api.update(store: store, patch)
    #expect(client.calls(of: "putNotificationPreferences").count == 1)
  }

  /// An empty patch changes nothing.
  @Test func emptyPatch() {
    #expect(NotificationSettingsPatch().isEmpty)
  }

  /// The patch only touches the fields it sets.
  @Test func patchAppliesOnlySetFields() {
    var prefs = defaults()
    var patch = NotificationSettingsPatch()
    patch.reply = App.Bsky.NotificationDefs_FilterablePreference(
      include: .all, list: false, push: false)
    patch.apply(to: &prefs)

    #expect(!prefs.reply.list)
    // Untouched fields are preserved.
    #expect(prefs.like.list)
    #expect(prefs.follow.push)
  }

  /// The convenience preference constants exist for the common on/off cases.
  @Test func preferenceConstants() {
    #expect(App.Bsky.NotificationDefs_Preference.enabled.list)
    #expect(App.Bsky.NotificationDefs_Preference.enabled.push)
    #expect(!App.Bsky.NotificationDefs_Preference.disabled.list)
  }
}
