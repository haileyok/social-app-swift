import Foundation

import Lexicons
import SwiftAtproto

/// Input for creating a muted word (no `id`; the server-facing identity is
/// minted on write).
public struct MutedWordInput: Sendable {
  public var value: String
  public var targets: [String]
  public var actorTarget: String?
  public var expiresAt: FormatString<Date>?

  public init(
    value: String, targets: [String] = [], actorTarget: String? = nil,
    expiresAt: FormatString<Date>? = nil
  ) {
    self.value = value
    self.targets = targets
    self.actorTarget = actorTarget
    self.expiresAt = expiresAt
  }
}

/// Input for creating a saved feed (no `id`; minted on write).
public struct SavedFeedInput: Sendable {
  public var type: String
  public var value: String
  public var pinned: Bool

  public init(type: String, value: String, pinned: Bool) {
    self.type = type
    self.value = value
    self.pinned = pinned
  }
}

/// A partial update to a feed view preference. Only non-nil fields are merged,
/// mirroring a TypeScript object spread.
public struct FeedViewPrefPatch: Sendable {
  public var hideReplies: Bool?
  public var hideRepliesByUnfollowed: Bool?
  public var hideRepliesByLikeCount: Int?
  public var hideReposts: Bool?
  public var hideQuotePosts: Bool?
  public var lab_mergeFeedEnabled: Bool?

  public init(
    hideReplies: Bool? = nil, hideRepliesByUnfollowed: Bool? = nil,
    hideRepliesByLikeCount: Int? = nil, hideReposts: Bool? = nil,
    hideQuotePosts: Bool? = nil, lab_mergeFeedEnabled: Bool? = nil
  ) {
    self.hideReplies = hideReplies
    self.hideRepliesByUnfollowed = hideRepliesByUnfollowed
    self.hideRepliesByLikeCount = hideRepliesByLikeCount
    self.hideReposts = hideReposts
    self.hideQuotePosts = hideQuotePosts
    self.lab_mergeFeedEnabled = lab_mergeFeedEnabled
  }

  /// The fields to merge, by wire name.
  var fields: [String: JSONValue] {
    var out: [String: JSONValue] = [:]
    if let hideReplies { out["hideReplies"] = JSONValue(hideReplies) }
    if let hideRepliesByUnfollowed {
      out["hideRepliesByUnfollowed"] = JSONValue(hideRepliesByUnfollowed)
    }
    if let hideRepliesByLikeCount {
      out["hideRepliesByLikeCount"] = JSONValue(hideRepliesByLikeCount)
    }
    if let hideReposts { out["hideReposts"] = JSONValue(hideReposts) }
    if let hideQuotePosts { out["hideQuotePosts"] = JSONValue(hideQuotePosts) }
    if let lab_mergeFeedEnabled {
      out["lab_mergeFeedEnabled"] = JSONValue(lab_mergeFeedEnabled)
    }
    return out
  }
}

/// A partial update to the thread view preference.
public struct ThreadViewPrefPatch: Sendable {
  public var sort: String?
  public var lab_treeViewEnabled: Bool?

  public init(sort: String? = nil, lab_treeViewEnabled: Bool? = nil) {
    self.sort = sort
    self.lab_treeViewEnabled = lab_treeViewEnabled
  }

  var fields: [String: JSONValue] {
    var out: [String: JSONValue] = [:]
    if let sort { out["sort"] = JSONValue(sort) }
    if let lab_treeViewEnabled { out["lab_treeViewEnabled"] = JSONValue(lab_treeViewEnabled) }
    return out
  }
}

/// Default post-interaction settings. Both fields are assigned explicitly;
/// `nil` means "absent", which the app reads as "everyone".
public struct PostInteractionSettings: Sendable {
  public var threadgateAllowRules: [PrefObject]?
  public var postgateEmbeddingRules: [PrefObject]?

  public init(
    threadgateAllowRules: [PrefObject]? = nil,
    postgateEmbeddingRules: [PrefObject]? = nil
  ) {
    self.threadgateAllowRules = threadgateAllowRules
    self.postgateEmbeddingRules = postgateEmbeddingRules
  }
}

/// A partial update to verification preferences.
public struct VerificationPrefsPatch: Sendable {
  public var hideBadges: Bool?

  public init(hideBadges: Bool? = nil) {
    self.hideBadges = hideBadges
  }
}

/// A live-event preference change.
public enum LiveEventAction: Sendable {
  case hideFeed(id: String)
  case unhideFeed(id: String)
  case toggleHideAllFeeds
}

/// One typed preference mutation.
///
/// Each case reproduces the patch one `@bsky/sdk` action applies to the raw
/// preference array. `apply` returns nil to skip the write, mirroring the
/// SDK's `update: prefs => false`.
public enum PreferencesAction: Sendable {
  case setAdultContentEnabled(Bool)
  case setContentLabelPref(key: String, value: LabelPreference, labelerDid: String?)
  /// Feeds already carry their minted `id`.
  case addSavedFeeds([PrefObject])
  case removeSavedFeeds(ids: [String])
  case updateSavedFeeds([PrefObject])
  case overwriteSavedFeeds([PrefObject])
  case addPinnedFeed(uri: String)
  case removePinnedFeed(uri: String)
  case setFeedViewPrefs(feed: String, patch: FeedViewPrefPatch)
  case setThreadViewPrefs(ThreadViewPrefPatch)
  case setPersonalDetails(birthDate: FormatString<Date>?)
  case setInterestsPref(tags: [String])
  case addMutedWord(MutedWordInput)
  case updateMutedWord(PrefObject)
  case removeMutedWord(PrefObject)
  case hidePost(uri: String)
  case unhidePost(uri: String)
  case addLabeler(did: String)
  case removeLabeler(did: String)
  case queueNudges([String])
  case dismissNudges([String])
  case setIsBetaUser(Bool)
  case setActiveProgressGuide(PrefObject?)
  case upsertNux(nux: PrefObject)
  case removeNuxs([String])
  case setVerificationPrefs(VerificationPrefsPatch)
  case setPostInteractionSettings(PostInteractionSettings)
  case updateLiveEventPreferences(LiveEventAction)
}

extension PreferencesAction {
  /// The patch this action applies. Throws when the input fails validation.
  ///
  /// Dispatch is a chain of thematic groups rather than one flat switch: each
  /// group covers a disjoint set of cases and returns nil for the rest, which
  /// keeps each function small enough to review on its own.
  public func patch(tids: TidGenerator) throws -> PreferencesUpdate {
    if let update = try moderationPatch(tids: tids) { return update }
    if let update = try savedFeedsPatch(tids: tids) { return update }
    if let update = try viewPatch() { return update }
    if let update = try profilePatch() { return update }
    if let update = try appStatePatch(tids: tids) { return update }
    if let update = try miscPatch() { return update }
    // Every case is claimed by exactly one group above.
    throw PreferencesError(.missingType)
  }
}
