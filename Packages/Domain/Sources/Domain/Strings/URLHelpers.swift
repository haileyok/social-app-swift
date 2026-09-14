import ATSyntax
import Foundation

/// Port of `src/lib/strings/url-helpers.ts`.
///
/// Deviation: a handful of RN helpers operate on a Lingui-aware app config
/// (`getServiceAuthAudFromUrl` aside, they are all pure string work here). The
/// trusted-host list is a literal because the app's `BSKY_TRUSTED_HOSTS`
/// includes dev-only hosts under `__DEV__`; those are not ported.
public enum URLHelpers {

  /// The canonical web app host.
  public static let bskyAppHost = "https://bsky.app"

  /// Hosts that are Bluesky-operated PDSes end with this suffix.
  public static let bskyHostingEndsWith = ".host.bsky.network"

  /// The default service used for `bsky.social` handles.
  public static let bskyService = "https://bsky.social"

  /// Hosts trusted as internal Bluesky surfaces. The RN list drops the dev-only
  /// `localhost` entries; they are not ported.
  static let bskyTrustedHosts = [
    "bsky\\.app",
    "bsky\\.social",
    "blueskyweb\\.xyz",
    "blueskyweb\\.zendesk\\.com",
  ]

  /*
   * Allow any trusted host by itself or with a subdomain, plus relative paths
   * like `/profile` and a bare `#` fragment. Built from the same host list the
   * RN app interpolates, so the two stay aligned if the list changes.
   */
  static let trustedRegex: NSRegularExpression = {
    let hostAlternation = bskyTrustedHosts.joined(separator: "|([\\w-]+\\.)?")
    let pattern = "^(http(s)?://(([\\w-]+\\.)?\(hostAlternation))|/|#)"
    return try! NSRegularExpression(pattern: pattern)
  }()

  /// Invite codes are 7-10 alphanumeric characters.
  public static let chatInviteCodeRegex = try! NSRegularExpression(pattern: "^/chat/([a-zA-Z0-9]{7,10})$")

  // MARK: - URL parsing

  /// Whether `url` can be parsed, optionally relative to `base`.
  public static func canParseUrl(_ url: String, base: String? = nil) -> Bool {
    parseUrl(url, base: base) != nil
  }

  /// Mirrors `new URL(url, base)` for the cases the app cares about: absolute
  /// http(s) URLs and relative paths resolved against `base`.
  public static func parseUrl(_ url: String, base: String? = nil) -> URL? {
    if let parsed = URL(string: url), parsed.scheme != nil {
      return parsed
    }
    if let base, let baseURL = URL(string: base) {
      return URL(string: url, relativeTo: baseURL)
    }
    return nil
  }

  // MARK: - Domain checks

  /// Whether `str` ends with a known TLD (`tlds`npm package semantics):
  /// the TLD must be preceded by a `.` and end the string.
  public static func isValidDomain(_ str: String) -> Bool {
    for tld in TLDSuffixes.all {
      guard let range = str.range(of: tld, options: .backwards) else { continue }
      let startIndex = range.lowerBound
      // The character immediately before the TLD must be a dot.
      guard startIndex > str.startIndex else { continue }
      let before = str[str.index(before: startIndex)]
      guard before == "." else { continue }
      // The TLD must end the string.
      guard range.upperBound == str.endIndex else { continue }
      return true
    }
    return false
  }

  /// `at://` record URI from its parts.
  public static func makeRecordUri(didOrName: String, collection: String, rkey: String) -> String {
    "at://\(didOrName)/\(collection)/\(rkey)"
  }

  // MARK: - Display helpers

  /// `bsky.social` renders as "Bluesky Social"; otherwise the host.
  public static func toNiceDomain(_ url: String) -> String {
    guard let urlp = URL(string: url) else { return url }
    if "https://\(urlp.host ?? "")" == bskyService {
      return "Bluesky Social"
    }
    return (urlp.host?.isEmpty == false) ? urlp.host! : url
  }

  /// Host plus a truncated path (13 chars then `...` when the path is >15).
  public static func toShortUrl(_ url: String) -> String {
    guard let urlp = URL(string: url) else { return url }
    let scheme = urlp.scheme ?? ""
    guard scheme == "http" || scheme == "https" else { return url }
    let pathname = urlp.path == "/" ? "" : urlp.path
    let path = pathname + (urlp.query.map { "?\($0)" } ?? "") + (urlp.fragment.map { "#\($0)" } ?? "")
    let host = urlp.host ?? ""
    if path.count > 15 {
      return host + String(path.prefix(13)) + "..."
    }
    return host + path
  }

  /// Converts a path into an absolute `https://bsky.app` URL.
  ///
  /// Mirrors the JS `url.pathname = path` setter, which percent-encodes the
  /// path (notably `?` and `#`, which stop being delimiters once assigned).
  public static func toShareUrl(_ url: String) -> String {
    if url.hasPrefix("https") {
      return url
    }
    return bskyAppHost + encodePath(rawPath: url)
  }

  /// Percent-encodes a raw string as a URL path, matching the JS `pathname`
  /// setter: a leading `/` is added when absent, `/` is preserved, and `?`,
  /// `#`, spaces, and non-ASCII are escaped.
  static func encodePath(rawPath: String) -> String {
    let withLeadingSlash = rawPath.hasPrefix("/") ? rawPath : "/" + rawPath
    var allowed = CharacterSet.urlPathAllowed
    // `urlPathAllowed` permits `?` and `#`; the JS pathname setter does not.
    allowed.remove(charactersIn: "?#")
    return withLeadingSlash.addingPercentEncoding(withAllowedCharacters: allowed)
      ?? withLeadingSlash
  }

  /// Resolves `url` against ``bskyAppHost``.
  public static func toBskyAppUrl(_ url: String) -> String {
    if let parsed = URL(string: url, relativeTo: URL(string: bskyAppHost)) {
      return parsed.absoluteString
    }
    return url
  }

  /// `*.host.bsky.network` renders as "Bluesky"; otherwise the host.
  public static func toNiceHostingUrl(_ url: String) -> String {
    guard let urlp = URL(string: url) else { return url }
    if (urlp.host ?? "").hasSuffix(bskyHostingEndsWith) {
      return "Bluesky"
    }
    return urlp.host ?? url
  }

  /// True when `url` points at a Bluesky-operated PDS.
  public static func isBlueskyHostedUrl(_ url: String) -> Bool {
    guard let host = URL(string: url)?.host else { return false }
    let serviceHost = URL(string: bskyService)?.host
    return host == serviceHost || host.hasSuffix(bskyHostingEndsWith)
  }

  // MARK: - Bluesky URL classification

  public static func isBskyAppUrl(_ url: String) -> Bool {
    url.hasPrefix("https://bsky.app/")
  }

  public static func isRelativeUrl(_ url: String) -> Bool {
    guard url.hasPrefix("/") else { return false }
    let second = url.dropFirst()
    guard let first = second.first else { return false }
    return first != "/"
  }

  public static func isBskyRSSUrl(_ url: String) -> Bool {
    (url.hasPrefix("https://bsky.app/") || isRelativeUrl(url)) && matches(url, #"/rss/?$"#)
  }

  public static func isExternalUrl(_ url: String) -> Bool {
    let external = !isBskyAppUrl(url) && url.hasPrefix("http")
    let rss = isBskyRSSUrl(url)
    return external || rss
  }

  public static func isTrustedUrl(_ url: String) -> Bool {
    matchesRegex(url, trustedRegex)
  }

  public static func isBskyPostUrl(_ url: String) -> Bool {
    guard isBskyAppUrl(url), let urlp = URL(string: url) else { return false }
    return matches(urlp.path, #"/profile/[^/]+/post/[^/]+"#, caseInsensitive: true)
  }

  public static func isBskyCustomFeedUrl(_ url: String) -> Bool {
    guard isBskyAppUrl(url), let urlp = URL(string: url) else { return false }
    return matches(urlp.path, #"/profile/[^/]+/feed/[^/]+"#, caseInsensitive: true)
  }

  public static func isBskyListUrl(_ url: String) -> Bool {
    guard isBskyAppUrl(url), let urlp = URL(string: url) else { return false }
    return matches(urlp.path, #"/profile/[^/]+/lists/[^/]+"#, caseInsensitive: true)
  }

  public static func isBskyStartUrl(_ url: String) -> Bool {
    guard isBskyAppUrl(url), let urlp = URL(string: url) else { return false }
    return matches(urlp.path, #"/start/[^/]+/[^/]+"#)
  }

  public static func isBskyStarterPackUrl(_ url: String) -> Bool {
    guard isBskyAppUrl(url), let urlp = URL(string: url) else { return false }
    return matches(urlp.path, #"/starter-pack/[^/]+/[^/]+"#)
  }

  /// Extracts a chat invite code from an app URL or relative path.
  public static func getChatInviteCodeFromUrl(_ url: String) -> String? {
    let pathname: String
    if isBskyAppUrl(url) {
      guard let urlp = URL(string: url) else { return nil }
      pathname = urlp.path
    } else if url.hasPrefix("/") {
      pathname = url.split(separator: "?").first.map(String.init)?.split(separator: "#").first.map(String.init) ?? url
    } else {
      return nil
    }
    let ns = pathname as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = chatInviteCodeRegex.firstMatch(in: pathname, options: [], range: range),
      match.numberOfRanges > 1
    else {
      return nil
    }
    let capture = match.range(at: 1)
    return capture.location == NSNotFound ? nil : ns.substring(with: capture)
  }

  public static func isBskyChatInviteUrl(_ url: String) -> Bool {
    getChatInviteCodeFromUrl(url) != nil
  }

  public static func isBskyDownloadUrl(_ url: String) -> Bool {
    if isExternalUrl(url) { return false }
    return url == "/download" || url.hasPrefix("/download?")
  }

  /// Maps an app URL to an internal route, or a short link to its href.
  public static func convertBskyAppUrlIfNeeded(_ url: String) -> String {
    if isBskyAppUrl(url) {
      guard let urlp = URL(string: url) else { return url }
      if isBskyStartUrl(url) {
        return urlp.path.replacingOccurrences(of: "/start/", with: "/starter-pack/")
      }
      return urlp.path + (urlp.query.map { "?\($0)" } ?? "")
    } else if isShortLink(url) {
      return shortLinkToHref(url)
    }
    return url
  }

  // MARK: - Record URI to app route

  public static func listUriToHref(_ url: String) -> String {
    guard let atUri = try? AtUri(url), let rkey = atUri.rkey else { return "" }
    return "/profile/\(atUri.host)/lists/\(rkey)"
  }

  public static func feedUriToHref(_ url: String) -> String {
    guard let atUri = try? AtUri(url), let rkey = atUri.rkey else { return "" }
    return "/profile/\(atUri.host)/feed/\(rkey)"
  }

  /// Record URI to `/profile/<handle-or-did>/post/<rkey>`.
  public static func postUriToRelativePath(_ uri: String, handle: String? = nil)
    -> String? {
    guard let atUri = try? AtUri(uri), let rkey = atUri.rkey else { return nil }
    let handleOrDid = (handle != nil && !isInvalidHandle(handle!)) ? handle! : atUri.host
    return "/profile/\(handleOrDid)/post/\(rkey)"
  }

  /// `handle.invalid` is the app's placeholder for an unresolvable handle.
  public static func isInvalidHandle(_ handle: String) -> Bool {
    handle == "handle.invalid"
  }

  // MARK: - Link labels and warnings

  /// Whether the label in the post text mismatches the host of the link facet.
  public static func linkRequiresWarning(uri: String, label: String) -> Bool {
    let labelDomain = labelToDomain(label)

    // Relative URLs and `#` are trusted internal content.
    if isRelativeUrl(uri) || uri == "#" {
      return false
    }

    guard let urlp = URL(string: uri) else {
      return true
    }

    let host = (urlp.host ?? "").lowercased()
    if isTrustedUrl(uri) {
      // Internal link presented as a URL to another app.
      return labelDomain != nil && labelDomain != host && isPossiblyAUrl(labelDomain!)
    } else {
      // External link: warn when the label does not match the target.
      guard let labelDomain else { return true }
      return labelDomain != host
    }
  }

  /// A lowercase hostname when `label` is a valid URL, else `nil`.
  public static func labelToDomain(_ label: String) -> String? {
    if label.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
      return nil
    }
    if let urlp = URL(string: label), let host = urlp.host, !host.isEmpty {
      return host.lowercased()
    }
    if let urlp = URL(string: "https://" + label), let host = urlp.host, !host.isEmpty {
      return host.lowercased()
    }
    return nil
  }

  /// Whether `str` looks like a URL: an `http(s)://` prefix, or its first
  /// word/slash-segment is a valid domain.
  public static func isPossiblyAUrl(_ str: String) -> Bool {
    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("http://") { return true }
    if trimmed.hasPrefix("https://") { return true }
    let firstWord = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first.map(String.init) ?? ""
    return isValidDomain(firstWord)
  }

  /// Splits a hostname into `(subdomain-with-trailing-dot, apex-domain)`.
  ///
  /// Uses the Public Suffix List so multi-label public suffixes (`co.uk`,
  /// `github.io`) resolve to the right apex. Returns `["", hostname]` when the
  /// host is not listed, mirroring `psl`'s `error/!listed` fallback.
  public static func splitApexDomain(_ hostname: String) -> (subdomain: String, domain: String) {
    guard let registrable = PublicSuffixList.registrableDomain(of: hostname) else {
      return ("", hostname)
    }
    if registrable == hostname {
      return ("", hostname)
    }
    let sub = String(hostname.dropLast(registrable.count))
    return (sub, registrable)
  }

  // MARK: - Proxying and short links

  /// Absolute `https://bsky.app` URL from a path, stripping an existing host.
  public static func createBskyAppAbsoluteUrl(_ path: String) -> String {
    var sanitized = path.replacingOccurrences(of: bskyAppHost, with: "")
    while sanitized.hasPrefix("/") {
      sanitized.removeFirst()
    }
    var host = bskyAppHost
    while host.hasSuffix("/") { host.removeLast() }
    return "\(host)/\(sanitized)"
  }

  /// Wraps an http(s) URL in the bsky.app redirect proxy.
  public static func createProxiedUrl(_ url: String) -> String {
    guard let parsed = URL(string: url), let scheme = parsed.scheme,
      scheme == "http" || scheme == "https"
    else {
      return url
    }
    return "https://go.bsky.app/redirect?u=\(urlEncoded(url))"
  }

  public static func isShortLink(_ url: String) -> Bool {
    url.hasPrefix("https://go.bsky.app/")
  }

  /// A go.bsky.app short link with a single path segment becomes a
  /// `/starter-pack-short/<code>` route.
  public static func shortLinkToHref(_ url: String) -> String {
    guard let urlp = URL(string: url) else { return url }
    let parts = urlp.path.split(separator: "/").filter { !$0.isEmpty }
    if parts.count == 1 {
      return "/starter-pack-short/\(parts[0])"
    }
    return url
  }

  public static func getHostnameFromUrl(_ url: String) -> String? {
    URL(string: url)?.host
  }

  /// `did:web:<hostname>` for service-auth audiences.
  public static func getServiceAuthAudFromUrl(_ url: String) -> String? {
    guard let hostname = getHostnameFromUrl(url) else { return nil }
    return "did:web:\(hostname)"
  }

  /// Normalizes `maybeUrl` when it parses and has a letter TLD of >= 2 chars.
  ///
  /// Returns `URL.toString()`-shaped output: lowercased host, an empty path
  /// rendered as `/`, and the query/fragment preserved.
  public static func definitelyUrl(_ maybeUrl: String) -> String? {
    var candidate = maybeUrl
    if candidate.hasSuffix(".") { return nil }
    if !candidate.hasPrefix("https://") && !candidate.hasPrefix("http://") {
      candidate = "https://" + candidate
    }
    guard let url = URL(string: candidate), let hostname = url.host else { return nil }
    let labels = hostname.split(separator: ".")
    if labels.count < 2 { return nil }
    let tld = String(labels[labels.count - 1])
    guard matches(tld, #"^[a-z]{2,}$"#, caseInsensitive: true) else { return nil }
    return normalizedUrlString(url)
  }

  /// Rebuilds a URL the way the JS `URL` object's `toString()` does for the
  /// components this app touches.
  static func normalizedUrlString(_ url: URL) -> String {
    let scheme = (url.scheme ?? "").lowercased()
    let host = (url.host ?? "").lowercased()
    var result = "\(scheme)://\(host)"
    if let port = url.port {
      result += ":\(port)"
    }
    let path = url.path
    result += path.isEmpty ? "/" : path
    if let query = url.query {
      result += "?\(query)"
    }
    if let fragment = url.fragment {
      result += "#\(fragment)"
    }
    return result
  }

  // MARK: - Internal regex helpers

  static func matches(_ value: String, _ pattern: String, caseInsensitive: Bool = false) -> Bool {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return false
    }
    let range = NSRange(location: 0, length: (value as NSString).length)
    return regex.firstMatch(in: value, options: [], range: range) != nil
  }

  static func matchesRegex(_ value: String, _ regex: NSRegularExpression) -> Bool {
    let range = NSRange(location: 0, length: (value as NSString).length)
    return regex.firstMatch(in: value, options: [], range: range) != nil
  }

  /// `encodeURIComponent` semantics: unreserved characters `A-Za-z0-9-_.!~*'()`
  /// are untouched.
  static func urlEncoded(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}
