import Foundation

import Lexicons
import SwiftAtproto

/// The typed preference API.
///
/// Each method maps to one `@bsky/sdk` action and applies the same patch to
/// the raw preference array. Writes go through ``PreferencesEngine/update(_:)``
/// so they are serialized against other preference writes.
extension PreferencesEngine {

  // MARK: - Moderation

  /// `setAdultContentEnabled`
  public func setAdultContentEnabled(_ enabled: Bool) async throws {
    try await submit(.setAdultContentEnabled(enabled))
  }

  /// `setContentLabelPref`
  public func setContentLabelPref(
    key: String, value: LabelPreference, labelerDid: String? = nil
  ) async throws {
    try await submit(
      .setContentLabelPref(key: key, value: value, labelerDid: labelerDid))
  }

  /// `addLabeler`
  public func addLabeler(_ did: String) async throws {
    try await submit(.addLabeler(did: did))
  }

  /// `removeLabeler`
  public func removeLabeler(_ did: String) async throws {
    try await submit(.removeLabeler(did: did))
  }

  /// `hidePost`
  public func hidePost(_ uri: String) async throws {
    try await submit(.hidePost(uri: uri))
  }

  /// `unhidePost`
  public func unhidePost(_ uri: String) async throws {
    try await submit(.unhidePost(uri: uri))
  }

  // MARK: - Saved feeds

  /// `addSavedFeeds`: mints ids for each feed and appends it.
  @discardableResult
  public func addSavedFeeds(_ feeds: [SavedFeedInput]) async throws -> [PrefObject] {
    let newFeeds = feeds.map { feed in
      PrefObject(fields: [
        "id": JSONValue(nextTid()),
        "type": JSONValue(feed.type),
        "value": JSONValue(feed.value),
        "pinned": JSONValue(feed.pinned),
      ])
    }
    try newFeeds.forEach(SavedFeeds.validate)
    try await submit(.addSavedFeeds(newFeeds))
    return newFeeds
  }

  /// `removeSavedFeeds`
  public func removeSavedFeeds(_ ids: [String]) async throws {
    try await submit(.removeSavedFeeds(ids: ids))
  }

  /// `updateSavedFeeds`: only `pinned` is updated.
  public func updateSavedFeeds(_ feeds: [PrefObject]) async throws {
    try await submit(.updateSavedFeeds(feeds))
  }

  /// `overwriteSavedFeeds`: replaces the whole v2 list, deduping by id.
  public func overwriteSavedFeeds(_ feeds: [PrefObject]) async throws {
    try await submit(.overwriteSavedFeeds(feeds))
  }

  /// `addPinnedFeed` (deprecated)
  public func addPinnedFeed(_ uri: String) async throws {
    try await submit(.addPinnedFeed(uri: uri))
  }

  /// `removePinnedFeed` (deprecated)
  public func removePinnedFeed(_ uri: String) async throws {
    try await submit(.removePinnedFeed(uri: uri))
  }

  // MARK: - Views

  /// `setFeedViewPrefs`
  public func setFeedViewPrefs(feed: String, patch: FeedViewPrefPatch) async throws {
    try await submit(.setFeedViewPrefs(feed: feed, patch: patch))
  }

  /// `setThreadViewPrefs`
  public func setThreadViewPrefs(_ patch: ThreadViewPrefPatch) async throws {
    try await submit(.setThreadViewPrefs(patch))
  }

  // MARK: - Profile / interests

  /// `setPersonalDetails`
  public func setPersonalDetails(_ birthDate: Date?) async throws {
    try await submit(
      .setPersonalDetails(
        birthDate: birthDate.map { FormatString<Date>(rawValue: $0.rawValue) }))
  }

  /// `setInterestsPref`
  public func setInterestsPref(tags: [String]) async throws {
    try await submit(.setInterestsPref(tags: tags))
  }

  // MARK: - Muted words

  /// `addMutedWord`
  public func addMutedWord(_ input: MutedWordInput) async throws {
    try await submit(.addMutedWord(input))
  }

  /// `addMutedWords`
  public func addMutedWords(_ words: [MutedWordInput]) async throws {
    for word in words {
      try await addMutedWord(word)
    }
  }

  /// `upsertMutedWords` (deprecated; alias of `addMutedWords`)
  public func upsertMutedWords(_ words: [MutedWordInput]) async throws {
    try await addMutedWords(words)
  }

  /// `updateMutedWord`
  public func updateMutedWord(_ mutedWord: PrefObject) async throws {
    try await submit(.updateMutedWord(mutedWord))
  }

  /// `removeMutedWord`
  public func removeMutedWord(_ mutedWord: PrefObject) async throws {
    try await submit(.removeMutedWord(mutedWord))
  }

  /// `removeMutedWords`
  public func removeMutedWords(_ words: [PrefObject]) async throws {
    for word in words {
      try await removeMutedWord(word)
    }
  }

  // MARK: - App state

  /// `queueNudges`
  public func queueNudges(_ nudges: [String]) async throws {
    try await submit(.queueNudges(nudges))
  }

  /// `dismissNudges`
  public func dismissNudges(_ nudges: [String]) async throws {
    try await submit(.dismissNudges(nudges))
  }

  /// `setIsBetaUser`
  public func setIsBetaUser(_ isBetaUser: Bool) async throws {
    try await submit(.setIsBetaUser(isBetaUser))
  }

  /// `setActiveProgressGuide`
  public func setActiveProgressGuide(_ guide: String?) async throws {
    if let guide {
      try await submit(.setActiveProgressGuide(PrefObject(fields: ["guide": JSONValue(guide)])))
    } else {
      try await submit(.setActiveProgressGuide(nil))
    }
  }

  /// `upsertNux`
  public func upsertNux(_ nux: PrefObject) async throws {
    try await submit(.upsertNux(nux: nux))
  }

  /// `removeNuxs`
  public func removeNuxs(_ ids: [String]) async throws {
    try await submit(.removeNuxs(ids))
  }

  // MARK: - Other prefs

  /// `setVerificationPrefs`
  public func setVerificationPrefs(_ patch: VerificationPrefsPatch) async throws {
    try await submit(.setVerificationPrefs(patch))
  }

  /// `setPostInteractionSettings`
  public func setPostInteractionSettings(_ settings: PostInteractionSettings) async throws {
    try await submit(.setPostInteractionSettings(settings))
  }

  /// `updateLiveEventPreferences`
  public func updateLiveEventPreferences(_ action: LiveEventAction) async throws {
    try await submit(.updateLiveEventPreferences(action))
  }

  // MARK: - Notification timestamp (separate endpoint)

  /// `updateSeenNotifications`: marks notifications seen up to `seenAt`
  /// (defaults to now). This is its own endpoint, not a preference write.
  public func updateSeenNotifications(_ seenAt: Date? = nil) async throws {
    let input = App.Bsky.NotificationUpdateSeen_Input(
      seenAt: FormatString<Date>(rawValue: (seenAt ?? Date()).rawValue))
    let _: EmptyResponse = try await client.procedure(
      "app.bsky.notification.updateSeen", body: input,
      authorization: try await authorization())
  }

  // MARK: - Internal

  /// Runs an action's patch through the serialized read-modify-write path.
  @discardableResult
  func submit(_ action: PreferencesAction) async throws -> UpdateResult {
    let patch = try action.patch(tids: currentTidGenerator)
    return try await update(patch)
  }

  /// Implements `overwriteSavedFeedsImpl`: dedupe by id and write, routed
  /// through the serialized saved-feeds path.
  func overwriteSavedFeedsImpl(_ feeds: [PrefObject]) async throws {
    try await submit(.overwriteSavedFeeds(feeds))
  }
}
