import Foundation

import Lexicons
import SwiftAtproto

extension PreferencesEngine {
  // MARK: - Hydration

  /// Interprets a raw preference array, migrating v1 saved feeds to v2 on the
  /// first read (port of the SDK's `getPreferences`).
  ///
  /// When a migration runs, the migrated feeds are used for this call's result
  /// directly and the write goes through the serialized saved-feeds path, so
  /// the migration does not recur.
  func hydrate(_ raw: PreferencesArray) async throws -> Preferences {
    var array = raw
    var migratedSavedFeeds: [PrefObject]?

    let hasV2 = array.contains(PrefType.savedFeedsPrefV2)
    let v1 = array.first(PrefType.savedFeedsPref)

    if !hasV2, let v1 {
      let migrated = migrateV1SavedFeeds(v1)
      migratedSavedFeeds = migrated
      try await overwriteSavedFeedsImpl(migrated)
      // `overwriteSavedFeedsImpl` ran a read-modify-write; mirror the RN
      // behavior of using the migrated feeds as this call's result.
      array = array.removing(PrefType.savedFeedsPrefV2)
    } else if !hasV2 {
      let migrated = [
        PrefObject(fields: [
          "id": JSONValue(nextTid()),
          "type": JSONValue("timeline"),
          "value": JSONValue("following"),
          "pinned": JSONValue(true),
        ])
      ]
      migratedSavedFeeds = migrated
      try await overwriteSavedFeedsImpl(migrated)
      array = array.removing(PrefType.savedFeedsPrefV2)
    }

    return try buildView(array, migratedSavedFeeds: migratedSavedFeeds)
  }

  /// Converts a v1 `savedFeedsPref` into v2 items (port of the migration in
  /// the SDK's `getPreferences`, following `agent.ts:687-746`).
  ///
  /// Pinned is the source of truth for order: the Following timeline is first,
  /// then pinned feeds/lists in their stored order, then saved-only entries.
  /// Duplicates are dropped by URI, keeping the first occurrence's position.
  func migrateV1SavedFeeds(_ v1: PrefObject) -> [PrefObject] {
    var order: [String] = []
    var byKey: [String: PrefObject] = [:]

    func insert(key: String, _ object: PrefObject) {
      if byKey[key] == nil {
        order.append(key)
        byKey[key] = object
      }
    }

    insert(
      key: "timeline",
      PrefObject(fields: [
        "id": JSONValue(nextTid()),
        "type": JSONValue("timeline"),
        "value": JSONValue("following"),
        "pinned": JSONValue(true),
      ]))

    for uri in v1["pinned"]?.stringArrayValue ?? [] {
      guard let type = SavedFeeds.type(forUri: uri), type != "timeline" else { continue }
      insert(
        key: uri,
        PrefObject(fields: [
          "id": JSONValue(nextTid()),
          "type": JSONValue(type),
          "value": JSONValue(uri),
          "pinned": JSONValue(true),
        ]))
    }

    for uri in v1["saved"]?.stringArrayValue ?? [] {
      guard byKey[uri] == nil else { continue }
      guard let type = SavedFeeds.type(forUri: uri), type != "timeline" else { continue }
      insert(
        key: uri,
        PrefObject(fields: [
          "id": JSONValue(nextTid()),
          "type": JSONValue(type),
          "value": JSONValue(uri),
          "pinned": JSONValue(false),
        ]))
    }

    return order.compactMap { byKey[$0] }
  }

  // MARK: - View assembly

  func buildView(_ array: PreferencesArray, migratedSavedFeeds: [PrefObject]?) throws -> Preferences {
    let v1Pref = array.first(PrefType.savedFeedsPref)
    let v2Items = try array.first(PrefType.savedFeedsPrefV2)?.objectArray("items") ?? []
    let threadViewPref = array.first(PrefType.threadViewPref)

    return Preferences(
      feeds: LegacyFeeds(
        saved: v1Pref?["saved"]?.stringArrayValue ?? [],
        pinned: v1Pref?["pinned"]?.stringArrayValue ?? []),
      savedFeeds: migratedSavedFeeds ?? v2Items,
      feedViewPrefs: Self.feedViewPrefs(from: array),
      threadViewPrefs: ThreadViewPreference(
        sort: threadViewPref?["sort"]?.stringValue ?? PreferencesDefaults.threadViewSort,
        lab_treeViewEnabled: threadViewPref?["lab_treeViewEnabled"]?.boolValue),
      moderationPrefs: ModerationPreferences(
        adultContentEnabled: array.first(PrefType.adultContentPref)?["enabled"]?.boolValue
          ?? false,
        labels: Self.globalLabels(from: array),
        labelers: try Self.labelers(from: array),
        mutedWords: try Self.mutedWords(from: array),
        hiddenPosts: array.first(PrefType.hiddenPostsPref)?["items"]?.stringArrayValue ?? []),
      birthDate: array.first(PrefType.personalDetailsPref)?["birthDate"]?
        .decoded(as: FormatString<Date>.self)?.typed,
      declaredAge: array.first(PrefType.declaredAgePref),
      interests: array.first(PrefType.interestsPref)?["tags"]?.stringArrayValue ?? [],
      bskyAppState: try Self.appState(from: array),
      postInteractionSettings: array.first(PrefType.postInteractionSettingsPref),
      verificationPrefs: array.first(PrefType.verificationPrefs)
        ?? PrefObject(fields: [
          "$type": JSONValue(PrefType.verificationPrefs),
          "hideBadges": JSONValue(false),
        ]),
      liveEventPreferences: Self.liveEventPreferences(from: array),
      raw: array)
  }

  // MARK: - View parts

  /// Global label map: defaults first, then stored (remapped) overrides.
  static func globalLabels(from array: PreferencesArray) -> [String: LabelPreference] {
    var labels = ModerationLabels.defaultLabelSettings
    for pref in array.all(PrefType.contentLabelPref) where pref["labelerDid"] == nil {
      let visibility = ModerationLabels.normalizeVisibility(
        pref["visibility"]?.stringValue ?? "")
      let stored = pref["label"]?.stringValue ?? ""
      labels[ModerationLabels.labelRemap[stored] ?? stored] = visibility
      // Also set the original legacy name when it was remapped.
      if ModerationLabels.labelRemap[stored] != nil {
        labels[stored] = visibility
      }
    }
    return labels
  }

  /// Feed view prefs keyed by feed id, with a default `home` entry.
  static func feedViewPrefs(from array: PreferencesArray) -> [String: FeedViewPreference] {
    var prefs: [String: FeedViewPreference] = [:]
    for pref in array.all(PrefType.feedViewPref) {
      guard let feed = pref["feed"]?.stringValue else { continue }
      prefs[feed] = FeedViewPreference(
        feed: feed,
        hideReplies: pref["hideReplies"]?.boolValue ?? false,
        hideRepliesByUnfollowed: pref["hideRepliesByUnfollowed"]?.boolValue ?? true,
        hideRepliesByLikeCount: pref["hideRepliesByLikeCount"]?.intValue ?? 0,
        hideReposts: pref["hideReposts"]?.boolValue ?? false,
        hideQuotePosts: pref["hideQuotePosts"]?.boolValue ?? false,
        lab_mergeFeedEnabled: pref["lab_mergeFeedEnabled"]?.boolValue)
    }
    if prefs["home"] == nil {
      prefs["home"] = FeedViewPreference(feed: "home")
    }
    return prefs
  }

  /// Muted words, with `actorTarget` defaulted to `all` when unset.
  static func mutedWords(from array: PreferencesArray) throws -> [PrefObject] {
    try (array.first(PrefType.mutedWordsPref)?.objectArray("items") ?? []).map { item in
      var copy = item
      if copy["actorTarget"] == nil {
        copy.set("actorTarget", "all")
      }
      return copy
    }
  }

  /// The app's labelers plus the user's, with per-labeler label overrides.
  static func labelers(from array: PreferencesArray) throws -> [LabelerPreference] {
    var order: [String] = []
    var labels: [String: [String: LabelPreference]] = [:]

    func register(_ did: String) {
      guard labels[did] == nil else { return }
      order.append(did)
      labels[did] = [:]
    }

    register(BlueskyModerationLabeler.did)
    for item in try array.first(PrefType.labelersPref)?.objectArray("labelers") ?? [] {
      guard let did = item["did"]?.stringValue else { continue }
      register(did)
    }
    for pref in array.all(PrefType.contentLabelPref) {
      guard let did = pref["labelerDid"]?.stringValue, labels[did] != nil else { continue }
      labels[did]?[pref["label"]?.stringValue ?? ""] =
        ModerationLabels.normalizeVisibility(pref["visibility"]?.stringValue ?? "")
    }
    return order.map { LabelerPreference(did: $0, labels: labels[$0] ?? [:]) }
  }

  static func appState(from array: PreferencesArray) throws -> BskyAppState {
    let pref = array.first(PrefType.bskyAppStatePref)
    return BskyAppState(
      queuedNudges: pref?["queuedNudges"]?.stringArrayValue ?? [],
      activeProgressGuide: pref?["activeProgressGuide"]?.objectValue.map(PrefObject.init(fields:)),
      nuxs: try pref?.objectArray("nuxs") ?? [],
      isBetaUser: pref?["isBetaUser"]?.boolValue)
  }

  static func liveEventPreferences(from array: PreferencesArray) -> LiveEventPreferences {
    let pref = array.first(PrefType.liveEventPreferences)
    return LiveEventPreferences(
      hiddenFeedIds: pref?["hiddenFeedIds"]?.stringArrayValue ?? [],
      hideAllFeeds: pref?["hideAllFeeds"]?.boolValue ?? false)
  }
}

/// The Bluesky moderation authority, always an app labeler.
public enum BlueskyModerationLabeler {
  public static let did = "did:plc:ar7c4by46qjdydhdevvrndac"
}
