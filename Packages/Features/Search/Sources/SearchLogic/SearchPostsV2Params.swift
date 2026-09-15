import Foundation

/// A field of the `app.bsky.feed.searchPostsV2` filter param set.
///
/// The v2 endpoint renamed v1's singular operators to plural arrays and `lang`
/// to `language`. Modeling the set as an enum - rather than as free-form
/// key/value strings - means the builder cannot emit a param the lexicon does
/// not have, and a test can assert the whole param map structurally.
public enum SearchPostsV2FilterField: String, CaseIterable, Sendable {
  case authors
  case mentions
  case domains
  case urls
  case hashtags
  case excludeAuthors
  case excludeMentions
  case excludeDomains
  case excludeUrls
  case excludeHashtags
  case languages
  case since
  case until
  case hasMedia
  case hasVideo
  case following
  case excludeReplies
  case repliesOnly
}

/// One filter value: a list field or a flag/scalar field.
public enum SearchPostsV2FilterValue: Hashable, Sendable {
  case list([String])
  case flag(Bool)
  case scalar(String)
}

/// The structured filter params for `app.bsky.feed.searchPostsV2`, minus
/// `query`/`limit`/`cursor`/`sort`, which the caller owns.
///
/// Ordered by ``SearchPostsV2FilterField/allCases`` so encoding is deterministic
/// and the param table a test asserts is stable.
public struct SearchPostsV2Filters: Sendable, Equatable {
  /// Values keyed by field. Absent keys are omitted from the request entirely.
  public var values: [SearchPostsV2FilterField: SearchPostsV2FilterValue]

  public init(values: [SearchPostsV2FilterField: SearchPostsV2FilterValue] = [:]) {
    self.values = values
  }

  public subscript(field: SearchPostsV2FilterField) -> SearchPostsV2FilterValue? {
    values[field]
  }

  /// The fields present, in canonical order.
  public var fields: [SearchPostsV2FilterField] {
    SearchPostsV2FilterField.allCases.filter { values[$0] != nil }
  }
}

extension SearchPostsV2Filters {
  /// Builds the `searchPostsV2` filter params from the operators embedded in the
  /// query string plus the structured advanced-search dialog filters.
  ///
  /// Ported 1:1 from `buildSearchPostsV2Filters`. The two sources are merged
  /// rather than overriding each other: list fields union their values, and
  /// scalar fields prefer the explicit dialog filter, falling back to the
  /// embedded operator.
  public static func build(
    embedded: ExtractedSearchParams,
    filters: SearchFilters? = nil
  ) -> SearchPostsV2Filters {
    let api = filters.map(SearchPostsV2Filters.fromDialogFilters) ?? .init()
    var params = SearchPostsV2Filters()

    if let authors = mergeList(embedded.author.map { [$0] }, api.authors) {
      params.values[.authors] = .list(authors)
    }
    if let mentions = mergeList(embedded.mentions.map { [$0] }, api.mentions) {
      params.values[.mentions] = .list(mentions)
    }
    if let domains = mergeList(embedded.domain.map { [$0] }, api.domains) {
      params.values[.domains] = .list(domains)
    }
    if let urls = mergeList(embedded.url.map { [$0] }, api.urls) {
      params.values[.urls] = .list(urls)
    }
    if let hashtags = mergeList(embedded.tag, api.hashtags) {
      params.values[.hashtags] = .list(hashtags)
    }

    let language = api.language ?? embedded.lang
    // NOTE: the language selector is single-select today, matching the RN
    // implementation (`filtersToApiParams` collapses `language` to one value).
    if let language { params.values[.languages] = .list([language]) }

    if let since = parseTimestamp(api.since ?? embedded.since) {
      params.values[.since] = .scalar(since)
    }
    if let until = parseTimestamp(api.until ?? embedded.until) {
      params.values[.until] = .scalar(until)
    }

    /*
     * Exclude lists have no embedded query-string source (operators like
     * `from:` are always include), so they pass straight through from the
     * dialog filters.
     */
    if let excludeAuthors = api.excludeAuthors {
      params.values[.excludeAuthors] = .list(excludeAuthors)
    }
    if let excludeMentions = api.excludeMentions {
      params.values[.excludeMentions] = .list(excludeMentions)
    }
    if let excludeDomains = api.excludeDomains {
      params.values[.excludeDomains] = .list(excludeDomains)
    }
    if let excludeUrls = api.excludeUrls {
      params.values[.excludeUrls] = .list(excludeUrls)
    }
    if let excludeHashtags = api.excludeHashtags {
      params.values[.excludeHashtags] = .list(excludeHashtags)
    }

    if api.hasMedia { params.values[.hasMedia] = .flag(true) }
    if api.hasVideo { params.values[.hasVideo] = .flag(true) }
    if api.following { params.values[.following] = .flag(true) }
    if api.excludeReplies { params.values[.excludeReplies] = .flag(true) }
    if api.repliesOnly { params.values[.repliesOnly] = .flag(true) }

    return params
  }

  /// Concatenates two optional value lists, dropping empties and duplicates
  /// while preserving order.
  ///
  /// Used to union the back-compat operators embedded in the query string with
  /// the explicit dialog filters so neither source clobbers the other.
  static func mergeList(_ a: [String]?, _ b: [String]?) -> [String]? {
    var seen = Set<String>()
    var merged: [String] = []
    for value in (a ?? []) + (b ?? []) where seen.insert(value).inserted {
      merged.append(value)
    }
    return merged.isEmpty ? nil : merged
  }

  /// Only the date is used; the time is appended here since the lexicon expects
  /// a datetime value.
  ///
  /// Ported from `parseTimestamp`, which is `new Date(value).toISOString().split('.')[0] + 'Z'`:
  /// a `YYYY-MM-DD` value becomes midnight UTC, a value that already carries a
  /// time keeps it (fractional seconds dropped), and an unparseable value is
  /// dropped rather than throwing.
  ///
  /// The full-date form is tried *second*: `ISO8601DateFormatter` with
  /// `.withFullDate` still matches a trailing time and discards it, which would
  /// silently truncate an explicit timestamp to midnight.
  static func parseTimestamp(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    let full = ISO8601DateFormatter()
    full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let internet = ISO8601DateFormatter()
    internet.formatOptions = [.withInternetDateTime]
    let dateOnly = ISO8601DateFormatter()
    dateOnly.formatOptions = [.withFullDate]

    let candidates = [full, internet, dateOnly]
    guard let date = candidates.lazy.compactMap({ $0.date(from: value) }).first else {
      return nil
    }
    let out = ISO8601DateFormatter()
    out.formatOptions = [.withInternetDateTime]
    out.timeZone = TimeZone(secondsFromGMT: 0)
    return out.string(from: date)
  }
}

/// The dialog-filter projection of ``SearchFilters``, the port of
/// `filtersToApiParams`.
///
/// `language` is the v2 name for the filter's `lang`; `hasMedia`/`hasVideo`/
/// `following`/`excludeReplies`/`repliesOnly` are v2-only booleans with no v1
/// equivalent.
public struct SearchPostsDialogFilterParams: Sendable, Equatable {
  public var authors: [String]?
  public var mentions: [String]?
  public var domains: [String]?
  public var urls: [String]?
  public var hashtags: [String]?
  public var excludeAuthors: [String]?
  public var excludeMentions: [String]?
  public var excludeDomains: [String]?
  public var excludeUrls: [String]?
  public var excludeHashtags: [String]?
  public var language: String?
  public var since: String?
  public var until: String?
  public var hasMedia: Bool = false
  public var hasVideo: Bool = false
  public var following: Bool = false
  public var excludeReplies: Bool = false
  public var repliesOnly: Bool = false

  public init() {}
}

extension SearchPostsV2Filters {
  /// Applies the dialog-filter → v2-param mapping for one multi-value key.
  ///
  /// Search v1 honored only the first value for the singular lexicon params
  /// (`author`/`domain`/`url`); v2 accepts every value and renames them to the
  /// plural forms. `tag` becomes `hashtags`; `mentions` keeps its name. The
  /// exclude* keys map to v2's matching exclude* params. Expressed as a switch
  /// rather than a static key-path map so no non-`Sendable` value is shared
  /// across isolation domains.
  static func multiValueField(
    for key: SearchFilters.SearchFilterKey
  ) -> SearchPostsV2FilterField? {
    switch key {
    case .author: return .authors
    case .mentions: return .mentions
    case .domain: return .domains
    case .url: return .urls
    case .tag: return .hashtags
    case .excludeAuthor: return .excludeAuthors
    case .excludeMentions: return .excludeMentions
    case .excludeDomain: return .excludeDomains
    case .excludeUrl: return .excludeUrls
    case .excludeTag: return .excludeHashtags
    default: return nil
    }
  }

  /// Splits a whitespace-separated dialog filter value into a value list.
  static func splitList(_ raw: String) -> [String] {
    raw.split(whereSeparator: \.isWhitespace).map(String.init)
  }

  /// Converts dialog filters into structured params for
  /// `app.bsky.feed.searchPostsV2`, the port of `filtersToApiParams`.
  ///
  /// List fields are split on whitespace into arrays; scalar fields pass
  /// through. Split into two helpers so neither half carries the whole branch
  /// count.
  public static func fromDialogFilters(_ filters: SearchFilters) -> SearchPostsDialogFilterParams {
    var params = SearchPostsDialogFilterParams()
    applyMultiValueFields(filters, to: &params)
    applyScalarFields(filters, to: &params)
    return params
  }

  /// Applies the list-valued dialog fields.
  static func applyMultiValueFields(
    _ filters: SearchFilters, to params: inout SearchPostsDialogFilterParams
  ) {
    for key in SearchFilters.paramKeys {
      guard let raw = filters[key], let field = multiValueField(for: key) else { continue }
      let values = splitList(raw)
      guard !values.isEmpty else { continue }
      applyList(values, to: field, params: &params)
    }
  }

  /// Writes one parsed list to its destination field.
  static func applyList(
    _ values: [String], to field: SearchPostsV2FilterField,
    params: inout SearchPostsDialogFilterParams
  ) {
    switch field {
    case .authors: params.authors = values
    case .mentions: params.mentions = values
    case .domains: params.domains = values
    case .urls: params.urls = values
    case .hashtags: params.hashtags = values
    case .excludeAuthors: params.excludeAuthors = values
    case .excludeMentions: params.excludeMentions = values
    case .excludeDomains: params.excludeDomains = values
    case .excludeUrls: params.excludeUrls = values
    case .excludeHashtags: params.excludeHashtags = values
    default: break
    }
  }

  /// Applies the scalar and boolean dialog fields.
  static func applyScalarFields(
    _ filters: SearchFilters, to params: inout SearchPostsDialogFilterParams
  ) {
    if let lang = filters.lang { params.language = lang }
    if let since = filters.since { params.since = since }
    if let until = filters.until { params.until = until }
    if filters.media == "true" { params.hasMedia = true }
    if filters.video == "true" { params.hasVideo = true }
    if filters.following == "true" { params.following = true }
    if filters.replies == "none" {
      params.excludeReplies = true
    } else if filters.replies == "only" {
      params.repliesOnly = true
    }
  }
}
