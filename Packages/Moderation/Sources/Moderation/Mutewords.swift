import Foundation

/// Languages that do not use spaces (or do not use them in a way conducive to
/// word-based filtering); for these, matching falls back to substring search.
private let languageExceptions: Set<String> = ["ja", "zh", "ko", "th", "vi"]

/// One muted word that matched, with the text that matched it.
public struct MutedWordMatch: Sendable, Hashable {
  /// The muted word that matched.
  public var word: MutedWord
  /// The matched predicate: the muted word itself for inclusion matches, or
  /// the trimmed word for word-boundary matches.
  public var matchedValue: String

  public init(word: MutedWord, matchedValue: String) {
    self.word = word
    self.matchedValue = matchedValue
  }
}

/// Current UTC datetime as an ISO-8601 string with millisecond precision,
/// matching `currentDatetimeString()` from `@atproto/syntax`. Used only for
/// lexicographic comparison against muted-word expiry timestamps.
public func currentDatetimeString(now: Date = Date()) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.string(from: now)
}

/// Checks whether `text` matches any of `mutedWords`, returning the matches or
/// `nil` when there are none.
///
/// One match is reported per muted word: the first candidate in the post text
/// that satisfies the word-boundary rules.
public func matchMuteWords(
  mutedWords: [MutedWord],
  text: String,
  facets: [RichTextFacet]? = nil,
  outlineTags: [String]? = nil,
  languages: [String]? = nil,
  actor: ProfileViewBasic? = nil,
  now: Date = Date()
) -> [MutedWordMatch]? {
  let exception = languageExceptions.contains(languages?.first ?? "")
  let tags = collectTags(facets: facets, outlineTags: outlineTags)
  let postText = text.lowercased()

  var matchContext = MuteWordMatchContext(
    postText: postText, tags: tags, exception: exception, actor: actor, now: now)
  var matches: [MutedWordMatch] = []
  for muteWord in mutedWords {
    if let match = matchMuteWord(muteWord, context: matchContext) {
      matches.append(match)
    }
  }
  return matches.isEmpty ? nil : matches
}

/// Lowercased hashtags from the post's outline tags and facet tag features.
/// `content`-targeted muted words apply to these as well as to the text.
private func collectTags(facets: [RichTextFacet]?, outlineTags: [String]?) -> [String] {
  let facetTags = (facets ?? []).flatMap { facet in
    (facet.features ?? [])
      .filter { $0.type == "app.bsky.richtext.facet#tag" }
      .compactMap(\.tag)
  }
  return ((outlineTags ?? []) + facetTags).map { $0.lowercased() }
}

/// The fixed inputs for matching one muted word against a piece of text.
private struct MuteWordMatchContext {
  let postText: String
  let tags: [String]
  let exception: Bool
  let actor: ProfileViewBasic?
  let now: Date
}

/// Applies the full matching algorithm to a single muted word, returning the
/// first match or nil. The checks are ordered exactly as in the TypeScript
/// engine; reordering them changes which predicate is reported.
private func matchMuteWord(
  _ muteWord: MutedWord,
  context: MuteWordMatchContext
) -> MutedWordMatch? {
  let mutedWord = muteWord.value.lowercased()
  let postText = context.postText
  let inclusiveMatch = MutedWordMatch(word: muteWord, matchedValue: muteWord.value)

  // expired, ignore
  if let expiresAt = muteWord.expiresAt, expiresAt < currentDatetimeString(now: context.now) {
    return nil
  }
  let followsActor = context.actor?.viewer?.following?.isEmpty == false
  if muteWord.actorTarget == .excludeFollowing, followsActor {
    return nil
  }
  // `content` applies to tags as well
  if context.tags.contains(mutedWord) {
    return inclusiveMatch
  }
  // rest of the checks are for `content` only
  if !muteWord.targets.contains(.content) {
    return nil
  }
  // single character or other exception, has to use includes
  if (mutedWord.count == 1 || context.exception) && postText.contains(mutedWord) {
    return inclusiveMatch
  }
  // too long
  if mutedWord.count > postText.count {
    return nil
  }
  // exact match
  if mutedWord == postText {
    return inclusiveMatch
  }
  // any muted phrase with space or punctuation
  let hasSeparator = mutedWord.contains { $0.isWhitespace || isPunctuation($0) }
  if hasSeparator, postText.contains(mutedWord) {
    return inclusiveMatch
  }
  // check individual character groups
  for word in splitKeepingEmpty(postText, isSeparator: isWordBoundarySeparator) {
    if let match = matchWordGroup(word, mutedWord: mutedWord, word: muteWord) {
      return match
    }
  }
  return nil
}

/// Compares one whitespace-delimited group against a muted word, allowing
/// internal punctuation (such as `s@ssy`) while rejecting `and/or`-style
/// matches against contiguous words like `Andor`.
private func matchWordGroup(
  _ word: String,
  mutedWord: String,
  word muteWord: MutedWord
) -> MutedWordMatch? {
  let matched = MutedWordMatch(word: muteWord, matchedValue: word)
  if word == mutedWord {
    return matched
  }
  // compare word without leading/trailing punctuation, but allow internal
  // punctuation (such as `s@ssy`)
  let wordTrimmedPunctuation = trimPunctuation(word)
  if mutedWord == wordTrimmedPunctuation {
    return matched
  }
  if mutedWord.count > wordTrimmedPunctuation.count {
    return nil
  }
  guard wordTrimmedPunctuation.contains(where: isPunctuation) else { return nil }
  /*
   * Exit case for any punctuation within the predicate that we _do_ allow
   * e.g. `and/or` should not match `Andor`.
   */
  if wordTrimmedPunctuation.contains("/") {
    return nil
  }
  let spacedWord = replaceRunsOfPunctuation(in: wordTrimmedPunctuation, with: " ")
  if spacedWord == mutedWord {
    return matched
  }
  let contiguousWord = spacedWord.filter { !$0.isWhitespace }
  if contiguousWord == mutedWord {
    return matched
  }
  for wordPart in splitKeepingEmpty(wordTrimmedPunctuation, isSeparator: isPunctuation)
  where wordPart == mutedWord {
    return matched
  }
  return nil
}

/// Checks whether `text` matches any of `mutedWords`.
public func hasMutedWord(
  mutedWords: [MutedWord],
  text: String,
  facets: [RichTextFacet]? = nil,
  outlineTags: [String]? = nil,
  languages: [String]? = nil,
  actor: ProfileViewBasic? = nil,
  now: Date = Date()
) -> Bool {
  matchMuteWords(
    mutedWords: mutedWords,
    text: text,
    facets: facets,
    outlineTags: outlineTags,
    languages: languages,
    actor: actor,
    now: now
  ) != nil
}

/// Splits `string` on `separator`, preserving empty pieces exactly as
/// JavaScript's `String.split` does. Swift's `split` drops them, which would
/// change which candidate words the engine compares.
private func splitKeepingEmpty(
  _ string: String,
  isSeparator: (Character) -> Bool
) -> [String] {
  var parts: [String] = []
  var current = String()
  for character in string {
    if isSeparator(character) {
      parts.append(current)
      current = ""
    } else {
      current.append(character)
    }
  }
  parts.append(current)
  return parts
}

/// Matches the engine's `WORD_BOUNDARY` class: any whitespace character.
private func isWordBoundarySeparator(_ character: Character) -> Bool {
  character.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
}

/// Matches the engine's `\p{P}` class at the scalar level.
private func isPunctuation(_ character: Character) -> Bool {
  character.unicodeScalars.contains { isPunctuationScalar($0) }
}

private func isPunctuationScalar(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.properties.generalCategory {
  case .connectorPunctuation,
    .dashPunctuation,
    .openPunctuation,
    .closePunctuation,
    .initialPunctuation,
    .finalPunctuation,
    .otherPunctuation:
    return true
  default:
    return false
  }
}

/// Strips leading and trailing punctuation, leaving internal punctuation.
private func trimPunctuation(_ word: String) -> String {
  var result = Substring(word)
  while let first = result.first, isPunctuation(first) {
    result = result.dropFirst()
  }
  while let last = result.last, isPunctuation(last) {
    result = result.dropLast()
  }
  return String(result)
}

/// Replaces each run of punctuation with `replacement`, matching `\p{P}+`.
private func replaceRunsOfPunctuation(in word: String, with replacement: Character) -> String {
  var result = String()
  var inRun = false
  for character in word {
    if isPunctuation(character) {
      if !inRun {
        result.append(replacement)
        inRun = true
      }
    } else {
      result.append(character)
      inRun = false
    }
  }
  return result
}
