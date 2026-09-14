import Foundation

/// The feed identity carried by a home-feed query, ported from the RN
/// `FeedDescriptor` union in `src/state/queries/post-feed.ts`.
///
/// Only the descriptors the home feed can produce are modelled here: the
/// following timeline, a feed generator (`feedgen|`), and a list (`list|`).
/// Author/likes/posts/demo feeds belong to other features.
public enum FeedDescriptor: Hashable, Sendable, CustomStringConvertible {
  /// The following timeline. RN encodes this as the bare string `following`.
  case following
  /// A feed generator, `feedgen|<at-uri>`.
  case feedgen(uri: String)
  /// A user list, `list|<at-uri>`.
  case list(uri: String)

  /// The RN string form, used as the query-key argument and in the pinned model.
  public var description: String {
    switch self {
    case .following: return "following"
    case .feedgen(let uri): return "feedgen|\(uri)"
    case .list(let uri): return "list|\(uri)"
    }
  }

  /// Parses the RN descriptor string back into a case. Returns `nil` for a
  /// descriptor this feature does not own.
  public init?(descriptor: String) {
    if descriptor == "following" {
      self = .following
      return
    }
    let parts = descriptor.split(separator: "|", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    switch parts[0] {
    case "feedgen": self = .feedgen(uri: parts[1])
    case "list": self = .list(uri: parts[1])
    default: return nil
    }
  }

  /// The feed-generator URI, when this is a generator descriptor.
  public var feedgenUri: String? {
    if case .feedgen(let uri) = self { return uri }
    return nil
  }
}
