import Foundation

import Lexicons
import QueryStore

public struct NotificationSettingsAPI: Sendable {
  /// The client every request goes through.
  public let client: NotificationClient
  /// Account scope for key identity.
  public let scope: String?

  public init(client: NotificationClient, scope: String? = nil) {
    self.client = client
    self.scope = scope
  }

  /// The settings key, matching `RQKEY_APP`.
  public var key: QueryKey {
    NotificationQueryKey.settings(scope: scope)
  }

  /// Fetches the app's notification preferences.
  ///
  /// The chat member the server returns is left in place; a caller that wants
  /// it removed can drop it, but keeping it faithful to the wire is the safer
  /// default.
  public func fetch(store: QueryStore) async throws -> App.Bsky.NotificationDefs_Preferences {
    try await store.fetch(key, staleTime: STALE.MINUTES.FIVE) { [client] in
      try await client.getNotificationPreferences().preferences
    }
  }

  /// Applies a patch, returning the preferences the server reports back.
  ///
  /// The port of `useNotificationSettingsUpdateMutation`. The server's
  /// response is the new truth and replaces the cached value, matching the RN
  /// mutation's invalidate-on-error / trust-the-response posture without the
  /// optimistic write (the views package owns optimistic UI).
  @discardableResult
  public func update(
    store: QueryStore,
    _ patch: NotificationSettingsPatch
  ) async throws -> App.Bsky.NotificationDefs_Preferences {
    var current = try await fetch(store: store)
    patch.apply(to: &current)
    let output = try await client.putNotificationPreferences(current)
    await store.setQueryData(
      output.preferences, for: key, persist: false)
    return output.preferences
  }
}

/// A partial update to the app's notification preferences.
///
/// Every field is optional, so a caller sends only what changed. This mirrors
/// `putPreferencesV2`'s own patch-shaped input rather than the full
/// `Preferences` record.
public struct NotificationSettingsPatch: Sendable, Hashable {
  public var follow: App.Bsky.NotificationDefs_FilterablePreference?
  public var like: App.Bsky.NotificationDefs_FilterablePreference?
  public var likeViaRepost: App.Bsky.NotificationDefs_FilterablePreference?
  public var mention: App.Bsky.NotificationDefs_FilterablePreference?
  public var quote: App.Bsky.NotificationDefs_FilterablePreference?
  public var reply: App.Bsky.NotificationDefs_FilterablePreference?
  public var repost: App.Bsky.NotificationDefs_FilterablePreference?
  public var repostViaRepost: App.Bsky.NotificationDefs_FilterablePreference?
  public var starterpackJoined: App.Bsky.NotificationDefs_Preference?
  public var subscribedPost: App.Bsky.NotificationDefs_Preference?
  public var unverified: App.Bsky.NotificationDefs_Preference?
  public var verified: App.Bsky.NotificationDefs_Preference?

  public init(
    follow: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    like: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    likeViaRepost: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    mention: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    quote: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    reply: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    repost: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    repostViaRepost: App.Bsky.NotificationDefs_FilterablePreference? = nil,
    starterpackJoined: App.Bsky.NotificationDefs_Preference? = nil,
    subscribedPost: App.Bsky.NotificationDefs_Preference? = nil,
    unverified: App.Bsky.NotificationDefs_Preference? = nil,
    verified: App.Bsky.NotificationDefs_Preference? = nil
  ) {
    self.follow = follow
    self.like = like
    self.likeViaRepost = likeViaRepost
    self.mention = mention
    self.quote = quote
    self.reply = reply
    self.repost = repost
    self.repostViaRepost = repostViaRepost
    self.starterpackJoined = starterpackJoined
    self.subscribedPost = subscribedPost
    self.unverified = unverified
    self.verified = verified
  }

  /// True when the patch would change nothing, in which case the RN mutation
  /// skips the request entirely.
  public var isEmpty: Bool {
    follow == nil && like == nil && likeViaRepost == nil && mention == nil
      && quote == nil && reply == nil && repost == nil && repostViaRepost == nil
      && starterpackJoined == nil && subscribedPost == nil && unverified == nil
      && verified == nil
  }

  /// Merges the patch into a preferences value, leaving unset fields alone.
  public func apply(to preferences: inout App.Bsky.NotificationDefs_Preferences) {
    if let follow { preferences.follow = follow }
    if let like { preferences.like = like }
    if let likeViaRepost { preferences.likeViaRepost = likeViaRepost }
    if let mention { preferences.mention = mention }
    if let quote { preferences.quote = quote }
    if let reply { preferences.reply = reply }
    if let repost { preferences.repost = repost }
    if let repostViaRepost { preferences.repostViaRepost = repostViaRepost }
    if let starterpackJoined { preferences.starterpackJoined = starterpackJoined }
    if let subscribedPost { preferences.subscribedPost = subscribedPost }
    if let unverified { preferences.unverified = unverified }
    if let verified { preferences.verified = verified }
  }
}

extension App.Bsky.NotificationDefs_Preference {
  /// The lexicon default: listed, pushed.
  public static let enabled = App.Bsky.NotificationDefs_Preference(list: true, push: true)
  /// Off entirely.
  public static let disabled = App.Bsky.NotificationDefs_Preference(list: false, push: false)
}
