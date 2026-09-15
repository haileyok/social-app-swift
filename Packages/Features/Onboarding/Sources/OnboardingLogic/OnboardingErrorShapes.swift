import ATProtoClient
import Domain
import Foundation

/// Conversions from the client's error shapes to the pure ``XRPCErrorShape``
/// the Domain classifiers operate on.
///
/// ``Domain/ErrorStrings`` deliberately does not depend on ATProtoClient, so
/// this package performs the widening at its own boundary. Login carries the
/// same small adapter; the duplication is intentional, because a shared copy
/// would have to live in a package neither feature owns.
public enum OnboardingErrorShapes {
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
    case let invalid as SessionInvalidError:
      return shape(fromXrpc: invalid.underlying)
    case let loggedOut as LoggedOutError:
      return XRPCErrorShape(
        name: "LoggedOutError", error: nil, message: String(describing: loggedOut))
    case let shape as XRPCErrorShape:
      return shape
    case let xrpc as XrpcError:
      return shapeFromXrpc(xrpc: xrpc)
    default:
      return nil
    }
  }

  /// The `subject` value the RN error helpers are called with, i.e. preferring
  /// the shape when the error is a lex error.
  public static func subject(for error: any Error) -> Any {
    if let shape = shape(from: error) {
      return shape
    }
    return error
  }

  /// ``shape(fromXrpc:)`` under a second name, so the `any Error` overload
  /// above cannot accidentally recurse into itself.
  private static func shapeFromXrpc(xrpc: XrpcError) -> XRPCErrorShape {
    shape(fromXrpc: xrpc)
  }
}
