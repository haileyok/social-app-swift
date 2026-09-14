import Foundation
import Lexicons

/// JSON payload builders for the paginated graph endpoints.
///
/// These exist because Swift cannot infer `[String: Any]` for a literal mixing
/// an array and a nested object, and every graph list response carries a required
/// `subject` alongside its items.
enum GraphJSON {
  /// The `subject` every `getFollows` / `getFollowers` / `getKnownFollowers`
  /// response must carry.
  static func subject(
    did: String = "did:plc:alice", handle: String = "alice.example.com"
  ) -> [String: Any] {
    ["did": did, "handle": handle]
  }

  /// A `getFollows` response.
  static func follows(
    _ items: [[String: Any]] = [], cursor: String? = nil
  ) -> [String: Any] {
    var payload: [String: Any] = ["follows": items, "subject": subject()]
    if let cursor { payload["cursor"] = cursor }
    return payload
  }

  /// A `getFollowers` or `getKnownFollowers` response.
  static func followers(
    _ items: [[String: Any]] = [], cursor: String? = nil
  ) -> [String: Any] {
    var payload: [String: Any] = ["followers": items, "subject": subject()]
    if let cursor { payload["cursor"] = cursor }
    return payload
  }

  /// A profile view, as a graph list returns it.
  static func profile(
    did: String, handle: String = "someone.example.com", viewer: [String: Any]? = nil
  ) -> [String: Any] {
    var payload: [String: Any] = ["did": did, "handle": handle]
    if let viewer { payload["viewer"] = viewer }
    return payload
  }
}
