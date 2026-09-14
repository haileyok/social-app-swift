import Foundation

import Lexicons
import SwiftAtproto

/// The thematic groups ``PreferencesAction/patch(tids:)`` dispatches over.
///
/// Each group returns nil for the cases it does not own, so the chain in
/// `patch` covers the enum exactly once.
extension PreferencesAction {

  // MARK: - Moderation

  /// Adult content, content labels, labelers, hidden posts.
  func moderationPatch(tids: TidGenerator) throws -> PreferencesUpdate? {
    switch self {
    case .setAdultContentEnabled(let enabled):
      return { prefs in
        Self.replaceInPlace(prefs, PrefType.adultContentPref, Self.upsert(
          prefs.first(PrefType.adultContentPref), PrefType.adultContentPref) { record in
            record.set("enabled", enabled)
          })
      }

    case .setContentLabelPref(let key, let value, let labelerDid):
      if let labelerDid { try DIDValidation.validate(labelerDid) }
      return { prefs in
        Self.setContentLabelPref(prefs, key: key, value: value, labelerDid: labelerDid)
      }

    case .hidePost(let uri):
      return { prefs in
        let existing = prefs.first(PrefType.hiddenPostsPref)
        let current = existing?["items"]?.stringArrayValue ?? []
        guard !current.contains(uri) else { return nil }
        return Self.replaceInPlace(prefs, PrefType.hiddenPostsPref, Self.upsert(
          existing, PrefType.hiddenPostsPref) { record in
            record.set("items", current + [uri])
          })
      }

    case .unhidePost(let uri):
      return { prefs in
        guard let existing = prefs.first(PrefType.hiddenPostsPref) else { return nil }
        return Self.replaceInPlace(prefs, PrefType.hiddenPostsPref, Self.upsert(
          existing, PrefType.hiddenPostsPref) { record in
            record.set("items", (existing["items"]?.stringArrayValue ?? []).filter { $0 != uri })
          })
      }

    default:
      return try labelerPatch()
    }
  }

  /// Labeler subscriptions.
  func labelerPatch() throws -> PreferencesUpdate? {
    switch self {
    case .addLabeler(let did):
      try DIDValidation.validate(did)
      return { prefs in
        let existing = prefs.first(PrefType.labelersPref)
        let current = try existing?.objectArray("labelers") ?? []
        guard !current.contains(where: { $0["did"]?.stringValue == did }) else { return nil }
        return Self.replaceInPlace(prefs, PrefType.labelersPref, Self.upsert(
          existing, PrefType.labelersPref) { record in
            record.setObjectArray("labelers", current + [Self.labelerItem(did: did)])
          })
      }

    case .removeLabeler(let did):
      return { prefs in
        guard let existing = prefs.first(PrefType.labelersPref) else { return nil }
        return Self.replaceInPlace(prefs, PrefType.labelersPref, try Self.upsert(
          existing, PrefType.labelersPref) { record in
            record.setObjectArray(
              "labelers",
              try existing.objectArray("labelers").filter { $0["did"]?.stringValue != did })
          })
      }

    default:
      return nil
    }
  }

  // MARK: - Saved feeds

  func savedFeedsPatch(tids: TidGenerator) throws -> PreferencesUpdate? {
    switch self {
    case .addSavedFeeds(let feeds):
      try feeds.forEach(SavedFeeds.validate)
      return { prefs in
        try Self.updateSavedFeedsV2(prefs) { items in items + feeds }
      }

    case .removeSavedFeeds(let ids):
      return { prefs in
        try Self.updateSavedFeedsV2(prefs) { items in
          items.filter { item in
            guard let id = item["id"]?.stringValue else { return true }
            return !ids.contains(id)
          }
        }
      }

    case .updateSavedFeeds(let updates):
      try updates.forEach(SavedFeeds.validate)
      return { prefs in
        try Self.updateSavedFeedsV2(prefs) { items in
          items.map { item -> PrefObject in
            guard let id = item["id"]?.stringValue,
              let updated = updates.first(where: { $0["id"]?.stringValue == id })
            else { return item }
            // Only `pinned` is updated.
            var copy = item
            copy.set("pinned", updated["pinned"]?.boolValue ?? false)
            return copy
          }
        }
      }

    case .overwriteSavedFeeds(let feeds):
      try feeds.forEach(SavedFeeds.validate)
      let unique = Self.dedupeByLastPosition(feeds)
      return { prefs in
        try Self.updateSavedFeedsV2(prefs) { _ in unique }
      }

    default:
      return try legacySavedFeedsPatch()
    }
  }

  /// The deprecated v1 `savedFeedsPref` actions.
  func legacySavedFeedsPatch() throws -> PreferencesUpdate? {
    switch self {
    case .addPinnedFeed(let uri):
      return { prefs in
        let existing = prefs.first(PrefType.savedFeedsPref)
        let saved = existing?["saved"]?.stringArrayValue ?? []
        let pinned = existing?["pinned"]?.stringArrayValue ?? []
        return Self.replaceInPlace(prefs, PrefType.savedFeedsPref, Self.upsert(
          existing, PrefType.savedFeedsPref) { record in
            record.set("saved", saved.filter { $0 != uri } + [uri])
            record.set("pinned", pinned.filter { $0 != uri } + [uri])
          })
      }

    case .removePinnedFeed(let uri):
      return { prefs in
        guard let existing = prefs.first(PrefType.savedFeedsPref) else { return nil }
        return Self.replaceInPlace(prefs, PrefType.savedFeedsPref, Self.upsert(
          existing, PrefType.savedFeedsPref) { record in
            record.set(
              "pinned", (existing["pinned"]?.stringArrayValue ?? []).filter { $0 != uri })
          })
      }

    default:
      return nil
    }
  }

  // MARK: - Views

  func viewPatch() throws -> PreferencesUpdate? {
    switch self {
    case .setFeedViewPrefs(let feed, let patch):
      return { prefs in
        let existing = prefs.all(PrefType.feedViewPref)
          .first { $0["feed"]?.stringValue == feed }
        let merged = Self.merged(existing, PrefType.feedViewPref, patch.fields) { fields in
          fields["feed"] = JSONValue(feed)
        }
        if prefs.contains(PrefType.feedViewPref) {
          // The SDK maps every feedViewPref: entries for this feed become the
          // updated record, the rest are untouched.
          return prefs.mapping(PrefType.feedViewPref) { pref in
            pref["feed"]?.stringValue == feed ? merged : pref
          }
        }
        return prefs.appending(merged)
      }

    case .setThreadViewPrefs(let patch):
      return { prefs in
        let updated = Self.merged(
          prefs.first(PrefType.threadViewPref), PrefType.threadViewPref, patch.fields)
        if prefs.contains(PrefType.threadViewPref) {
          return prefs.mapping(PrefType.threadViewPref) { _ in updated }
        }
        return prefs.appending(updated)
      }

    default:
      return nil
    }
  }

  // MARK: - Profile / interests

  func profilePatch() throws -> PreferencesUpdate? {
    switch self {
    case .setPersonalDetails(let birthDate):
      return { prefs in
        Self.replaceInPlace(prefs, PrefType.personalDetailsPref, try Self.upsert(
          prefs.first(PrefType.personalDetailsPref), PrefType.personalDetailsPref) { record in
            Self.setOptional(&record, "birthDate", birthDate)
          })
      }

    case .setInterestsPref(let tags):
      return { prefs in
        Self.replaceInPlace(prefs, PrefType.interestsPref, try Self.upsert(
          prefs.first(PrefType.interestsPref), PrefType.interestsPref) { record in
            record.set("tags", tags)
          })
      }

    default:
      return nil
    }
  }

  // MARK: - Muted words

  func mutedWordPatch(tids: TidGenerator) throws -> PreferencesUpdate? {
    switch self {
    case .addMutedWord(let input):
      let sanitized = MutedWords.sanitize(input.value)
      guard !sanitized.isEmpty else { return { _ in nil } }
      let newWord = Self.mutedWord(
        id: tids.next(), value: sanitized, targets: input.targets,
        actorTarget: input.actorTarget ?? "all", expiresAt: input.expiresAt)
      return { prefs in
        let existing = prefs.first(PrefType.mutedWordsPref)
        var items = try existing?.objectArray("items") ?? []
        items.append(newWord)
        items = Self.migrateLegacyMutedWords(items, tids: tids)
        return Self.replaceMutedWords(prefs, existing: existing, items: items)
      }

    case .updateMutedWord(let mutedWord):
      return { prefs in
        guard let existing = prefs.first(PrefType.mutedWordsPref) else { return prefs }
        let items = try existing.objectArray("items").map { item -> PrefObject in
          guard Self.matchMutedWord(item, mutedWord) else { return item }
          var merged = item.fields
          for (key, value) in mutedWord.fields where key != "$type" {
            merged[key] = value
          }
          let updated = PrefObject(fields: merged)
          let value = MutedWords.sanitize(updated["value"]?.stringValue ?? "")
          return Self.mutedWord(
            id: item["id"]?.stringValue ?? tids.next(),
            value: value.isEmpty ? (item["value"]?.stringValue ?? "") : value,
            targets: updated["targets"]?.stringArrayValue ?? [],
            actorTarget: updated["actorTarget"]?.stringValue ?? "all",
            expiresAt: updated["expiresAt"]?.decoded(as: FormatString<Date>.self))
        }
        return Self.replaceMutedWords(
          prefs, existing: existing, items: Self.migrateLegacyMutedWords(items, tids: tids))
      }

    case .removeMutedWord(let mutedWord):
      return { prefs in
        guard let existing = prefs.first(PrefType.mutedWordsPref) else { return prefs }
        var items = try existing.objectArray("items")
        if let index = items.firstIndex(where: { Self.matchMutedWord($0, mutedWord) }) {
          items.remove(at: index)
        }
        return Self.replaceMutedWords(
          prefs, existing: existing, items: Self.migrateLegacyMutedWords(items, tids: tids))
      }

    default:
      return nil
    }
  }

  // MARK: - App state

  func appStatePatch(tids: TidGenerator) throws -> PreferencesUpdate? {
    if let update = try mutedWordPatch(tids: tids) { return update }
    if let update = try nudgePatch(tids: tids) { return update }
    if let update = try nuxPatch() { return update }
    switch self {
    case .setIsBetaUser(let isBetaUser):
      return { prefs in
        Self.replaceInPlace(prefs, PrefType.bskyAppStatePref, Self.upsert(
          prefs.first(PrefType.bskyAppStatePref), PrefType.bskyAppStatePref) { record in
            record.set("isBetaUser", isBetaUser)
          })
      }

    case .setActiveProgressGuide(let guide):
      return { prefs in
        Self.replaceInPlace(prefs, PrefType.bskyAppStatePref, Self.upsert(
          prefs.first(PrefType.bskyAppStatePref), PrefType.bskyAppStatePref) { record in
            if let guide {
              record.set("activeProgressGuide", guide.fields)
            } else {
              record.remove("activeProgressGuide")
            }
          })
      }

    default:
      return nil
    }
  }

  /// NUX records stored in the app-state pref.
  func nuxPatch() throws -> PreferencesUpdate? {
    switch self {
    case .upsertNux(let nux):
      try Nux.validate(nux)
      return { prefs in
        let existing = prefs.first(PrefType.bskyAppStatePref)
        var nuxs = try existing?.objectArray("nuxs") ?? []
        if let index = nuxs.firstIndex(where: {
          $0["id"]?.stringValue == nux["id"]?.stringValue
        }) {
          nuxs[index] = nux
        } else {
          nuxs.append(nux)
        }
        return Self.replaceInPlace(prefs, PrefType.bskyAppStatePref, Self.upsert(
          existing, PrefType.bskyAppStatePref) { record in
            record.setObjectArray("nuxs", nuxs)
          })
      }

    case .removeNuxs(let ids):
      return { prefs in
        guard let existing = prefs.first(PrefType.bskyAppStatePref) else { return nil }
        return Self.replaceInPlace(prefs, PrefType.bskyAppStatePref, try Self.upsert(
          existing, PrefType.bskyAppStatePref) { record in
            record.setObjectArray(
              "nuxs",
              try existing.objectArray("nuxs").filter { item in
                guard let id = item["id"]?.stringValue else { return true }
                return !ids.contains(id)
              })
          })
      }

    default:
      return nil
    }
  }

  /// Queued-nudge bookkeeping.
  func nudgePatch(tids: TidGenerator) throws -> PreferencesUpdate? {
    switch self {
    case .queueNudges(let nudges):
      return { prefs in
        let existing = prefs.first(PrefType.bskyAppStatePref)
        let current = existing?["queuedNudges"]?.stringArrayValue ?? []
        return Self.replaceInPlace(prefs, PrefType.bskyAppStatePref, Self.upsert(
          existing, PrefType.bskyAppStatePref) { record in
            record.set("queuedNudges", current + nudges.filter { !current.contains($0) })
          })
      }

    case .dismissNudges(let nudges):
      return { prefs in
        guard let existing = prefs.first(PrefType.bskyAppStatePref) else { return nil }
        return Self.replaceInPlace(prefs, PrefType.bskyAppStatePref, Self.upsert(
          existing, PrefType.bskyAppStatePref) { record in
            record.set(
              "queuedNudges",
              (existing["queuedNudges"]?.stringArrayValue ?? []).filter {
                !nudges.contains($0)
              })
          })
      }

    default:
      return nil
    }
  }

  // MARK: - Other preferences

  func miscPatch() throws -> PreferencesUpdate? {
    switch self {
    case .setVerificationPrefs(let patch):
      return { prefs in
        let updated = Self.merged(
          prefs.first(PrefType.verificationPrefs), PrefType.verificationPrefs,
          patch.hideBadges.map { ["hideBadges": JSONValue($0)] } ?? [:])
        if prefs.contains(PrefType.verificationPrefs) {
          return Self.replaceInPlace(prefs, PrefType.verificationPrefs, updated)
        }
        return prefs.appending(updated)
      }

    case .setPostInteractionSettings(let settings):
      return { prefs in
        var merged = prefs.first(PrefType.postInteractionSettingsPref)?.fields ?? [:]
        merged["$type"] = JSONValue(PrefType.postInteractionSettingsPref)
        // Explicit assignment: nil means "absent", not "keep existing".
        Self.setOptional(&merged, "threadgateAllowRules", settings.threadgateAllowRules)
        Self.setOptional(&merged, "postgateEmbeddingRules", settings.postgateEmbeddingRules)
        return prefs.removing(PrefType.postInteractionSettingsPref)
          .appending(PrefObject(fields: merged))
      }

    case .updateLiveEventPreferences(let action):
      return { prefs in
        let existing = prefs.first(PrefType.liveEventPreferences)
        var hidden = Set(existing?["hiddenFeedIds"]?.stringArrayValue ?? [])
        var hideAll = existing?["hideAllFeeds"]?.boolValue ?? false
        switch action {
        case .hideFeed(let id): hidden.insert(id)
        case .unhideFeed(let id): hidden.remove(id)
        case .toggleHideAllFeeds: hideAll.toggle()
        }
        var merged = existing?.fields ?? [:]
        merged["$type"] = JSONValue(PrefType.liveEventPreferences)
        merged["hiddenFeedIds"] = JSONValue(Array(hidden))
        merged["hideAllFeeds"] = JSONValue(hideAll)
        return prefs.removing(PrefType.liveEventPreferences)
          .appending(PrefObject(fields: merged))
      }

    default:
      return nil
    }
  }
}
