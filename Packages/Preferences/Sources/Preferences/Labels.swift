import Foundation

/// Label-visibility setting stored in a `contentLabelPref`.
public typealias LabelPreference = String

/// Moderation label constants ported from `@bsky/sdk/moderation/const/labels`.
public enum ModerationLabels {
  /// Default visibility for the app's global labels.
  public static let defaultLabelSettings: [String: LabelPreference] = [
    "porn": "hide",
    "sexual": "warn",
    "nudity": "ignore",
    "graphic-media": "warn",
  ]

  /// Legacy label name -> current label name. Older clients wrote prefs under
  /// the legacy names; reads remap them forward.
  public static let labelRemap: [String: String] = [
    "nsfw": "porn",
    "gore": "graphic-media",
    "suggestive": "sexual",
  ]

  /// Current label name -> legacy aliases. `setContentLabelPref` double-writes
  /// a global label pref under each alias so older clients see the change.
  public static let labelRemapReverse: [String: [String]] = [
    "porn": ["nsfw"],
    "graphic-media": ["gore"],
    "sexual": ["suggestive"],
  ]

  /// `'show'` is a legacy visibility value remapped to `'ignore'` on read;
  /// any other unknown value passes through unchanged.
  public static func normalizeVisibility(_ visibility: LabelPreference) -> LabelPreference {
    visibility == "show" ? "ignore" : visibility
  }
}

/// Feed/thread view defaults, mirroring `#/state/queries/preferences/const`.
public enum PreferencesDefaults {
  public static let homeFeedViewPrefs: [String: JSONValue] = [
    "hideReplies": JSONValue(false),
    "hideRepliesByUnfollowed": JSONValue(true),
    "hideRepliesByLikeCount": JSONValue(0),
    "hideReposts": JSONValue(false),
    "hideQuotePosts": JSONValue(false),
  ]

  public static let threadViewSort = "hotness"
}
