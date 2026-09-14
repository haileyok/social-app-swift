import Domain
import Foundation

/// Stable identifier for the user-facing message an ``OnboardingError``
/// renders.
///
/// The views package maps these onto its own catalog; keeping the identifier
/// separate from the English text means copy can change without touching the
/// flow's stored state.
public enum OnboardingMessageID: String, Sendable, CaseIterable {
  case noSession
  case progressUnavailable
  case displayNameTooLong
  case displayNameBlank
  case handleInvalid
  case handleTaken
  case handleCheckFailed
  case avatarUploadFailed
  case profileWriteFailed
  case interestsWriteFailed
  case followFailed
  case preferencesUnavailable
  case unexpected
}

/// Every way an onboarding step can fail.
///
/// The wizard's steps swallow most write failures on purpose (RN logs and
/// continues through onboarding, see `StepFinished.finishOnboarding`), but the
/// flow still surfaces typed failures to the caller so a view can decide what
/// to log or retry.
public enum OnboardingError: Error, Sendable, Equatable {
  /// No signed-in session, so no write can be made.
  case noSession
  /// The progress sink could not be read or written.
  case progressUnavailable
  /// A display name exceeded the maximum length.
  case displayNameTooLong(maxLength: Int)
  /// A display name was empty after trimming.
  case displayNameBlank
  /// A handle failed local syntax validation.
  case handleInvalid(reason: String)
  /// A handle is taken. Carries the server's suggestions.
  case handleTaken(suggestions: [String])
  /// The handle-availability check could not complete.
  case handleCheckFailed(underlying: XRPCErrorShape?)
  /// The avatar blob could not be uploaded.
  case avatarUploadFailed(underlying: XRPCErrorShape?)
  /// The profile record write failed.
  case profileWriteFailed(underlying: XRPCErrorShape?)
  /// The interests preference write failed.
  case interestsWriteFailed(underlying: XRPCErrorShape?)
  /// Following the selected accounts failed.
  case followFailed(underlying: XRPCErrorShape?)
  /// A preferences read or write failed for another reason.
  case preferencesUnavailable(underlying: XRPCErrorShape?)
  /// Anything else; carries Domain's cleaned server message.
  case unexpected(message: String, underlying: XRPCErrorShape?)

  /// The identifier of the user-facing message.
  public var messageID: OnboardingMessageID {
    switch self {
    case .noSession: .noSession
    case .progressUnavailable: .progressUnavailable
    case .displayNameTooLong: .displayNameTooLong
    case .displayNameBlank: .displayNameBlank
    case .handleInvalid: .handleInvalid
    case .handleTaken: .handleTaken
    case .handleCheckFailed: .handleCheckFailed
    case .avatarUploadFailed: .avatarUploadFailed
    case .profileWriteFailed: .profileWriteFailed
    case .interestsWriteFailed: .interestsWriteFailed
    case .followFailed: .followFailed
    case .preferencesUnavailable: .preferencesUnavailable
    case .unexpected: .unexpected
    }
  }

  /// The underlying lex error, when the failure came from the server.
  public var underlying: XRPCErrorShape? {
    switch self {
    case .noSession, .progressUnavailable, .displayNameTooLong, .displayNameBlank,
      .handleInvalid, .handleTaken:
      nil
    case .handleCheckFailed(let underlying), .avatarUploadFailed(let underlying),
      .profileWriteFailed(let underlying), .interestsWriteFailed(let underlying),
      .followFailed(let underlying), .preferencesUnavailable(let underlying),
      .unexpected(_, let underlying):
      underlying
    }
  }

  /// Whether the step can be retried without changing the user's input.
  public var isRetryable: Bool {
    switch self {
    case .handleCheckFailed, .avatarUploadFailed, .profileWriteFailed,
      .interestsWriteFailed, .followFailed, .preferencesUnavailable, .unexpected:
      true
    case .noSession, .progressUnavailable, .displayNameTooLong, .displayNameBlank,
      .handleInvalid, .handleTaken:
      false
    }
  }
}

/// The message the flow shows for an error, derived from the RN screens'
/// copy where it exists.
public enum OnboardingStrings {
  /// `screens/Onboarding` renders no copy for a failed write; it logs and
  /// continues. These strings exist for the flows that do report.
  public static let genericError = "An error occurred while fetching suggested accounts."
  /// `StepProfile` error for an unusable image.
  public static let unusableImage =
    "This image could not be used. Try a different format like .jpg or .png."
  /// `StepSuggestedAccounts` empty state.
  public static let noSuggestions =
    "Sorry, we're unable to load account suggestions at this time."
}

/// Maps a thrown error onto an ``OnboardingError``.
///
/// Port of the shape handling in `lib/strings/errors.ts` as used by the
/// onboarding writes: the flow distinguishes a network failure (retryable)
/// from a validation rejection (not), and everything else falls through to
/// Domain's cleaned message.
public enum OnboardingErrorMapper {
  /// Maps any error thrown during a step write.
  public static func map(_ error: any Error) -> OnboardingError {
    if let onboarding = error as? OnboardingError { return onboarding }
    let shape = OnboardingErrorShapes.shape(from: error)
    let subject = OnboardingErrorShapes.subject(for: error)
    return .unexpected(message: ErrorStrings.cleanError(subject), underlying: shape)
  }
}
