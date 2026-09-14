import Foundation

/// The flow's published state: the wizard plus the derived values a view
/// needs, and whether a step write is in flight.
///
/// A value type so any observer can hold it without sharing mutable state, and
/// an `Equatable` one so tests can assert transitions directly.
public struct OnboardingState: Sendable, Equatable {
  /// The step the user is on.
  public let activeStep: OnboardingStep
  /// The direction of the most recent transition.
  public let stepTransitionDirection: StepTransitionDirection
  /// The enabled steps, in order.
  public let stepOrder: [OnboardingStep]
  /// Which steps the user settled.
  public let completion: StepCompletion
  /// Everything the flow collected.
  public let results: OnboardingResults
  /// Whether a step write is currently running.
  public let isRunning: Bool
  /// The position shown in the progress indicator.
  public let activeStepIndex: Int
  /// How many steps the progress indicator shows.
  public let totalSteps: Int
  /// Whether the user can go back.
  public let canGoBack: Bool
  /// Whether the active step can be skipped.
  public let canSkipActiveStep: Bool
  /// Whether the flow is on its final step.
  public let isFinished: Bool

  /// Builds the state from a wizard.
  init(wizard: OnboardingWizard, isRunning: Bool) {
    self.activeStep = wizard.activeStep
    self.stepTransitionDirection = wizard.stepTransitionDirection
    self.stepOrder = wizard.stepOrder
    self.completion = wizard.completion
    self.results = wizard.results
    self.isRunning = isRunning
    self.activeStepIndex = wizard.displayStepIndex
    self.totalSteps = wizard.totalDisplaySteps
    self.canGoBack = wizard.canGoBack
    self.canSkipActiveStep = wizard.canSkipActiveStep
    self.isFinished = wizard.isFinished
  }

  /// The snapshot to persist.
  public var progress: OnboardingProgress {
    OnboardingProgress(
      activeStep: activeStep,
      stepTransitionDirection: stepTransitionDirection,
      completion: completion,
      configuration: OnboardingStepConfiguration(
        starterPacksStepEnabled: stepOrder.contains(.suggestedStarterPacks),
        findContactsStepEnabled: stepOrder.contains(.findContacts)),
      results: results)
  }
}
