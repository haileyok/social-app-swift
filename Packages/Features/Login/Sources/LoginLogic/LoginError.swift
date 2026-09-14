import ATProtoClient
import Domain
import Foundation

/// Stable identifier for the user-facing message a ``LoginError`` renders.
///
/// The views package maps these onto its own localization catalog; keeping the
/// identifier separate from the English text means a message can be reworded
/// without touching the flow's stored state.
public enum LoginMessageID: String, Sendable, CaseIterable {
  case incorrectCredentials
  case authFactorRequired
  case invalidAuthFactorToken
  case rateLimited
  case networkOffline
  case appPasswordNotAllowed
  case unexpected
}

/// Every way a sign-in attempt can fail, with the copy the RN screens show.
///
/// Ported from the `try/catch` in `screens/Login/LoginForm.tsx`
/// (`attemptLogin`), widened with the app-password and rate-limit cases the
/// task calls for. The ordering of the checks matters and mirrors the RN
/// branch order, because the branches are substring matches over the same
/// stringified error.
public enum LoginError: Error, Sendable, Equatable {
  /// The server rejected the identifier/password pair.
  ///
  /// RN matches `Authentication Required` or `Invalid identifier or password`.
  case incorrectCredentials(underlying: XRPCErrorShape?)

  /// The server demands an emailed confirmation code before the session is
  /// usable. Recoverable: supply the code and retry with `authFactorToken`.
  case authFactorRequired(underlying: XRPCErrorShape?)

  /// A confirmation code was supplied and rejected (`Token is invalid`).
  case invalidAuthFactorToken(underlying: XRPCErrorShape?)

  /// The server rate-limited the attempt.
  case rateLimited(underlying: XRPCErrorShape?, retryAfterSeconds: Int?)

  /// The service could not be reached at all.
  case networkOffline(underlying: XRPCErrorShape?)

  /// The credentials were fine but the app password lacks the needed scope.
  case appPasswordNotAllowed(underlying: XRPCErrorShape?)

  /// Anything else; carries Domain's cleaned server message.
  case unexpected(message: String, underlying: XRPCErrorShape?)

  /// The identifier of the user-facing message.
  public var messageID: LoginMessageID {
    switch self {
    case .incorrectCredentials: .incorrectCredentials
    case .authFactorRequired: .authFactorRequired
    case .invalidAuthFactorToken: .invalidAuthFactorToken
    case .rateLimited: .rateLimited
    case .networkOffline: .networkOffline
    case .appPasswordNotAllowed: .appPasswordNotAllowed
    case .unexpected: .unexpected
    }
  }

  /// The English source copy for this failure.
  public var message: String {
    switch self {
    case .incorrectCredentials:
      LoginStrings.incorrectCredentials
    case .authFactorRequired:
      LoginStrings.twoFactorPrompt
    case .invalidAuthFactorToken:
      LoginStrings.invalidAuthFactorToken
    case .rateLimited:
      LoginStrings.rateLimited
    case .networkOffline:
      LoginStrings.unableToContactService
    case .appPasswordNotAllowed:
      LoginStrings.appPasswordNotAllowed
    case .unexpected(let message, _):
      message
    }
  }

  /// The underlying lex error, when the failure came from the server.
  public var underlying: XRPCErrorShape? {
    switch self {
    case .incorrectCredentials(let underlying),
      .authFactorRequired(let underlying),
      .invalidAuthFactorToken(let underlying),
      .rateLimited(let underlying, _),
      .networkOffline(let underlying),
      .appPasswordNotAllowed(let underlying),
      .unexpected(_, let underlying):
      underlying
    }
  }

  /// True when the flow can continue by collecting a code from the user.
  public var isRecoverable: Bool {
    switch self {
    case .authFactorRequired, .invalidAuthFactorToken, .incorrectCredentials,
      .rateLimited, .networkOffline:
      true
    case .appPasswordNotAllowed, .unexpected:
      false
    }
  }
}

/// The RN branch order, ported.
///
/// `attemptLogin` checks, in order: the 2FA error type, `Token is invalid`,
/// `Authentication Required` / `Invalid identifier or password`, a network
/// error, and finally `cleanError(err)`. The app-password and rate-limit
/// branches are inserted before the general network check so a 429 with an
/// `InvalidToken` app-password body is not misreported as a connectivity
/// problem.
public enum LoginErrorMapper {
  /// Maps any error thrown during a sign-in attempt to a ``LoginError``.
  public static func map(_ error: any Error) -> LoginError {
    // Typed first: PasswordSession.translate's this case before we ever see it.
    if error is AuthFactorRequiredError {
      return .authFactorRequired(underlying: XRPCErrorShapes.shape(from: error))
    }
    let shape = XRPCErrorShapes.shape(from: error)
    if shape?.error == "AuthFactorTokenRequired" {
      return .authFactorRequired(underlying: shape)
    }

    let subject = XRPCErrorShapes.subject(for: error)
    let search = XRPCErrorShapes.searchString(for: error)

    if search.contains("Token is invalid") {
      return .invalidAuthFactorToken(underlying: shape)
    }
    let isInvalidCredentials =
      search.contains("Authentication Required")
      || search.contains("Invalid identifier or password")
    if isInvalidCredentials {
      return .incorrectCredentials(underlying: shape)
    }
    if ErrorStrings.isErrorMaybeAppPasswordPermissions(subject) {
      return .appPasswordNotAllowed(underlying: shape)
    }
    if shape?.status == 429 || shape?.error == "RateLimitExceeded" {
      return .rateLimited(
        underlying: shape,
        retryAfterSeconds: XRPCErrorShapes.retryAfterSeconds(from: error))
    }
    if ErrorStrings.isNetworkError(subject) {
      return .networkOffline(underlying: shape)
    }
    return .unexpected(message: ErrorStrings.cleanError(subject), underlying: shape)
  }
}
