import Foundation

/// Structured `app.bsky.feed.searchPosts` params lifted out of a free-text
/// query, ported 1:1 from `ExtractedSearchParams` in
/// `src/state/queries/search-posts-params.ts`.
///
/// Recognized operators are stripped from ``q``; everything else (free text,
/// quoted phrases, OR groups, unsupported operators) stays in ``q`` verbatim.
public struct ExtractedSearchParams: Hashable, Sendable {
  /// The free text left after supported operators were lifted out.
  public var q: String
  public var author: String?
  public var mentions: String?
  public var domain: String?
  public var url: String?
  public var lang: String?
  public var since: String?
  public var until: String?
  public var tag: [String]?

  public init(
    q: String,
    author: String? = nil,
    mentions: String? = nil,
    domain: String? = nil,
    url: String? = nil,
    lang: String? = nil,
    since: String? = nil,
    until: String? = nil,
    tag: [String]? = nil
  ) {
    self.q = q
    self.author = author
    self.mentions = mentions
    self.domain = domain
    self.url = url
    self.lang = lang
    self.since = since
    self.until = until
    self.tag = tag
  }
}

/// Pure helpers for lifting structured `searchPosts` params out of a query.
///
/// Ported from `src/state/queries/search-posts-params.ts`. Kept free of any
/// store or network dependency so it can be unit tested in isolation.
public enum SearchQueryParams {
  /// True when `value` starts with a `YYYY-MM-DD` date prefix.
  ///
  /// The RN helper is `/^\d{4}-\d{2}-\d{2}/`; only the date portion is required
  /// for a `since`/`until` operator to be recognized, so an explicit prefix
  /// check is equivalent and avoids a shared `Regex` value.
  static func hasDatePrefix(_ value: String) -> Bool {
    let parts = value.prefix(10)
    guard parts.count == 10 else { return false }
    for (index, char) in parts.enumerated() {
      if index == 4 || index == 7 {
        guard char == "-" else { return false }
      } else {
        guard char.isASCII, char.isNumber else { return false }
      }
    }
    return true
  }

  /// Strips a leading `@` from a handle so `from:@alice.bsky.social` and
  /// `from:alice.bsky.social` resolve to the same author.
  ///
  /// Mirrors the marker stripping the advanced-search dialog applies, which
  /// otherwise 400s the appview.
  static func stripHandleMarker(_ value: String) -> String {
    value.hasPrefix("@") ? String(value.dropFirst()) : value
  }

  /// Splits a query into whitespace-delimited tokens, keeping quoted phrases
  /// (`"a b"`) and parenthesized OR groups (`(a OR b)`) intact so they pass
  /// through to `q` untouched.
  ///
  /// Ported verbatim from `tokenizeQuery`, including its tolerant handling of an
  /// unterminated quote or paren (the remainder becomes one token).
  public static func tokenize(_ raw: String) -> [String] {
    let chars = Array(raw)
    var tokens: [String] = []
    var i = 0
    let n = chars.count
    while i < n {
      if chars[i].isWhitespace {
        i += 1
        continue
      }
      let start = i
      if chars[i] == "(" {
        var depth = 0
        while i < n {
          if chars[i] == "(" {
            depth += 1
          } else if chars[i] == ")" {
            depth -= 1
            if depth == 0 {
              i += 1
              break
            }
          }
          i += 1
        }
        tokens.append(String(chars[start..<i]))
        continue
      }
      var buf = ""
      while i < n, !chars[i].isWhitespace, chars[i] != "(" {
        if chars[i] == "\"" {
          buf.append(chars[i])
          i += 1
          while i < n, chars[i] != "\"" {
            buf.append(chars[i])
            i += 1
          }
          if i < n {
            buf.append(chars[i])
            i += 1
          }
        } else {
          buf.append(chars[i])
          i += 1
        }
      }
      if !buf.isEmpty { tokens.append(buf) }
    }
    return tokens
  }

  /// Splits a bare `from:me` token out of a query.
  ///
  /// The "Me" author filter always travels inside `q` as a `from:me` token (the
  /// backend resolves `me` to the viewer), but the UI never shows it as text.
  /// Tokenization keeps quoted phrases intact, so a `from:me` inside quotes
  /// stays in the query text.
  public static func extractFromMe(_ query: String) -> (q: String, fromMe: Bool) {
    let tokens = tokenize(query)
    let kept = tokens.filter { $0 != "from:me" }
    return (kept.joined(separator: " "), kept.count != tokens.count)
  }

  /// Re-appends the `from:me` token when the "Me" author filter is active.
  ///
  /// Idempotent: a query that already carries a bare `from:me` is returned as-is.
  public static func appendFromMe(_ query: String, fromMe: Bool) -> String {
    guard fromMe else { return query }
    if tokenize(query).contains("from:me") { return query }
    return query.isEmpty ? "from:me" : "\(query) from:me"
  }

  /// Lifts the operators that `app.bsky.feed.searchPosts` accepts as structured
  /// params out of the free-text query so the backend filters on them directly.
  ///
  /// Singular params keep the first value seen; `tag` accumulates because the
  /// lexicon AND-matches multiple tags.
  public static func extract(_ query: String) -> ExtractedSearchParams {
    var result = ExtractedSearchParams(q: "")
    var remaining: [String] = []
    var tags: [String] = []

    for token in tokenize(query) {
      if token.hasPrefix("#"), token.count > 1, !token.contains(":") {
        tags.append(String(token.dropFirst()))
        continue
      }

      guard let colonIdx = token.firstIndex(of: ":") else {
        remaining.append(token)
        continue
      }

      let op = String(token[token.startIndex..<colonIdx])
      let value = String(token[token.index(after: colonIdx)...])
      if value.isEmpty {
        remaining.append(token)
        continue
      }

      switch op {
      case "from":
        // `me` is resolved by the backend, so leave it in the query text.
        if value == "me" { remaining.append(token) } else { result.author = result.author ?? stripHandleMarker(value) }
      case "mentions", "to":
        if value == "me" {
          remaining.append(token)
        } else {
          result.mentions = result.mentions ?? stripHandleMarker(value)
        }
      case "domain":
        result.domain = result.domain ?? value
      case "url":
        result.url = result.url ?? value
      case "lang":
        result.lang = result.lang ?? value
      case "since":
        if hasDatePrefix(value) { result.since = result.since ?? value } else { remaining.append(token) }
      case "until":
        if hasDatePrefix(value) { result.until = result.until ?? value } else { remaining.append(token) }
      default:
        // Unsupported operator (`replies:`, `media:`, ...) - keep in q.
        remaining.append(token)
      }
    }

    if !tags.isEmpty { result.tag = tags }
    result.q = remaining.joined(separator: " ")
    return result
  }
}
