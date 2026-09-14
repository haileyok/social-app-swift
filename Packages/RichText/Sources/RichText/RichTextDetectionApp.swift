import Foundation

/// One item of a linkified string: either literal text or a detected link.
///
/// Ported from `DetectedLinkable` in the RN app's
/// `src/lib/strings/rich-text-detection.ts`, where it is `string | {link: string}`.
public enum DetectedLinkable: Hashable, Sendable {
  case text(String)
  case link(String)
}

/// Splits `text` into literal runs and detected links, mentions included.
///
/// Ported from `detectLinkables`. This is the RN app's own, older detection pass
/// used for plain-text linkification (Chat, profile descriptions); it is looser
/// than ``detectFacets(_:)`` - a mention counts as a "link", and the URL pattern
/// accepts any non-space run after a domain.
///
/// Offsets come out UTF-16-based from the regex, and text is sliced with those
/// offsets. Slicing by a UTF-16 offset into a Swift `String` would be a bug, so
/// the arithmetic here stays in UTF-16 space and only the final substrings are
/// converted - which is what the original does with JS string indices.
public func detectLinkables(_ text: String) -> [DetectedLinkable] {
  let string = text as NSString
  var segments: [DetectedLinkable] = []
  var start = 0

  for match in RichTextRegex.linkable.matches(in: text, range: NSRange(0..<string.length)) {
    var matchIndex = match.range.location
    var matchValue = string.substring(with: match.range)

    // A domain that is not a real TLD is not a link; the regex matched the
    // leading separator, so skip the whole match.
    if let domain = match.namedGroup("domain", in: string), !isValidDomain(domain) {
      continue
    }

    if matchValue.contains(where: \.isWhitespace) || matchValue.contains("(") {
      // HACK (upstream): skip the leading separator. The pattern has no negative
      // lookbehind - the RN engine cannot express one reliably - so it consumes
      // the space or "(" that precedes the link and steps back over it here.
      matchIndex += 1
      matchValue = String(matchValue.dropFirst())
    }

    // Strip a trailing sentence terminator, then an unbalanced ")".
    if let last = matchValue.last, ".,;!?".contains(last) {
      matchValue.removeLast()
    }
    if matchValue.hasSuffix(")") && !matchValue.contains("(") {
      matchValue.removeLast()
    }

    if start != matchIndex {
      segments.append(.text(string.substring(with: NSRange(start..<matchIndex))))
    }
    segments.append(.link(matchValue))
    start = matchIndex + (matchValue as NSString).length
  }

  if start < string.length {
    segments.append(.text(string.substring(from: start)))
  }
  return segments
}

/// The short form of a URL shown in the composer and in shortened posts.
///
/// Ported from `toShortUrl` in the RN app's `src/lib/strings/url-helpers.ts`.
/// Non-HTTP URLs and unparseable input are returned unchanged; `host` includes
/// the port when present; the root path `/` is dropped before measuring, and the
/// 13-character preview is followed by `...` (three periods, as upstream).
public func toShortUrl(_ url: String) -> String {
  guard let parsed = URL(string: url) else { return url }
  guard let scheme = parsed.scheme, scheme == "http" || scheme == "https" else { return url }
  let path = parsed.path() == "/" ? "" : parsed.path(percentEncoded: true)
  let suffix =
    path + (parsed.query(percentEncoded: true).map { "?" + $0 } ?? "")
    + (parsed.fragment(percentEncoded: true).map { "#" + $0 } ?? "")
  guard let host = parsed.host() else { return url }
  let hostWithPort = parsed.port.map { "\(host):\($0)" } ?? host
  if suffix.count > 15 {
    return hostWithPort + String(suffix.prefix(13)) + "..."
  }
  return hostWithPort + suffix
}
