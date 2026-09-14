import ATSyntax
import Foundation

/// The parts of a starter-pack URI, RN's `parseStarterPackUri` result.
public struct ParsedStarterPackURI: Sendable, Equatable {
  /// The authority: a DID for an `at://` URI, a handle for an `https://` one.
  public let name: String
  /// The record key.
  public let rkey: String

  /// Creates a parsed URI.
  public init(name: String, rkey: String) {
    self.name = name
    self.rkey = rkey
  }
}

/// Starter-pack URI construction and parsing.
///
/// Port of `src/lib/strings/starter-pack.ts`. All builders return the same
/// strings RN produces, so a shared link and an in-app navigation agree byte for
/// byte.
public enum StarterPackURI {
  /// The collection every starter pack record lives under.
  public static let collection = "app.bsky.graph.starterpack"
  /// The collection a pack's backing list lives under.
  public static let listCollection = "app.bsky.graph.list"
  /// The collection a list membership lives under.
  public static let listItemCollection = "app.bsky.graph.listitem"

  // MARK: - Parsing

  /// Parses an `at://` or `https://bsky.app/...` starter-pack URI.
  ///
  /// Port of `parseStarterPackUri`. Returns nil for a URI that is not a starter
  /// pack, that has no rkey, or that a path has the wrong shape for.
  ///
  /// - Note: RN accepts both `/starter-pack/<name>/<rkey>` and the legacy
  ///   `/start/<name>/<rkey>` web path; both are recognized here.
  public static func parse(_ uri: String?) -> ParsedStarterPackURI? {
    guard let uri, !uri.isEmpty else { return nil }

    if uri.hasPrefix("at://") {
      guard let atURI = try? AtUri(uri) else { return nil }
      guard atURI.collection == collection, !atURI.rkeySafe.isEmpty else { return nil }
      return ParsedStarterPackURI(name: atURI.host, rkey: atURI.rkeySafe)
    }

    guard let url = URL(string: uri) else { return nil }
    let parts = url.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    // `/starter-pack/<name>/<rkey>` splits to ["", "starter-pack", name, rkey].
    guard parts.count == 4 else { return nil }
    let path = parts[1]
    guard path == "starter-pack" || path == "start" else { return nil }
    let name = parts[2]
    let rkey = parts[3]
    guard !name.isEmpty, !rkey.isEmpty else { return nil }
    return ParsedStarterPackURI(name: name, rkey: rkey)
  }

  /// Converts an http(s) pack URI to its `at://` form, or nil.
  ///
  /// Port of `httpStarterPackUriToAtUri`. An `at://` input is returned
  /// unchanged.
  public static func httpToAtURI(_ httpURI: String?) -> String? {
    guard let httpURI else { return nil }
    guard let parsed = parse(httpURI) else { return nil }
    if httpURI.hasPrefix("at://") { return httpURI }
    return makeURI(did: parsed.name, rkey: parsed.rkey)
  }

  // MARK: - Building

  /// `at://<did>/app.bsky.graph.starterpack/<rkey>`.
  ///
  /// Port of `createStarterPackUri`.
  public static func makeURI(did: String, rkey: String) -> String {
    "at://\(did)/\(collection)/\(rkey)"
  }

  /// The app share link `https://bsky.app/start/<name>/<rkey>`.
  ///
  /// Port of `makeStarterPackLink`. `name` is a handle for a shareable link
  /// (RN's screen passes `creator.handle`), not a DID.
  public static func appShareLink(name: String, rkey: String) -> String {
    "https://bsky.app/start/\(name)/\(rkey)"
  }

  /// The card image `https://ogcard.cdn.bsky.app/start/<did>/<rkey>`.
  ///
  /// Port of `getStarterPackOgCard`.
  public static func ogCardURL(creatorDID: String, rkey: String) -> String {
    "https://ogcard.cdn.bsky.app/start/\(creatorDID)/\(rkey)"
  }

  /// Rewrites a `/start/` web path to `/starter-pack/`.
  ///
  /// Port of `startUriToStarterPackUri`.
  public static func startToStarterPackPath(_ uri: String) -> String {
    uri.replacingOccurrences(of: "/start/", with: "/starter-pack/")
  }

  /// The Google Play referrer URI that carries a pack through app install.
  ///
  /// Port of `createStarterPackGooglePlayUri`. Returns nil for an empty name or
  /// rkey, matching RN's early return.
  public static func googlePlayURI(name: String, rkey: String) -> String? {
    guard !name.isEmpty, !rkey.isEmpty else { return nil }
    return "https://play.google.com/store/apps/details?id=xyz.blueskyweb.app"
      + "&referrer=utm_source%3Dbluesky%26utm_medium%3Dstarterpack"
      + "%26utm_content%3Dstarterpack_\(name)_\(rkey)"
  }

  /// Recovers a pack URI from an Android install referrer query string.
  ///
  /// Port of `createStarterPackLinkFromAndroidReferrer`. The referrer is a bare
  /// query string (not a full URL), so it is parsed as one. Returns nil unless
  /// the source is `bluesky` and the content is exactly
  /// `starterpack_<name>_<rkey>`.
  public static func fromAndroidReferrer(_ referrerQueryString: String) -> String? {
    guard let url = URL(string: "http://throwaway.com/?\(referrerQueryString)") else {
      return nil
    }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard let utmContent = items.first(where: { $0.name == "utm_content" })?.value else {
      return nil
    }
    guard items.first(where: { $0.name == "utm_source" })?.value == "bluesky" else { return nil }

    let contentParts = utmContent.split(separator: "_", omittingEmptySubsequences: false).map(
      String.init)
    guard contentParts.count == 3, contentParts[0] == "starterpack" else { return nil }
    return makeURI(did: contentParts[1], rkey: contentParts[2])
  }
}

/// The record with the given key, or nil.
extension ParsedStarterPackURI {
  /// The `at://` URI this parse describes, when its authority is a DID.
  public var atURI: String {
    StarterPackURI.makeURI(did: name, rkey: rkey)
  }
}
