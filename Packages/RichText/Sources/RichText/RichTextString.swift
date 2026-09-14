import Foundation

/// Renders rich text as a plain string, expanding or eliding links.
///
/// Ported from `richTextToString` in the RN app's
/// `src/lib/strings/rich-text-helpers.ts`. A link whose label does not match its
/// destination is a spoofing risk: in `loose` mode it is rendered as Markdown
/// `[label](href)` so the destination stays visible, and otherwise it collapses
/// to just the label.
///
/// The RN version decides with `linkRequiresWarning`, which needs the app's
/// trusted-host list and URL parsing. That lives in an app-level package, so the
/// caller supplies the predicate; see ``linkRequiresWarning(href:label:isTrusted:)``
/// for the ported default.
public func richTextToString(
  _ richText: RichText,
  loose: Bool = false,
  linkRequiresWarning: (String, String) -> Bool
) -> String {
  let facets = richText.facets
  guard let facets, !facets.isEmpty else { return richText.text }

  var result = ""
  for segment in richText.segments() {
    if let href = segment.link {
      let label = segment.text
      result +=
        linkRequiresWarning(href, label)
        ? (loose ? "[\(label)](\(href))" : label)
        : href
    } else {
      result += segment.text
    }
  }
  return result
}

/// Convenience form of ``richTextToString(_:loose:linkRequiresWarning:)`` taking
/// the trusted-host predicate directly.
public func richTextToString(
  _ richText: RichText,
  loose: Bool = false,
  isTrusted: (String) -> Bool
) -> String {
  richTextToString(richText, loose: loose) { href, label in
    linkRequiresWarning(href: href, label: label, isTrusted: isTrusted)
  }
}

/// Whether a link's visible label misrepresents where it goes.
///
/// Ported from `linkRequiresWarning` in the RN app's `src/lib/strings/url-helpers.ts`.
/// Relative URLs (internal app links) and bare `#` never warn. A URL that cannot
/// be parsed always warns.
///
/// - Parameters:
///   - href: the link destination.
///   - label: the visible link text.
///   - isTrusted: whether `href` points at a Bluesky-operated host. The RN
///     original consults its `BSKY_TRUSTED_HOSTS` regex, which is app-level
///     policy rather than engine behaviour, so it is injected here.
public func linkRequiresWarning(
  href: String,
  label: String,
  isTrusted: (String) -> Bool
) -> Bool {
  let labelDomain = labelToDomain(label)

  // Internal content - we know where it goes.
  if isRelativeUrl(href) || href == "#" {
    return false
  }

  guard let parsed = URL(string: href), let rawHost = parsed.host() else {
    return true
  }
  let host = rawHost.lowercased()

  if isTrusted(href) {
    // Trusted host: warn only if the label claims to be some other URL.
    guard let labelDomain else { return false }
    return labelDomain != host && isPossiblyAUrl(labelDomain)
  }
  guard let labelDomain else { return true }
  return labelDomain != host
}

/// The lowercased host of `label` if it reads as a URL, else `nil`.
///
/// Ported from `labelToDomain`. Parsing is tried as-is first, then with
/// `https://` prepended, so a bare `example.com` label resolves.
public func labelToDomain(_ label: String) -> String? {
  // Any whitespace rules the label out immediately.
  guard !label.contains(where: \.isWhitespace) else { return nil }
  if let host = URL(string: label)?.host() { return host.lowercased() }
  if let host = URL(string: "https://" + label)?.host() { return host.lowercased() }
  return nil
}

/// Whether `string` looks like it should be a URL but might be a spoofed label.
///
/// Ported from `isPossiblyAUrl`: an explicit scheme is enough, and otherwise the
/// first whitespace- or slash-delimited word must be a domain.
public func isPossiblyAUrl(_ string: String) -> Bool {
  let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }
  let firstWord = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first ?? ""
  return isValidDomain(String(firstWord))
}

/// Whether `url` is an in-app path, i.e. a slash followed by something other than
/// another slash.
///
/// Ported from `isRelativeUrl`.
public func isRelativeUrl(_ url: String) -> Bool {
  guard url.hasPrefix("/") else { return false }
  guard url.count > 1 else { return false }
  return url[url.index(after: url.startIndex)] != "/"
}
