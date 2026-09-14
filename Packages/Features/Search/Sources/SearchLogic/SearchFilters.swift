import Foundation

/// Structured advanced-search filters, ported 1:1 from the `SearchFilters`
/// type in `src/screens/Search/searchParams.ts`.
///
/// These are the values the advanced-search dialog collects. On the web build
/// they live as sibling URL query params next to `q`; in this port they are an
/// in-memory value the search state machine carries. All values are strings so
/// they serialize cleanly; multi-value fields (`tag`, `author`, ...) hold
/// whitespace-separated lists that split at the API boundary.
public struct SearchFilters: Hashable, Sendable, Codable {
  public var author: String?
  public var mentions: String?
  public var domain: String?
  public var url: String?
  public var tag: String?
  /// Exclude variants of the list fields above. v2-only; v1 has no structured
  /// exclude operators so these are dropped on the legacy path.
  public var excludeAuthor: String?
  public var excludeMentions: String?
  public var excludeDomain: String?
  public var excludeUrl: String?
  public var excludeTag: String?
  public var lang: String?
  public var since: String?
  public var until: String?
  /// `none` or `only`. Any other value is ignored by the builder.
  public var replies: String?
  /// `true` when set to the literal string `true`.
  public var media: String?
  /// `true` when set to the literal string `true`.
  public var video: String?
  /// `true` when set to the literal string `true`.
  public var following: String?
  /// `me` when the "Me" author filter is active.
  public var from: String?

  public init(
    author: String? = nil,
    mentions: String? = nil,
    domain: String? = nil,
    url: String? = nil,
    tag: String? = nil,
    excludeAuthor: String? = nil,
    excludeMentions: String? = nil,
    excludeDomain: String? = nil,
    excludeUrl: String? = nil,
    excludeTag: String? = nil,
    lang: String? = nil,
    since: String? = nil,
    until: String? = nil,
    replies: String? = nil,
    media: String? = nil,
    video: String? = nil,
    following: String? = nil,
    from: String? = nil
  ) {
    self.author = author
    self.mentions = mentions
    self.domain = domain
    self.url = url
    self.tag = tag
    self.excludeAuthor = excludeAuthor
    self.excludeMentions = excludeMentions
    self.excludeDomain = excludeDomain
    self.excludeUrl = excludeUrl
    self.excludeTag = excludeTag
    self.lang = lang
    self.since = since
    self.until = until
    self.replies = replies
    self.media = media
    self.video = video
    self.following = following
    self.from = from
  }

  /// Every filter key, in the order the RN `FILTER_PARAM_KEYS` tuple lists them.
  ///
  /// Counts and reads iterate this so an added field cannot be silently
  /// forgotten by ``countActiveFilters`` or ``definedParams``.
  public static let paramKeys: [SearchFilterKey] = [
    .author, .mentions, .domain, .url, .tag,
    .excludeAuthor, .excludeMentions, .excludeDomain, .excludeUrl, .excludeTag,
    .lang, .since, .until, .replies, .media, .video, .following, .from,
  ]

  /// Subscript over ``paramKeys``.
  public subscript(key: SearchFilterKey) -> String? {
    get {
      switch key {
      case .author: return author
      case .mentions: return mentions
      case .domain: return domain
      case .url: return url
      case .tag: return tag
      case .excludeAuthor: return excludeAuthor
      case .excludeMentions: return excludeMentions
      case .excludeDomain: return excludeDomain
      case .excludeUrl: return excludeUrl
      case .excludeTag: return excludeTag
      case .lang: return lang
      case .since: return since
      case .until: return until
      case .replies: return replies
      case .media: return media
      case .video: return video
      case .following: return following
      case .from: return from
      }
    }
    set {
      switch key {
      case .author: author = newValue
      case .mentions: mentions = newValue
      case .domain: domain = newValue
      case .url: url = newValue
      case .tag: tag = newValue
      case .excludeAuthor: excludeAuthor = newValue
      case .excludeMentions: excludeMentions = newValue
      case .excludeDomain: excludeDomain = newValue
      case .excludeUrl: excludeUrl = newValue
      case .excludeTag: excludeTag = newValue
      case .lang: lang = newValue
      case .since: since = newValue
      case .until: until = newValue
      case .replies: replies = newValue
      case .media: media = newValue
      case .video: video = newValue
      case .following: following = newValue
      case .from: from = newValue
      }
    }
  }

  /// The string key a filter uses as a route param / persisted field name.
  public enum SearchFilterKey: String, CaseIterable, Sendable {
    case author
    case mentions
    case domain
    case url
    case tag
    case excludeAuthor
    case excludeMentions
    case excludeDomain
    case excludeUrl
    case excludeTag
    case lang
    case since
    case until
    case replies
    case media
    case video
    case following
    case from
  }
}

extension SearchFilters {
  /// Reads filter params out of a route-params-like dictionary, keeping only
  /// non-empty string values.
  ///
  /// Ported from `readSearchFilters`. The literal string `undefined` is ignored
  /// because it leaks in from URL serialization on the web build.
  public static func read(from routeParams: [String: String?]?) -> SearchFilters {
    var filters = SearchFilters()
    guard let routeParams else { return filters }
    for key in SearchFilters.paramKeys {
      guard let value = routeParams[key.rawValue], let value, !value.isEmpty,
        value != "undefined"
      else { continue }
      filters[key] = value
    }
    return filters
  }

  /// True when any filter param is set.
  public var isActive: Bool { countActiveFilters() > 0 }

  /// Number of active filter params, used for the `[+N filters]` pill in search
  /// history. Each set key counts once, so a multi-value field like `author`
  /// counts as one filter regardless of how many handles it holds.
  public func countActiveFilters() -> Int {
    SearchFilters.paramKeys.count { self[$0] != nil }
  }

  /// Filter keys that restrict posts specifically, as opposed to `lang`, which
  /// applies equally to posts, people, and feeds.
  ///
  /// Used to decide whether the People/Feeds search tabs still make sense: a
  /// language alone should not hide them, but any post-only filter should.
  public var hasPostOnlyFilters: Bool {
    SearchFilters.paramKeys.contains { key in
      key != .lang && self[key] != nil
    }
  }

  /// Only the filter keys that have a value, omitting the rest entirely.
  ///
  /// Ported from `definedFilterParams`; safe for building a fresh URL because
  /// absent filters never appear.
  public var definedParams: [String: String] {
    var params: [String: String] = [:]
    for key in SearchFilters.paramKeys {
      if let value = self[key] { params[key.rawValue] = value }
    }
    return params
  }

  /// Expands filters to a params object covering every filter key, with absent
  /// keys set to `nil`.
  ///
  /// Ported from `filtersToRouteParams`: use with a merge-style param set so
  /// filters the user removed are cleared. On web the `definedParams` form is
  /// the correct one, since a literal `"undefined"` would leak into the URL.
  public var routeParams: [String: String?] {
    var params: [String: String?] = [:]
    for key in SearchFilters.paramKeys { params[key.rawValue] = self[key] }
    return params
  }

  /// Strips all filter keys from a params dictionary, leaving non-filter params
  /// (`q`, `tab`, `name`) intact.
  public static func withoutFilterParams(
    _ routeParams: [String: String?]?
  ) -> [String: String?] {
    var base = routeParams ?? [:]
    for key in SearchFilters.paramKeys { base[key.rawValue] = nil }
    return base
  }
}
