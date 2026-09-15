import OnboardingLogic

/// The user-facing copy for a failed onboarding step.
///
/// `OnboardingLogic` maps a thrown error onto a typed ``OnboardingError`` and
/// classifies it (``OnboardingError/isRetryable``, and the per-step
/// `StepFailurePolicy`); the wording belongs here. Where the RN flow already has
/// copy for a case it is reused through ``OnboardingStrings`` rather than
/// restated.
public enum OnboardingErrorPresentation {

  /// The message to show for a failed step write.
  public static func message(for error: OnboardingError) -> String {
    switch error {
    case .noSession:
      return "Sign in to finish setting up your account."
    case .progressUnavailable:
      return "Your progress could not be saved. You can keep going."
    case .displayNameTooLong(let maxLength):
      return "Display names can be at most \(maxLength) characters."
    case .displayNameBlank:
      return "Enter a display name to continue."
    case .handleInvalid:
      return "That handle is not valid."
    case .handleTaken(let suggestions):
      return handleTakenMessage(suggestions)
    case .handleCheckFailed:
      return "We could not check that handle. Try again."
    case .avatarUploadFailed:
      return OnboardingStrings.unusableImage
    case .profileWriteFailed, .interestsWriteFailed, .followFailed, .preferencesUnavailable:
      return OnboardingStrings.genericError
    case .unexpected(let message, _):
      return message
    }
  }

  /// Whether the failed step should offer a retry, rather than only a message.
  public static func canRetry(_ error: OnboardingError) -> Bool {
    error.isRetryable
  }

  /// The taken-handle message, with the server's suggestions when it offered
  /// any.
  private static func handleTakenMessage(_ suggestions: [String]) -> String {
    guard !suggestions.isEmpty else { return "That handle is taken." }
    return "That handle is taken. Try \(suggestions.joined(separator: ", "))."
  }
}
