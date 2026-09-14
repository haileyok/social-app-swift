import Foundation

import Moderation
// A plain module import is used rather than selective imports: the module also
// exports a `Preferences` struct, so member-syntax qualification like
// `Preferences.MutedWords` resolves against the struct. Unqualified names are
// unambiguous.
import Preferences
import SwiftAtproto

/// How long a muted word lasts when added.
///
/// Port of the `durations` radio group in
/// `src/components/dialogs/MutedWords.tsx` (`forever`, `24_hours`, `7_days`,
/// `30_days`). `forever` mints no `expiresAt`.
public enum MutedWordDuration: String, Sendable, CaseIterable, Hashable {
  case forever
  case hours24 = "24_hours"
  case days7 = "7_days"
  case days30 = "30_days"

  /// The number of days this duration spans, or nil for `forever`.
  public var days: Int? {
    switch self {
    case .forever: return nil
    case .hours24: return 1
    case .days7: return 7
    case .days30: return 30
    }
  }

  /// The expiry instant for a word added at `now`, or nil for `forever`.
  public func expiresAt(from now: Date) -> Date? {
    guard let days else { return nil }
    return now.addingTimeInterval(Double(days) * 86_400)
  }
}

/// The targets a new muted word applies to.
///
/// Port of the `targets` radio in `MutedWords.tsx`: the UI offers "Text & tags"
/// (`content`) and "Tags only" (`tag`), and the submit path always includes
/// `tag`, adding `content` only when the "Text & tags" surface is chosen:
///
/// ```ts
/// const surfaces = ['tag', targets.includes('content') && 'content'].filter(Boolean)
/// ```
public enum MutedWordSurface: String, Sendable, CaseIterable, Hashable {
  case content
  case tag
}

/// A validated add-muted-word input.
public struct MutedWordDraft: Sendable, Hashable {
  /// The raw field contents, exactly as typed.
  public var rawValue: String
  /// The surfaces chosen.
  public var surfaces: Set<MutedWordSurface>
  /// Whether the word should skip users the viewer follows.
  public var excludeFollowing: Bool
  /// The chosen duration.
  public var duration: MutedWordDuration
  /// The instant the dialog is submitting at, injected so expiry is testable.
  public var now: Date

  public init(
    rawValue: String, surfaces: Set<MutedWordSurface> = [.content],
    excludeFollowing: Bool = false, duration: MutedWordDuration = .forever,
    now: Date = Date()
  ) {
    self.rawValue = rawValue
    self.surfaces = surfaces
    self.excludeFollowing = excludeFollowing
    self.duration = duration
    self.now = now
  }
}

/// What a row in "Your muted words" shows.
///
/// Port of the `MutedWordRow` derivation: the target phrase, whether the word
/// has expired, and whether it excludes followed users.
public struct MutedWordRowModel: Sendable, Hashable {
  /// The stored word.
  public let word: MutedWord
  /// The record identifier, when the stored item had one.
  public let id: String?
  /// True when the word applies to post text as well as tags.
  public let appliesToContent: Bool
  /// The parsed expiry, when set.
  public let expiryDate: Date?
  /// True when the expiry is in the past.
  public let isExpired: Bool
  /// True when the word skips followed users.
  public let excludesFollowing: Bool

  public init(
    word: MutedWord, id: String? = nil, appliesToContent: Bool, expiryDate: Date?,
    isExpired: Bool, excludesFollowing: Bool
  ) {
    self.word = word
    self.id = id
    self.appliesToContent = appliesToContent
    self.expiryDate = expiryDate
    self.isExpired = isExpired
    self.excludesFollowing = excludesFollowing
  }
}

/// Builds and validates muted-word edits.
///
/// Port of the submit path in `src/components/dialogs/MutedWords.tsx` plus the
/// row derivation in `MutedWordRow`. The RN screen sends the RAW field value
/// and relies on the SDK to sanitize (`// send raw value and rely on SDK as
/// sanitization source of truth`), so this model does the same: validation
/// reads the sanitized value but the payload carries the raw one.
public enum MutedWordsEditor {

  /// Validation failures the editor surfaces to the user.
  public enum ValidationError: Error, Sendable, Equatable {
    /// The sanitized value was empty, or no surface was chosen. RN shows one
    /// message for both: "Please enter a valid word, tag, or phrase to mute".
    case emptyValueOrNoSurface
  }

  /// The message RN shows for ``ValidationError/emptyValueOrNoSurface``.
  public static let emptyValueMessage = "Please enter a valid word, tag, or phrase to mute"

  /// Builds the `app.bsky.actor.defs#mutedWord` payload for an add.
  ///
  /// Targets are always `["tag"]` plus `"content"` when that surface is
  /// selected, in that order, matching the RN array construction. `expiresAt`
  /// is omitted for `forever`.
  ///
  /// The value sent is the RAW input: the preferences engine sanitizes it on
  /// write, and the RN screen deliberately relies on that.
  ///
  /// - Note: RN's guard is `!sanitizedValue || !surfaces.length`, but `surfaces`
  ///   is built as `['tag', ...]` and therefore is never empty. The surface half
  ///   of the guard is kept for fidelity and is unreachable; only an empty
  ///   value can fail here. A draft with no selected surfaces still mutes in
  ///   tags only, exactly as RN does.
  public static func payload(for draft: MutedWordDraft) throws -> MutedWord {
    let sanitized = MutedWords.sanitize(draft.rawValue)
    let surfaces = targets(for: draft.surfaces)
    guard !sanitized.isEmpty, !surfaces.isEmpty else {
      throw ValidationError.emptyValueOrNoSurface
    }

    var payload = MutedWord(
      value: draft.rawValue,
      targets: surfaces.compactMap { MutedWordTarget(rawValue: $0) },
      actorTarget: draft.excludeFollowing ? .excludeFollowing : .all)
    if let expiry = draft.duration.expiresAt(from: draft.now) {
      payload.expiresAt = isoString(expiry)
    }
    return payload
  }

  /// The wire target list for a set of surfaces, always including `tag`.
  ///
  /// Returns strings so the caller can build the `MutedWordInput` the
  /// preferences actions take (which is `[String]`).
  public static func targets(for surfaces: Set<MutedWordSurface>) -> [String] {
    var out = ["tag"]
    if surfaces.contains(.content) { out.append("content") }
    return out
  }

  /// Whether a draft is submittable, without throwing. Drives the Add button's
  /// disabled state (`disabled={isPending || !field}` in RN).
  ///
  /// Mirrors ``payload(for:)``'s reachable guard: only an empty value blocks
  /// submission.
  public static func canSubmit(_ draft: MutedWordDraft) -> Bool {
    !MutedWords.sanitize(draft.rawValue).isEmpty
  }

  /// Derives the list-row models, newest first.
  ///
  /// Port of the `.reverse()` in the RN list render (muted words are appended,
  /// so reversing shows the most recent first).
  public static func rows(_ words: [MutedWord], items: [PrefObject]? = nil, now: Date = Date())
    -> [MutedWordRowModel]
  {
    let byValue = items.map { objects in
      Dictionary(
        objects.compactMap { object in
          object["value"]?.stringValue.map { ($0, object) }
        }, uniquingKeysWith: { first, _ in first })
    }

    return words.reversed().map { word in
      let item = byValue?[word.value]
      let id = item?["id"]?.stringValue
      let expiry = parseISO(word.expiresAt)
      return MutedWordRowModel(
        word: word,
        id: id,
        appliesToContent: word.targets.contains(.content),
        expiryDate: expiry,
        isExpired: expiry.map { $0 < now } ?? false,
        excludesFollowing: word.actorTarget == .excludeFollowing)
    }
  }

  /// The renewed payload for a row: same word, a new expiry.
  ///
  /// Port of the `renew(days)` handler, which spreads the existing word and
  /// replaces `expiresAt` (or clears it for "Forever").
  public static func renewed(_ word: MutedWord, days: Int?, from now: Date) -> MutedWord {
    var copy = word
    if let days {
      copy.expiresAt = isoString(now.addingTimeInterval(Double(days) * 86_400))
    } else {
      copy.expiresAt = nil
    }
    return copy
  }

  /// The `app.bsky.actor.defs#mutedWord` record for a remove/update call.
  ///
  /// The preferences actions match by `id` when present and by `value` for
  /// legacy entries, so the record only needs the identity fields plus whatever
  /// the update intends to change.
  public static func record(
    id: String?, value: String, targets: [String]? = nil, actorTarget: String? = nil,
    expiresAt: String? = nil
  ) -> PrefObject {
    var record = PrefObject.make(PrefType.mutedWordsPref)
    record = PrefObject(fields: record.fields)
    var fields: [String: JSONValue] = [:]
    if let id { fields["id"] = JSONValue(id) }
    fields["value"] = JSONValue(value)
    if let targets { fields["targets"] = JSONValue(targets) }
    if let actorTarget { fields["actorTarget"] = JSONValue(actorTarget) }
    if let expiresAt { fields["expiresAt"] = JSONValue(expiresAt) }
    return PrefObject(fields: fields)
  }

  /// Renders a date as the ISO-8601 string the wire expects.
  static func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  /// Parses an ISO-8601 timestamp, tolerating the with/without-fractional
  /// variants the network contains.
  static func parseISO(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: raw) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: raw)
  }
}

private extension PrefObject {
  /// Reads a member that holds a string.
  subscript(key: String) -> JSONValue? { fields[key] }
}
