import Foundation

/// Port of `src/lib/xrpc-error.ts` and the pure parts of
/// `src/lib/strings/errors.ts`.
///
/// Deviation: the RN versions operate on the `@atproto/lex` error classes
/// (`LexError`, `XrpcResponseError`). Domain must not depend on ATProtoClient,
/// so these are pure functions over ``XRPCErrorShape`` - a minimal local error
/// shape carrying the same fields the RN helpers read.
///
/// ``cleanError(_:)`` returns the English source copy; the RN version routes
/// each branch through Lingui. Established by `errors.test.ts`.

/// A minimal stand-in for the lex error hierarchy.
///
/// - `name` distinguishes the class (`XrpcResponseError`, `LexError`, ...).
/// - `error` is the lexicon error code, when the value carries one.
/// - `message` is the human-readable server text.
/// - `status` is the HTTP status, present only for a genuine response error.
public struct XRPCErrorShape: Error, Hashable, Sendable, CustomStringConvertible {
  public let name: String
  public let error: String?
  public let message: String
  public let status: Int?

  public init(name: String, error: String?, message: String, status: Int? = nil) {
    self.name = name
    self.error = error
    self.message = message
    self.status = status
  }

  /// A lex error with a code.
  public static func lexError(_ error: String, message: String = "") -> XRPCErrorShape {
    XRPCErrorShape(name: "LexError", error: error, message: message)
  }

  /// A response error carrying a status.
  public static func response(
    _ error: String,
    message: String,
    status: Int
  ) -> XRPCErrorShape {
    XRPCErrorShape(name: "XrpcResponseError", error: error, message: message, status: status)
  }

  /// `Class: [ErrorCode] message` - the lex `toString()` shape.
  public var description: String {
    "\(name): [\(error ?? "")] \(message)"
  }

  /// Builds the shape the lex client produces from a JSON XRPC error payload.
  public static func responsePayload(
    error: String,
    message: String,
    status: Int
  ) -> XRPCErrorShape {
    XRPCErrorShape(name: "XrpcResponseError", error: error, message: message, status: status)
  }

  /// Builds the shape the lex client produces from a bare HTTP status: the
  /// code is derived from the status and the message is the generic overview.
  /// Mirrors `httpResponseCodeToName` for the codes the app hits.
  public static func responseStatus(_ status: Int) -> XRPCErrorShape {
    XRPCErrorShape(
      name: "XrpcResponseError",
      error: httpResponseCodeToName(status),
      message: "Upstream server responded with a \(status) error",
      status: status
    )
  }

  /// Status code to lexicon error name, matching the SDK's `ResponseType`
  /// enum for known codes and its 4xx/5xx fallbacks.
  public static func httpResponseCodeToName(_ status: Int) -> String {
    switch status {
    case 400: return "InvalidRequest"
    case 401: return "AuthenticationRequired"
    case 403: return "Forbidden"
    case 404: return "XRPCNotSupported"
    case 406: return "NotAcceptable"
    case 413: return "PayloadTooLarge"
    case 415: return "UnsupportedMediaType"
    case 429: return "RateLimitExceeded"
    case 500: return "InternalServerError"
    case 501: return "MethodNotImplemented"
    case 502: return "UpstreamFailure"
    case 503: return "NotEnoughResources"
    case 504: return "UpstreamTimeout"
    default:
      if (400..<500).contains(status) { return "InvalidRequest" }
      return "InternalServerError"
    }
  }
}

/// Pure error helpers over ``XRPCErrorShape``.
public enum XRPCErrorHelpers {

  /// The lex error code (`err.error`), or `nil` when absent.
  public static func getErrorName(_ e: Any?) -> String? {
    (e as? XRPCErrorShape)?.error
  }

  /// The lexicon error code, narrowed to a declared set for one method.
  public static func matchXrpcError(_ e: Any?, declaredCodes: Set<String>) -> String? {
    guard let shape = e as? XRPCErrorShape, shape.name == "XrpcResponseError" else {
      return nil
    }
    guard let code = shape.error, declaredCodes.contains(code) else { return nil }
    return code
  }

  /// Whether `e` is a `com.atproto.repo.getRecord` "record absent" failure,
  /// matching `isRecordNotFoundError`.
  public static func isRecordNotFoundError(_ e: Any?) -> Bool {
    if let shape = e as? XRPCErrorShape,
      shape.name == "XrpcResponseError",
      shape.error == "RecordNotFound" {
      return true
    }
    return ErrorStrings.stringify(e).contains("Could not locate record:")
  }
}

/// Port of `src/lib/strings/errors.ts`.
public enum ErrorStrings {

  static let networkErrors = [
    "Abort",
    "Network request failed",
    "Failed to fetch",
    "fetch failed",
    "Load failed",
    "Upstream service unreachable",
    "NetworkError when attempting to fetch resource",
  ]

  /// Whether the stringified error contains any known network-failure marker.
  public static func isNetworkError(_ e: Any?) -> Bool {
    let str = stringify(e)
    return networkErrors.contains { str.contains($0) }
  }

  /// The text to show the user when no special case applies.
  ///
  /// A lex error stringifies as `Class: [ErrorCode] message`, which is never
  /// fit for display: prefer its message, falling back to the code.
  /// Everything else keeps the historical behaviour of dropping a leading
  /// `Error: `.
  public static func cleanError(_ e: Any?) -> String {
    guard let e else { return "" }
    let str = stringify(e)
    if isNetworkError(e) {
      return "Unable to connect. Please check your internet connection and try again."
    }
    /*
     * The legacy client named these with spaces ("Upstream Failure"); lexicon
     * error codes are space-free ("UpstreamFailure"). Match both while the app
     * throws both shapes.
     */
    if str.contains("Upstream Failure") || str.contains("UpstreamFailure")
      || str.contains("NotEnoughResources") || str.contains("pipethrough network error") {
      return "The server appears to be experiencing issues. Please try again in a few moments."
    }
    if str.contains("Do not have authorization to set preferences")
      && str.contains("app.bsky.actor.defs#personalDetailsPref") {
      return
        "You cannot update your birthdate while using an app password. Please sign in with your main password to update your birthdate."
    }
    if str.contains("Bad token scope") || str.contains("Bad token method") {
      return
        "This feature is not available while using an App Password. Please sign in with your main password."
    }
    if str.contains("Account has been suspended") {
      return "Account has been suspended"
    }
    if str.contains("Account is deactivated") {
      return "Account is deactivated"
    }
    if str.contains("Profile not found") {
      return "Profile not found"
    }
    if str.contains("Unable to resolve handle") {
      return "Unable to resolve handle"
    }
    return toDisplayString(e, str)
  }

  static func toDisplayString(_ e: Any?, _ str: String) -> String {
    if let shape = e as? XRPCErrorShape {
      return shape.message.isEmpty ? (shape.error ?? str) : shape.message
    }
    if str.hasPrefix("Error: ") {
      return String(str.dropFirst("Error: ".count))
    }
    return str
  }

  /// The PDS answers an app-password-scope rejection with the code
  /// `InvalidToken` and a message of 'Bad token scope' or 'Bad token method'.
  public static func isErrorMaybeAppPasswordPermissions(_ e: Any?) -> Bool {
    if let shape = e as? XRPCErrorShape, shape.error != nil {
      return shape.error == "InvalidToken"
        && (shape.message.contains("Bad token scope")
          || shape.message.contains("Bad token method"))
    }
    let str = stringify(e)
    return str.contains("Bad token scope") || str.contains("Bad token method")
  }

  /// Captures "User cancelled" / "Crop cancelled" errors from the expo modules.
  public static func isCancelledError(_ e: Any?) -> Bool {
    stringify(e).lowercased().contains("cancel")
  }

  static let retryableHttpStatuses = [408, 425, 429, 500, 502, 503, 504, 522, 524]

  public static func isRetryableHttpStatus(_ status: Int) -> Bool {
    retryableHttpStatuses.contains(status)
  }

  /// `Class: [Code] message` for the local shape, else a plain description.
  static func stringify(_ e: Any?) -> String {
    switch e {
    case let shape as XRPCErrorShape:
      return shape.description
    case let str as String:
      return str
    case let describable as CustomStringConvertible:
      // Covers the test/app error types whose `description` is the message,
      // which is what the RN `String(e)` produces.
      return describable.description
    case let error as Error:
      return (error as NSError).localizedDescription
    case .some(let value):
      return String(describing: value)
    case .none:
      return ""
    }
  }
}
