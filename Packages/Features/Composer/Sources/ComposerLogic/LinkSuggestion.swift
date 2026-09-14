import Foundation
import RichText

/// A detected link facet together with the rich text it was detected in.
///
/// Ported from `LinkFacetMatch` in
/// `src/view/com/composer/text-input/text-input-util.ts`.
public struct LinkFacetMatch: Sendable {
  public var richText: RichTextValue
  public var facet: Facet

  public init(richText: RichTextValue, facet: Facet) {
    self.richText = richText
    self.facet = facet
  }
}

/// Decides which detected link, if any, should become a link card right now.
///
/// Ported from `suggestLinkCardUri`. The rule exists so a link card is not
/// fetched while the user is still typing the URL: a URL that differs from the
/// previous keystroke's detection is "not yet stable", and only stabilises once
/// the text after it stops changing or is followed by whitespace/punctuation.
///
/// The `pastSuggestedUris` set is mutated in place, matching the RN helper: a
/// suggested URI is recorded so it is never suggested twice, and a URI that
/// stops being detected is dropped from the set so it is eligible again.
///
/// - Parameters:
///   - suggestImmediately: paste/intent prefills skip the stability check.
///   - nextDetectedUris: links detected on this keystroke, keyed by URI.
///   - prevDetectedUris: links detected on the previous keystroke.
///   - pastSuggestedUris: mutated; URIs already suggested or dismissed.
/// - Returns: the URI to suggest, or `nil`.
public func suggestLinkCardUri(
  suggestImmediately: Bool,
  nextDetectedUris: [String: LinkFacetMatch],
  prevDetectedUris: [String: LinkFacetMatch],
  pastSuggestedUris: inout Set<String>
) -> String? {
  var suggestedUris = Set<String>()
  for (uri, nextMatch) in nextDetectedUris {
    guard isValidUrlAndDomain(uri) else { continue }
    if pastSuggestedUris.contains(uri) { continue }
    if suggestImmediately {
      suggestedUris.insert(uri)
      continue
    }
    guard let prevMatch = prevDetectedUris[uri] else {
      // Not detected on the last keystroke either, so it is probably still
      // being typed. Wait for it to stabilise.
      continue
    }
    let prevTextAfterUri = prevMatch.richText.text(afterByteOffset: prevMatch.facet.index.byteEnd)
    let nextTextAfterUri = nextMatch.richText.text(afterByteOffset: nextMatch.facet.index.byteEnd)
    if prevTextAfterUri == nextTextAfterUri {
      // The edit was before the link: "abc google.com" -> "abcd google.com".
      suggestedUris.insert(uri)
      continue
    }
    if nextTextAfterUri.range(of: #"^\s"#, options: .regularExpression) != nil {
      // The link is now followed by a space, e.g. "google.com" -> "google.com ".
      suggestedUris.insert(uri)
      continue
    }
    if prevTextAfterUri.range(of: #"^[)]?[.,:;!?)](\s|$)"#, options: .regularExpression) != nil,
      nextTextAfterUri.range(of: #"^[)]?[.,:;!?)]\s"#, options: .regularExpression) != nil {
      // Punctuation was already trailing it, and now it is followed by
      // punctuation *and* a space, e.g. "google.com." -> "google.com. ".
      suggestedUris.insert(uri)
      continue
    }
  }

  for uri in pastSuggestedUris where nextDetectedUris[uri] == nil {
    // If a link is no longer detected it is eligible for suggestions next time.
    pastSuggestedUris.remove(uri)
  }

  guard let suggestedUri = suggestedUris.sorted().first else { return nil }
  pastSuggestedUris.insert(suggestedUri)
  return suggestedUri
}

/// Whether a URI is a syntactically valid absolute URL with a plausible domain.
///
/// Ported verbatim from `isValidUrlAndDomain`, including the private-address
/// exclusions: `10.x`, `127.x`, `169.254.x`, `192.168.x` and `172.16-31.x` are
/// rejected so a link card is never fetched for a local address.
public func isValidUrlAndDomain(_ value: String) -> Bool {
  let pattern = #"^(?:(?:(?:https?|ftp):)?\/\/)(?:\S+(?::\S*)?@)?(?:(?!(?:10|127)(?:\.\d{1,3}){3})(?!(?:169\.254|192\.168)(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z\u00a1-\uffff0-9]-*)*[a-z\u00a1-\uffff0-9]+)(?:\.(?:[a-z\u00a1-\uffff0-9]-*)*[a-z\u00a1-\uffff0-9]+)*(?:\.(?:[a-z\u00a1-\uffff]{2,})))(?::\d{2,5})?(?:[/?#]\S*)?$"#
  return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}

/// Collects the link facets of `richText`, split into post links and other links.
///
/// Ported from the `initText` branch of `createComposerState`: post URLs become
/// quotes, everything else can become a link card. Post URLs are recognised by
/// ``Domain/URLHelpers/isBskyPostUrl(_:)``.
public struct DetectedLinkUris: Sendable {
  /// `bsky.app` post links, keyed by URI.
  public var postUris: [String: LinkFacetMatch] = [:]
  /// Every other link, keyed by URI.
  public var externalUris: [String: LinkFacetMatch] = [:]

  public init(postUris: [String: LinkFacetMatch] = [:], externalUris: [String: LinkFacetMatch] = [:]) {
    self.postUris = postUris
    self.externalUris = externalUris
  }

  /// Whether nothing was detected.
  public var isEmpty: Bool { postUris.isEmpty && externalUris.isEmpty }
}
