import Foundation

import Lexicons
import SwiftAtproto

/// Shared helpers behind ``PreferencesAction`` patches: the content-label
/// double-write, the v2 saved-feeds read-modify-write, muted-word bookkeeping,
/// and small optional-field setters.
extension PreferencesAction {

  /// `setContentLabelPref`: replace the key+labeler pair, then double-write the
  /// global pref under each legacy alias for `key`.
  internal static func setContentLabelPref(
    _ prefs: PreferencesArray, key: String, value: LabelPreference, labelerDid: String?
  ) -> PreferencesArray {
    var elements = prefs.elements.filter { pref in
      guard pref.type == PrefType.contentLabelPref else { return true }
      let matchesKey = pref["label"]?.stringValue == key
      let matchesLabeler = pref["labelerDid"]?.stringValue == labelerDid
      return !(matchesKey && matchesLabeler)
    }
    var newPref = PrefObject.make(PrefType.contentLabelPref)
    newPref.set("label", key)
    if let labelerDid { newPref.set("labelerDid", labelerDid) }
    newPref.set("visibility", value)
    elements.append(newPref)

    // Legacy alias double-write applies only to global (unlabeled) prefs.
    if labelerDid == nil {
      for alias in ModerationLabels.labelRemapReverse[key] ?? [] {
        elements.removeAll { pref in
          pref.type == PrefType.contentLabelPref
            && pref["label"]?.stringValue == alias
            && pref["labelerDid"]?.stringValue == nil
        }
        var aliasPref = PrefObject.make(PrefType.contentLabelPref)
        aliasPref.set("label", alias)
        aliasPref.set("visibility", value)
        elements.append(aliasPref)
      }
    }
    return PreferencesArray(elements: elements)
  }

  /// The shared v2 saved-feeds read-modify-write: applies `transform` to the
  /// current items, orders pinned-first, and double-writes the v2 URIs back
  /// into an existing v1 pref during the transition.
  internal static func updateSavedFeedsV2(
    _ prefs: PreferencesArray,
    _ transform: ([PrefObject]) throws -> [PrefObject]
  ) throws -> PreferencesArray {
    let existingV2 = prefs.first(PrefType.savedFeedsPrefV2)
    let currentItems = try existingV2?.objectArray("items") ?? []
    let newFeeds = try transform(currentItems)
    let sorted = Self.pinnedFirst(newFeeds)

    var v2Record = existingV2 ?? PrefObject.make(PrefType.savedFeedsPrefV2)
    v2Record.setObjectArray("items", sorted)

    var updated = prefs.removing(PrefType.savedFeedsPrefV2)
    updated.elements.append(v2Record)

    if let existingV1 = prefs.first(PrefType.savedFeedsPref) {
      // v1 only understands feeds and lists.
      let v2Compat = Self.savedFeedsToUriArrays(
        sorted.filter { ["feed", "list"].contains($0["type"]?.stringValue ?? "") })
      let saved = existingV1["saved"]?.stringArrayValue ?? []
      let pinned = existingV1["pinned"]?.stringArrayValue ?? []
      var v1Record = existingV1
      v1Record.set("saved", Self.uniquePreservingOrder(saved + v2Compat.saved))
      v1Record.set("pinned", Self.uniquePreservingOrder(pinned + v2Compat.pinned))
      updated = updated.removing(PrefType.savedFeedsPref).appending(v1Record)
    }
    return updated
  }

  /// Stable partition: pinned items keep their relative order and precede
  /// unpinned items (which also keep theirs).
  internal static func pinnedFirst(_ feeds: [PrefObject]) -> [PrefObject] {
    feeds.filter { $0["pinned"]?.boolValue == true }
      + feeds.filter { $0["pinned"]?.boolValue != true }
  }

  internal static func savedFeedsToUriArrays(_ feeds: [PrefObject]) -> LegacyFeeds {
    var result = LegacyFeeds()
    for feed in feeds {
      guard let value = feed["value"]?.stringValue else { continue }
      if feed["pinned"]?.boolValue == true {
        result.pinned.append(value)
        result.saved.append(value)
      } else {
        result.saved.append(value)
      }
    }
    return result
  }

  internal static func uniquePreservingOrder(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values where !seen.contains(value) {
      seen.insert(value)
      out.append(value)
    }
    return out
  }

  internal static func mutedWord(
    id: String, value: String, targets: [String], actorTarget: String,
    expiresAt: FormatString<Date>?
  ) -> PrefObject {
    var record = PrefObject(fields: [:])
    record.set("id", id)
    record.set("value", value)
    record.set("targets", targets)
    record.set("actorTarget", actorTarget)
    if let expiresAt {
      record.set("expiresAt", expiresAt)
    }
    return record
  }

  /// Backfills `id` on legacy muted words that lack one.
  internal static func migrateLegacyMutedWords(
    _ items: [PrefObject], tids: TidGenerator
  ) -> [PrefObject] {
    items.map { item in
      guard item["id"]?.stringValue == nil else { return item }
      var copy = item
      copy.set("id", tids.next())
      return copy
    }
  }

  /// Matches by `id` when present, else by `value` for legacy entries.
  internal static func matchMutedWord(_ existing: PrefObject, _ new: PrefObject) -> Bool {
    if let existingId = existing["id"]?.stringValue {
      return existingId == new["id"]?.stringValue
    }
    return existing["value"]?.stringValue == new["value"]?.stringValue
  }

  internal static func replaceMutedWords(
    _ prefs: PreferencesArray, existing: PrefObject?, items: [PrefObject]
  ) -> PreferencesArray {
    var record = existing ?? PrefObject.make(PrefType.mutedWordsPref)
    record.setObjectArray("items", items)
    return prefs.removing(PrefType.mutedWordsPref).appending(record)
  }

  internal static func setOptional<T: Encodable>(
    _ record: inout PrefObject, _ key: String, _ value: T?
  ) {
    if let value {
      record.set(key, value)
    } else {
      record.remove(key)
    }
  }

  internal static func setOptional(
    _ fields: inout [String: JSONValue], _ key: String, _ value: [PrefObject]?
  ) {
    if let value {
      fields[key] = JSONValue(value.map(\.fields))
    } else {
      fields.removeValue(forKey: key)
    }
  }

  /// Replaces every record of `type` with `record`, preserving position, or
  /// appends when none exists.
  ///
  /// This mirrors the SDK's `prefs.map(p => is$typedObject(p, type) ? updated : p)`
  /// pattern, which rewrites matching entries in place. The alternative
  /// (`filter` + `concat`) moves the record to the end of the array; the
  /// actions that do that are marked in the patch code.
  internal static func replaceInPlace(
    _ prefs: PreferencesArray, _ type: String, _ record: PrefObject
  ) -> PreferencesArray {
    if prefs.contains(type) {
      return prefs.mapping(type) { _ in record }
    }
    return prefs.appending(record)
  }

  /// Replaces or appends a singleton preference record.
  ///
  /// `transform` receives the existing record (or a fresh one carrying just
  /// the `$type`), so a `$build`-style spread preserves every member the
  /// transform does not touch.
  internal static func upsert(
    _ existing: PrefObject?, _ type: String,
    _ transform: (inout PrefObject) throws -> Void
  ) rethrows -> PrefObject {
    var record = existing ?? PrefObject.make(type)
    try transform(&record)
    return record
  }

  /// Merges partial fields over an existing record's members.
  internal static func merged(
    _ existing: PrefObject?, _ type: String, _ fields: [String: JSONValue],
    _ extra: (inout [String: JSONValue]) -> Void = { _ in }
  ) -> PrefObject {
    var out = existing?.fields ?? [:]
    out["$type"] = JSONValue(type)
    for (key, value) in fields {
      out[key] = value
    }
    extra(&out)
    return PrefObject(fields: out)
  }

  /// Dedupes saved feeds by id, keeping the position of the last occurrence.
  internal static func dedupeByLastPosition(_ feeds: [PrefObject]) -> [PrefObject] {
    var order: [String] = []
    var byId: [String: PrefObject] = [:]
    for feed in feeds {
      guard let id = feed["id"]?.stringValue else { continue }
      if byId[id] != nil {
        order.removeAll { $0 == id }
      }
      order.append(id)
      byId[id] = feed
    }
    return order.compactMap { byId[$0] }
  }

  internal static func labelerItem(did: String) -> PrefObject {
    PrefObject(fields: ["did": JSONValue(did)])
  }
}
