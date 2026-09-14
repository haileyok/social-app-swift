import Foundation

/// The resumable slice of the wizard.
///
/// RN does not persist the whole onboarding reducer: only the shell's coarse
/// step (`persisted.onboarding.step` in `state/shell/onboarding.tsx`), which
/// collapses Welcome/RecommendedFeeds/RecommendedFollows/Home. This snapshot is
/// the equivalent for the Swift wizard: enough to rebuild where the user was,
/// which steps are done, and what they collected.
///
/// It is a plain value type so a sink can store it however it likes (a file, a
/// key-value store, memory) and so tests can compare snapshots directly.
public struct OnboardingProgress: Sendable, Equatable, Codable {
  /// Schema version of this snapshot.
  ///
  /// A snapshot written by a different version is discarded rather than
  /// migrated: onboarding state is re-collectable, so starting over is a safe
  /// fallback and avoids carrying a migration forever. Mirrors
  /// `persistedVersion` on a ``QueryStore/QueryKey``.
  public static let currentVersion = 1

  /// The version this snapshot was written at.
  public var version: Int
  /// The step the user was on.
  public var activeStep: OnboardingStep
  /// The direction of the last transition.
  public var stepTransitionDirection: StepTransitionDirection
  /// Which steps the user settled.
  public var completion: StepCompletion
  /// Which optional steps the session includes.
  public var configuration: OnboardingStepConfiguration
  /// Everything the flow collected.
  public var results: OnboardingResults

  /// Creates a snapshot.
  public init(
    version: Int = OnboardingProgress.currentVersion,
    activeStep: OnboardingStep,
    stepTransitionDirection: StepTransitionDirection = .forward,
    completion: StepCompletion = StepCompletion(),
    configuration: OnboardingStepConfiguration = .default,
    results: OnboardingResults = OnboardingResults()
  ) {
    self.version = version
    self.activeStep = activeStep
    self.stepTransitionDirection = stepTransitionDirection
    self.completion = completion
    self.configuration = configuration
    self.results = results
  }

  /// Whether this snapshot can be restored by the current build.
  public var isRestorable: Bool {
    version == Self.currentVersion && configuration.includes(activeStep)
  }
}

/// Where resumable progress is kept.
///
/// The sink is the pluggable seam: the flow never touches storage directly, so
/// the app can back it with the persisted store while tests use the in-memory
/// implementation below.
///
/// Implementations must be safe to call from any task. A failing load is not
/// fatal; the flow treats it as "no saved progress" and starts over.
public protocol OnboardingProgressSink: Sendable {
  /// Loads the saved snapshot, or nil when there is none.
  func loadProgress() async throws -> OnboardingProgress?
  /// Saves a snapshot.
  func saveProgress(_ progress: OnboardingProgress) async throws
  /// Clears the saved snapshot.
  func clearProgress() async throws
}

/// An in-memory sink. The default when the caller does not supply one, and the
/// harness the tests use.
public actor InMemoryOnboardingProgressSink: OnboardingProgressSink {
  private var stored: OnboardingProgress?

  /// Creates a sink, optionally preloaded with a snapshot.
  public init(initial: OnboardingProgress? = nil) {
    self.stored = initial
  }

  /// The current snapshot, for test assertions.
  public var progress: OnboardingProgress? { stored }

  public func loadProgress() async throws -> OnboardingProgress? {
    stored
  }

  public func saveProgress(_ progress: OnboardingProgress) async throws {
    stored = progress
  }

  public func clearProgress() async throws {
    stored = nil
  }
}

/// A sink that always fails, for exercising the flow's error handling.
public struct FailingOnboardingProgressSink: OnboardingProgressSink {
  /// Whether loads fail.
  public var failLoad: Bool
  /// Whether saves fail.
  public var failSave: Bool

  /// Creates a failing sink.
  public init(failLoad: Bool = true, failSave: Bool = true) {
    self.failLoad = failLoad
    self.failSave = failSave
  }

  public func loadProgress() async throws -> OnboardingProgress? {
    if failLoad { throw OnboardingError.progressUnavailable }
    return nil
  }

  public func saveProgress(_ progress: OnboardingProgress) async throws {
    if failSave { throw OnboardingError.progressUnavailable }
  }

  public func clearProgress() async throws {
    if failSave { throw OnboardingError.progressUnavailable }
  }
}
