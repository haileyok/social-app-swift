import ATProtoClient
import Domain
import Foundation

/// Conversions from the client's error shapes to the pure
/// ``XRPCErrorShape`` the Domain classifiers operate on.
///
/// ``Domain/ErrorStrings`` deliberately does not depend on ATProtoClient, so
/// the login package performs the widening at its own boundary.
public enum XRPCErrorShapes {
  /// The pure shape for a transport-level ``XrpcError``.
  ///
  /// Distinctly named from the `any Error` overload below: two `shape(from:)`
  /// overloads let one call the other by mistake, and the recursion is not
  /// diagnosable from the resulting stack overflow.
  public static func shape(fromXrpc error: XrpcError) -> XRPCErrorShape {
    XRPCErrorShape(
      name: "XrpcResponseError",
      error: error.rawCode,
      message: error.message ?? "",
      status: error.status >= 0 ? error.status : nil)
  }

  /// The pure shape for any error the flow can throw, when one can be derived.
  public static func shape(from error: any Error) -> XRPCErrorShape? {
    switch error {
    case let auth as AuthFactorRequiredError:
      return shape(fromXrpc: auth.underlying)
    case let invalid as SessionInvalidError:
      return shape(fromXrpc: invalid.underlying)
    case let shape as XRPCErrorShape:
      return shape
    case let xrpc as XrpcError:
      return shape(fromXrpc: xrpc)
    default:
      return nil
    }
  }

  /// The value the RN error mapping matches its substring checks against.
  ///
  /// The RN code stringifies the error and matches on the result, which for a
  /// lex error is `Class: [ErrorCode] message`. ``XRPCErrorShape/description``
  /// reproduces that shape exactly, so the same checks port over unchanged.
  public static func searchString(for error: any Error) -> String {
    if let shape = shape(from: error) {
      return shape.description
    }
    return String(describing: error)
  }

  /// The value the RN code passes to `String(err)` when a plain description is
  /// wanted, i.e. preferring the shape when the error is a lex error.
  public static func subject(for error: any Error) -> Any {
    if let shape = shape(from: error) {
      return shape
    }
    return error
  }

  /// The `Retry-After` header value the transport recorded, when present.
  public static func retryAfterSeconds(from error: any Error) -> Int? {
    (error as? XrpcError)?.retryAfterSeconds
  }
}
