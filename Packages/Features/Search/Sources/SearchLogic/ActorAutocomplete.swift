import Foundation
import Lexicons

/// Typeahead prefix normalization and suggestion filtering.
///
/// Ported from `state/queries/actor-autocomplete.ts`. The RN hook normalizes
/// the prefix before it becomes part of the query key (lowercase + trim, and
/// strip one trailing `.` so going from `foo` to `foo.` does not clear the
/// matches), returns an empty list for an empty prefix without a request, and
/// filters the results by handle-uniqueness.
///
/// The RN version also drops profiles that moderate to a filter/hide. That
/// check needs the moderation package and the user's moderation options, so
/// this port exposes ``shouldInclude(handle:isExactMatch:moderationExcluded:)``
/// with the moderation decision injected: the caller supplies the verdict, the
/// exact-match override rule stays here.
public enum ActorAutocomplete {
  /// The RN default typeahead limit (`limit || 8`).
  public static let defaultLimit = 8

  /// Normalizes a typeahead prefix the way the RN hook does.
  ///
  /// Lowercases, trims surrounding whitespace, and drops a single trailing `.`.
  public static func normalizePrefix(_ raw: String) -> String {
    var prefix = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if prefix.hasSuffix(".") {
      // Going from "foo" to "foo." should not clear matches.
      prefix = String(prefix.dropLast())
    }
    return prefix
  }

  /// True when the prefix warrants a network request.
  ///
  /// The RN hook returns `[]` for an empty prefix rather than calling the
  /// endpoint, so the caller must not fetch when this is false.
  public static func shouldFetch(prefix: String) -> Bool {
    !prefix.isEmpty
  }

  /// The moderation verdicts the inclusion rule needs, supplied by the caller.
  ///
  /// RN computes these from `moderateProfile(profile, moderationOpts).ui('profileList')`:
  /// whether the profile moderates to a filter, whether it contains a hideable
  /// offense, and whether it is "just a mute" (muted but otherwise clean). The
  /// moderation package is not a dependency of this one, so the verdict is
  /// injected rather than computed here.
  public struct ModerationVerdict: Sendable, Equatable {
    /// `modui.filter` - the profile should be filtered out of the list.
    public let filter: Bool
    /// `moduiContainsHideableOffense(modui)` - a hideable offense is present.
    public let containsHideableOffense: Bool
    /// `isJustAMute(modui)` - muted, but nothing worse.
    public let isJustAMute: Bool

    public init(filter: Bool, containsHideableOffense: Bool, isJustAMute: Bool) {
      self.filter = filter
      self.containsHideableOffense = containsHideableOffense
      self.isJustAMute = isJustAMute
    }

    /// A clean profile: nothing moderated.
    public static let clean = ModerationVerdict(
      filter: false, containsHideableOffense: false, isJustAMute: false)
  }

  /// The typeahead suggestions for `prefix`, in RN's filtered order.
  ///
  /// Handles are deduped (first occurrence wins), and the result is filtered by
  /// ``shouldInclude(handle:prefix:verdict:)``.
  public static func suggestions(
    prefix: String,
    searched: [App.Bsky.ActorDefs_ProfileViewBasic],
    verdict: (App.Bsky.ActorDefs_ProfileViewBasic) -> ModerationVerdict = { _ in .clean }
  ) -> [App.Bsky.ActorDefs_ProfileViewBasic] {
    var seenHandles = Set<String>()
    let unique = searched.filter { seenHandles.insert($0.handle.rawValue).inserted }
    return unique.filter { profile in
      shouldInclude(handle: profile.handle.rawValue, prefix: prefix, verdict: verdict(profile))
    }
  }

  /// The inclusion rule from RN's `computeSuggestions`.
  ///
  /// A profile is kept when any of: it matches the typed handle exactly and
  /// carries no hideable offense; moderation does not filter it; or it is only
  /// muted. An exact handle match therefore survives a filter, but not a
  /// hideable offense.
  public static func shouldInclude(
    handle: String, prefix: String, verdict: ModerationVerdict
  ) -> Bool {
    let isExactMatch = !prefix.isEmpty && handle.lowercased() == prefix
    return (isExactMatch && !verdict.containsHideableOffense) || !verdict.filter
      || verdict.isJustAMute
  }
}
