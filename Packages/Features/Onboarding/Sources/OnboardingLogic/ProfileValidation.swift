import Foundation

/// Validation rules for the profile step.
///
/// Port of the constraints the RN app applies to a display name and a handle.
/// RN's onboarding profile step has no name or handle field today (the
/// `StepProfile` screen only collects an avatar, and `StepFinished` writes
/// `displayName = ''`), so these rules come from the screens that *do* collect
/// them: `EditProfileDialog.tsx` for the display name and the signup handle
/// step for the handle. They live here because the Swift profile step is the
/// one that owns the profile write.
public enum ProfileValidation {

  /// `MAX_DISPLAY_NAME` from `lib/constants.ts`.
  public static let maxDisplayNameLength = 64

  /// The outcome of validating a display name.
  public enum DisplayNameValidation: Sendable, Equatable {
    /// The name is acceptable; the associated value is the trimmed form.
    case valid(String)
    /// The name was empty after trimming, which the profile write treats as
    /// "clear the display name" rather than as an error.
    case empty
    /// The name exceeded ``maxDisplayNameLength``.
    case tooLong
  }

  /// Validates a display name.
  ///
  /// Length is counted in UTF-16 code units, matching the `maxCount` the RN
  /// text field enforces via `string.length`. The lexicon constrains the field
  /// by grapheme count (64), so a name of 64 emoji is 128 UTF-16 units and is
  /// rejected here even though the server would accept it; that is the RN
  /// behaviour, and matching it keeps the two clients from disagreeing about
  /// what the counter shows.
  public static func validateDisplayName(_ raw: String) -> DisplayNameValidation {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .empty }
    if trimmed.utf16.count > maxDisplayNameLength { return .tooLong }
    return .valid(trimmed)
  }

  /// The outcome of validating a handle's syntax.
  public enum HandleValidation: Sendable, Equatable {
    /// The handle is syntactically usable.
    case valid(String)
    /// The handle was empty.
    case empty
    /// The handle failed a syntax rule; carries which one.
    case invalid(reason: String)
  }

  /// The shortest a handle's first segment may be.
  public static let minHandleSegmentLength = 3
  /// The longest a handle's first segment may be.
  public static let maxHandleSegmentLength = 18
  /// The longest a whole handle may be.
  public static let maxHandleLength = 253

  /// Validates a handle's syntax.
  ///
  /// The rules are the atproto handle grammar as the RN signup step applies
  /// it (`screens/Signup/StepHandle`): a dot-separated name whose segments are
  /// alphanumeric with interior hyphens, each segment at most 63 characters,
  /// and a first segment between 3 and 18 characters. The domain half is not
  /// checked against a public-suffix list here; availability is the server's
  /// answer to ``checkHandleAvailability``.
  public static func validateHandle(_ raw: String) -> HandleValidation {
    let handle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if handle.isEmpty { return .empty }
    if handle.utf16.count > maxHandleLength {
      return .invalid(reason: "handle is too long")
    }
    if handle.hasPrefix(".") || handle.hasSuffix(".") || handle.contains("..") {
      return .invalid(reason: "handle has an empty segment")
    }
    // A trailing dot is how a user writes "I have not typed the domain yet";
    // it is rejected above rather than silently stripped.
    let segments = handle.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard segments.count >= 2 else {
      return .invalid(reason: "handle needs a domain")
    }
    for segment in segments {
      guard segment.count <= 63 else { return .invalid(reason: "handle segment is too long") }
      guard segment.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
        return .invalid(reason: "handle has an invalid character")
      }
      guard !segment.hasPrefix("-"), !segment.hasSuffix("-") else {
        return .invalid(reason: "handle segment starts or ends with a hyphen")
      }
    }
    let first = segments[0]
    if first.count < minHandleSegmentLength {
      return .invalid(reason: "handle name is too short")
    }
    if first.count > maxHandleSegmentLength {
      return .invalid(reason: "handle name is too long")
    }
    return .valid(handle)
  }

  /// Composes a full handle from a name and a domain, the way
  /// `createFullHandle` in `lib/strings/handles.ts` does.
  public static func fullHandle(name: String, domain: String) -> String {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let name = trimmedName.replacingOccurrences(
      of: #"\.+$"#, with: "", options: .regularExpression)
    let domain = trimmedDomain.replacingOccurrences(
      of: #"^\.+"#, with: "", options: .regularExpression)
    return "\(name).\(domain)"
  }
}

/// The interest taxonomy.
///
/// Port of `src/lib/interests.ts`. The list is the wire vocabulary: these
/// exact strings are what `setInterestsPref` stores and what the
/// `X-Bsky-Topics` header carries to the suggestion endpoints.
public enum Interests {
  /// Every selectable interest, alphabetized as in the RN source.
  public static let all: [String] = [
    "animals", "art", "books", "comedy", "comics", "culture", "dev", "education",
    "finance", "food", "gaming", "journalism", "movies", "music", "nature", "news",
    "pets", "photography", "politics", "science", "sports", "tech", "tv", "writers",
  ]

  /// The subset the RN app surfaces first (`popularInterests`).
  public static let popular: [String] = [
    "art", "gaming", "sports", "comics", "music", "politics", "photography",
    "science", "news",
  ]

  /// English display names, port of `useInterestsDisplayNames`. Kept here (and
  /// untranslated) so the logic layer can order and label without a locale
  /// dependency; the views target localizes.
  public static let displayNames: [String: String] = [
    "animals": "Animals",
    "art": "Art",
    "books": "Books",
    "comedy": "Comedy",
    "comics": "Comics",
    "culture": "Culture",
    "dev": "Software Dev",
    "education": "Education",
    "finance": "Finance",
    "food": "Food",
    "gaming": "Video Games",
    "journalism": "Journalism",
    "movies": "Movies",
    "music": "Music",
    "nature": "Nature",
    "news": "News",
    "pets": "Pets",
    "photography": "Photography",
    "politics": "Politics",
    "science": "Science",
    "sports": "Sports",
    "tech": "Tech",
    "tv": "TV",
    "writers": "Writers",
  ]

  /// Whether a tag is in the taxonomy.
  public static func isValid(_ tag: String) -> Bool {
    all.contains(tag)
  }

  /// Filters a selection down to known tags, preserving order.
  ///
  /// The RN step renders the whole taxonomy and stores whatever the toggle
  /// group reports, so an unknown tag can only arrive from a restored
  /// snapshot or a server that wrote one. Dropping them keeps the header and
  /// the preference write on-vocabulary.
  public static func known(_ tags: [String]) -> [String] {
    tags.filter(isValid)
  }

  /// The tab order for the suggested-accounts screen: the user's own
  /// selections first (in selection order), then the popular interests, then
  /// the rest in taxonomy order.
  ///
  /// Port of the two chained `sort(boostInterests(...))` calls in
  /// `StepSuggestedAccounts`. Array sort is stable in V8, so the *second* call
  /// is the primary key and the first breaks its ties. `boostInterests` ranks
  /// by the index in its boosts array, not by membership, so the selection's
  /// own order is what the first group follows.
  public static func orderedForTabs(selected: [String]) -> [String] {
    func rank(_ tag: String, in boosts: [String]) -> Int {
      boosts.firstIndex(of: tag) ?? Int.max
    }
    return all.sorted { lhs, rhs in
      let lhsSelected = rank(lhs, in: selected)
      let rhsSelected = rank(rhs, in: selected)
      if lhsSelected != rhsSelected { return lhsSelected < rhsSelected }
      return rank(lhs, in: popular) < rank(rhs, in: popular)
    }
  }
}
