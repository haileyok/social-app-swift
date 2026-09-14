#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import RichText
import SwiftUI
import UIComponentsCore

/// Renders ``RichTextSegment`` runs as an inline flowing text.
///
/// The RN app walks the same segment list and emits a `<Text>` per run with a
/// tappable `Link`. SwiftUI has no inline flow of separately-tappable views, so
/// the port builds one `AttributedString`: the runs are concatenated with their
/// facet styling applied, and each rendered range carries the destination so a
/// tap can be routed. That keeps the text flowing and selectable like the RN
/// original instead of stacking a view per word.
///
/// ```swift
/// RichTextBody(segments: item.segments, onOpen: { route($0) })
/// ```
public struct RichTextBody: View {
  private let segments: [RichTextSegment]
  private let scale: TypeScale
  private let onOpen: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    segments: [RichTextSegment],
    scale: TypeScale = .md,
    onOpen: @escaping (RichTextTarget) -> Void = { _ in }
  ) {
    self.segments = segments
    self.scale = scale
    self.onOpen = onOpen
  }

  public var body: some View {
    Text(attributed)
      .font(scale.font())
      .foregroundStyle(theme.atomColors.text)
      .textSelection(.enabled)
      .environment(
        \.openURL,
        OpenURLAction { url in
          onOpen(RichTextTarget(url: url))
          return .handled
        })
  }

  /// The concatenated, styled body. Exposed for tests and for callers that need
  /// the same runs in a different container (a mention pill, a share sheet).
  public var attributed: AttributedString {
    var result = AttributedString()
    for segment in segments {
      var run = AttributedString(segment.text)
      if segment.isLink || segment.isTag || segment.isMention {
        run.foregroundColor = theme.atomColors.textLink
        run.underlineStyle = segment.isLink ? .single : nil
        if let destination = destination(for: segment) {
          run.link = destination
        }
      }
      result.append(run)
    }
    return result
  }

  /// The URL a facet resolves to. A link uses its URI; a tag or mention becomes
  /// an internal destination the caller routes on.
  private func destination(for segment: RichTextSegment) -> URL? {
    if let link = segment.link { return URL(string: link) }
    if let tag = segment.tag {
      return URL(string: "bsky://hashtag/\(tag)")
    }
    if let mention = segment.mention {
      return URL(string: "bsky://profile/\(mention)")
    }
    return nil
  }
}

/// A tapped facet destination, unwrapped from the `bsky://` routing scheme.
public enum RichTextTarget: Equatable, Sendable {
  case external(URL)
  case hashtag(String)
  case profile(did: String)

  /// Parses an internal or external URL.
  public init(url: URL) {
    guard url.scheme == "bsky" else {
      self = .external(url)
      return
    }
    let components = url.pathComponents.filter { $0 != "/" }
    switch url.host {
    case "hashtag":
      self = .hashtag(components.first ?? "")
    case "profile":
      self = .profile(did: components.first ?? "")
    default:
      self = .external(url)
    }
  }
}
#endif
