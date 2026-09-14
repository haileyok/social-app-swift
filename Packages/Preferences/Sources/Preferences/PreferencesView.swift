import Foundation

import Lexicons
import SwiftAtproto

/// A feed view preference (per-feed, keyed by the feed identifier).
public struct FeedViewPreference: Sendable, Hashable {
  public var feed: String
  public var hideReplies: Bool
  public var hideRepliesByUnfollowed: Bool
  public var hideRepliesByLikeCount: Int
  public var hideReposts: Bool
  public var hideQuotePosts: Bool
  /// Experimental field some clients still carry; absent when unset.
  public var lab_mergeFeedEnabled: Bool?

  public init(
    feed: String,
    hideReplies: Bool = false,
    hideRepliesByUnfollowed: Bool = true,
    hideRepliesByLikeCount: Int = 0,
    hideReposts: Bool = false,
    hideQuotePosts: Bool = false,
    lab_mergeFeedEnabled: Bool? = nil
  ) {
    self.feed = feed
    self.hideReplies = hideReplies
    self.hideRepliesByUnfollowed = hideRepliesByUnfollowed
    self.hideRepliesByLikeCount = hideRepliesByLikeCount
    self.hideReposts = hideReposts
    self.hideQuotePosts = hideQuotePosts
    self.lab_mergeFeedEnabled = lab_mergeFeedEnabled
  }
}

/// Thread view preferences.
public struct ThreadViewPreference: Sendable, Hashable {
  public var sort: String
  /// Experimental field some clients still carry; absent when unset.
  public var lab_treeViewEnabled: Bool?

  public init(sort: String = PreferencesDefaults.threadViewSort, lab_treeViewEnabled: Bool? = nil) {
    self.sort = sort
    self.lab_treeViewEnabled = lab_treeViewEnabled
  }
}

/// A labeler entry with its label-specific overrides.
public struct LabelerPreference: Sendable, Hashable {
  public var did: String
  public var labels: [String: LabelPreference]

  public init(did: String, labels: [String: LabelPreference] = [:]) {
    self.did = did
    self.labels = labels
  }
}

/// Moderation-relevant preferences.
public struct ModerationPreferences: Sendable {
  public var adultContentEnabled: Bool
  /// Global label visibility, seeded from the defaults then overridden by
  /// stored (remapped) prefs.
  public var labels: [String: LabelPreference]
  public var labelers: [LabelerPreference]
  public var mutedWords: [PrefObject]
  public var hiddenPosts: [String]
}

/// A new user experience record the app has stored.
public typealias NuxRecord = PrefObject

/// bsky.app-specific state.
public struct BskyAppState: Sendable {
  public var queuedNudges: [String]
  public var activeProgressGuide: PrefObject?
  public var nuxs: [PrefObject]
  /// Only present when the pref set it.
  public var isBetaUser: Bool?
}

/// Live-event preferences.
public struct LiveEventPreferences: Sendable {
  public var hiddenFeedIds: [String]
  public var hideAllFeeds: Bool
}

/// The legacy v1 saved-feed arrays (deprecated; kept for the v1 preference).
public struct LegacyFeeds: Sendable {
  public var saved: [String]
  public var pinned: [String]

  public init(saved: [String] = [], pinned: [String] = []) {
    self.saved = saved
    self.pinned = pinned
  }
}

/// The interpreted preferences the app consumes (port of the SDK's
/// `BskyPreferences`).
public struct Preferences: Sendable {
  /// @deprecated use `savedFeeds`
  public var feeds: LegacyFeeds
  public var savedFeeds: [PrefObject]
  public var feedViewPrefs: [String: FeedViewPreference]
  public var threadViewPrefs: ThreadViewPreference
  public var moderationPrefs: ModerationPreferences
  public var birthDate: Date?
  public var declaredAge: PrefObject?
  public var interests: [String]
  public var bskyAppState: BskyAppState
  public var postInteractionSettings: PrefObject?
  public var verificationPrefs: PrefObject
  public var liveEventPreferences: LiveEventPreferences

  /// The raw array the view was derived from, retained so callers that need to
  /// write back do not refetch.
  public var raw: PreferencesArray
}

/// Thrown when a typed field could not be read out of the stored records.
public struct PreferencesDecodingError: Error, Sendable {
  public let message: String
  public init(_ message: String) {
    self.message = message
  }
}
