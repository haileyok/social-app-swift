import ATSyntax
import Foundation
import Lexicons

/// Port of `src/lib/link-meta/link-meta.ts` - the metadata result types and the
/// `LikelyType` classification. Actual HTTP fetching (the `fetch` to the link
/// meta proxy) is out of scope; ``LinkMeta/applyingProxyBody(_:to:shouldFollowRedirect:)``
/// maps a decoded proxy response body, which is the pure part.
public enum LikelyType: String, Hashable, Sendable, CaseIterable {
  case html
  case text
  case image
  case video
  case audio
  case atpData
  case other
}

/// Metadata for a link, as produced by the link meta proxy.
public struct LinkMeta: Hashable, Sendable {
  public var error: String?
  public var likelyType: LikelyType
  public var url: String
  public var title: String?
  public var description: String?
  public var image: String?
  /// The strong refs of the Atmosphere records representing this external
  /// content (`app.bsky.embed.external#external.associatedRefs`).
  public var associatedRefs: [Com.Atproto.RepoStrongRef]?
  /// The hydrated embed view for this link (`app.bsky.embed.external#view`).
  public var view: App.Bsky.EmbedExternal_View?

  public init(
    error: String? = nil,
    likelyType: LikelyType,
    url: String,
    title: String? = nil,
    description: String? = nil,
    image: String? = nil,
    associatedRefs: [Com.Atproto.RepoStrongRef]? = nil,
    view: App.Bsky.EmbedExternal_View? = nil
  ) {
    self.error = error
    self.likelyType = likelyType
    self.url = url
    self.title = title
    self.description = description
    self.image = image
    self.associatedRefs = associatedRefs
    self.view = view
  }
}

/// A JSON value from the proxy response body, decoded without losing anything.
public enum LinkMetaValue: Hashable, Sendable {
  case string(String)
  case object([String: LinkMetaValue])
  case array([LinkMetaValue])
  case null
  case other
}

extension LinkMeta {
  /// The image-extension pattern from the RN source (`IMAGE_PATH_REGEX`,
  /// case-insensitive).
  static let imagePathRegex: NSRegularExpression = {
    try! NSRegularExpression(
      pattern: #"\.(?:apng|avif|bmp|gif|heic|heif|ico|jpe?g|jxl|png|svgz?|tiff?|webp)$"#,
      options: [.caseInsensitive])
  }()

  /// Classifies a URL string. Unparseable input is ``LikelyType/other``.
  ///
  /// The RN code passes the string to `new URL(url)`, which requires an
  /// absolute URL; a bare word like `notaurl` throws. Foundation accepts a
  /// relative string, so a missing scheme is treated as unparseable here.
  public static func getLikelyType(from urlString: String) -> LikelyType {
    guard let url = URL(string: urlString), url.scheme != nil else {
      return .other
    }
    return getLikelyType(fromPath: url.path)
  }

  /// Classifies a parsed URL. The image pattern on the path yields
  /// ``LikelyType/image``; otherwise ``LikelyType/html``.
  public static func getLikelyType(from url: URL) -> LikelyType {
    getLikelyType(fromPath: url.path)
  }

  static func getLikelyType(fromPath path: String) -> LikelyType {
    let range = NSRange(location: 0, length: (path as NSString).length)
    return imagePathRegex.firstMatch(in: path, options: [], range: range) != nil ? .image : .html
  }

  /// The pre-network decision in `getLinkMeta`: an app URL that is not a
  /// starter pack is already Atmosphere data, so no fetch is needed.
  public static func preflightType(url: String) -> LikelyType? {
    if URLHelpers.isBskyAppUrl(url) && parseStarterPackUri(url) == nil {
      return .atpData
    }
    return nil
  }

  /// Applies the proxy body fields onto `meta`, matching the RN assignments.
  ///
  /// `shouldFollowRedirect` mirrors the SoundCloud-shortlink case: the proxy's
  /// resolved `url` replaces the original only then.
  public static func applyingProxyBody(
    _ body: [String: LinkMetaValue],
    to meta: LinkMeta,
    shouldFollowRedirect: Bool
  ) -> LinkMeta {
    var meta = meta
    if case .string(let description) = body["description"] { meta.description = description }
    if case .string(let image) = body["image"] { meta.image = image }
    if case .string(let title) = body["title"] { meta.title = title }
    if case .string(let url) = body["url"], shouldFollowRedirect { meta.url = url }
    return meta
  }

  /// The proxy reports failures in an `error` string field; an empty string
  /// means success, exactly as the RN code checks (`body.error !== ''`).
  public static func proxyError(in body: [String: LinkMetaValue]) -> String? {
    if case .string(let error) = body["error"] {
      return error.isEmpty ? nil : error
    }
    return nil
  }
}

/// Result of parsing a starter-pack URI (the subset `getLinkMeta` consults).
public struct StarterPackParts: Hashable, Sendable {
  public let name: String
  public let rkey: String
}

/// Port of the `parseStarterPackUri` branch used by the link-meta preflight.
///
/// The full helper lives in `src/lib/strings/starter-pack.ts`; only the parse
/// is needed here. Returns `nil` when `uri` is absent, unparseable, or not a
/// starter pack.
public func parseStarterPackUri(_ uri: String?) -> StarterPackParts? {
  guard let uri else { return nil }
  if uri.hasPrefix("at://") {
    guard let atUri = try? AtUri(uri) else { return nil }
    guard atUri.collection == "app.bsky.graph.starterpack" else { return nil }
    guard let rkey = atUri.rkey, !rkey.isEmpty else { return nil }
    return StarterPackParts(name: atUri.host, rkey: rkey)
  }
  guard let url = URL(string: uri) else { return nil }
  let parts = url.path.split(separator: "/").map(String.init)
  guard parts.count == 3 else { return nil }
  let path = parts[0]
  guard path == "starter-pack" || path == "start" else { return nil }
  let name = parts[1]
  let rkey = parts[2]
  guard !name.isEmpty, !rkey.isEmpty else { return nil }
  return StarterPackParts(name: name, rkey: rkey)
}
