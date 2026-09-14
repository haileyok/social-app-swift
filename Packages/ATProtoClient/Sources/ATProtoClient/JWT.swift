import Foundation

/// Minimal JWT payload decoding.
///
/// This deliberately performs NO signature verification: the payload is only
/// used for client-side hints (is this access token expired? was it issued for
/// a queued signup?), never for an authorization decision. Anything that must
/// be trusted is verified server-side, and a forged token buys nothing here
/// because every request it authorizes is independently rejected upstream.
public enum JWT {
  /// The decoded payload claims this app reads.
  public struct Payload: Sendable, Equatable {
    /// Expiry, in seconds since the Unix epoch, when present.
    public let exp: Int?
    /// The atproto token scope, when present.
    public let scope: String?

    public init(exp: Int?, scope: String?) {
      self.exp = exp
      self.scope = scope
    }
  }

  /// The scope claim value on a token issued for a queued (waitlisted) signup.
  public static let signupQueuedScope = "com.atproto.signupQueued"

  /// The scope claim value on an app-password session.
  public static let appPasswordScope = "com.atproto.appPass"

  /// Decodes the payload segment of a compact JWS.
  ///
  /// Returns `nil` when the token is not a three-part JWT, the payload is not
  /// valid base64url, or the payload is not a JSON object.
  public static func decodePayload(_ token: String) -> Payload? {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3 else { return nil }
    guard let data = base64URLDecode(String(segments[1])),
      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    /* `exp` arrives as a JSON number; some issuers send it as a string. Accept
     * both rather than treating a stringified expiry as absent. */
    let exp: Int?
    if let value = raw["exp"] as? Int {
      exp = value
    } else if let value = raw["exp"] as? Double {
      exp = Int(value)
    } else if let value = raw["exp"] as? String {
      exp = Int(value)
    } else {
      exp = nil
    }
    let scope = raw["scope"] as? String
    return Payload(exp: exp, scope: scope)
  }

  /// Whether the token is expired (or unreadable), relative to `now`.
  ///
  /// An unreadable token is treated as expired, matching the RN
  /// `isJwtExpired`: the caller then takes the network resume path instead of
  /// trusting tokens it cannot inspect.
  public static func isExpired(_ token: String, now: Date = Date()) -> Bool {
    guard let payload = decodePayload(token), let exp = payload.exp else {
      return true
    }
    return Int(now.timeIntervalSince1970) >= exp
  }

  /// Whether the token was issued for a queued signup.
  public static func isSignupQueued(_ token: String) -> Bool {
    decodePayload(token)?.scope == signupQueuedScope
  }

  /// Whether the token was issued from an app password.
  public static func isAppPassword(_ token: String) -> Bool {
    decodePayload(token)?.scope == appPasswordScope
  }

  /// Decodes base64url (RFC 4648 section 5): URL-safe alphabet, no padding.
  public static func base64URLDecode(_ input: String) -> Data? {
    var value = input
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = value.count % 4
    if remainder > 0 {
      value += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: value)
  }

  /// Encodes base64url, used by tests to build hand-crafted tokens.
  public static func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// Builds an unsigned compact-JWS-shaped token from a payload object.
  ///
  /// Test-only helper: the signature segment is a placeholder, which is fine
  /// because nothing here verifies signatures.
  public static func unsignedToken(payload: [String: Any]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
      return nil
    }
    let header = base64URLEncode(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
    return "\(header).\(base64URLEncode(data))."
  }
}
