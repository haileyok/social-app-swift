import ATProtoClient
import Foundation
import Preferences

/// The onboarding flow.
///
/// Owns the wizard, the progress sink, and the step runner, and is the single
/// entry point a view drives. It has no UI dependency and no MainActor
/// requirement, so it can be exercised from any context and from Linux CI.
///
/// ## Observation
///
/// ``state`` is a value that can be read at any time, and ``addListener``
/// registers a callback invoked with the new value after every change. The
/// class is `@unchecked Sendable` because the state and listener list are
/// guarded by a lock; the stored dependencies are all `Sendable`.
public final class OnboardingFlow: @unchecked Sendable {

  /// A state observer.
  public typealias Listener = @Sendable (OnboardingState) -> Void

  private let actions: any OnboardingActionService
  private let preferences: PreferencesEngine
  private let sink: any OnboardingProgressSink

  private let lock = NSLock()
  private var listeners: [Listener] = []
  private var wizard: OnboardingWizard
  private var runner: OnboardingStepRunner
  private var isRunning = false

  /// Creates a flow.
  public init(
    actions: any OnboardingActionService,
    preferences: PreferencesEngine,
    sink: any OnboardingProgressSink = InMemoryOnboardingProgressSink(),
    configuration: OnboardingStepConfiguration = .default
  ) {
    self.actions = actions
    self.preferences = preferences
    self.sink = sink
    let wizard = OnboardingWizard(configuration: configuration)
    self.wizard = wizard
    self.runner = OnboardingStepRunner(
      wizard: wizard, actions: actions, preferences: preferences)
  }

  // MARK: - Observation

  /// The current state.
  public var state: OnboardingState {
    lock.lock()
    defer { lock.unlock() }
    return OnboardingState(wizard: wizard, isRunning: isRunning)
  }

  /// Registers a state observer. The listener is called synchronously from
  /// whichever context mutated the state, so it must not block.
  public func addListener(_ listener: @escaping Listener) {
    lock.lock()
    listeners.append(listener)
    lock.unlock()
  }

  /// Mutates the wizard and notifies every observer.
  private func update(_ mutate: (inout OnboardingWizard) -> Void) {
    lock.lock()
    let previous = wizard
    mutate(&wizard)
    let next = wizard
    runner.setWizard(next)
    let changed = next != previous
    let snapshot = OnboardingState(wizard: next, isRunning: isRunning)
    let observers = listeners
    lock.unlock()
    guard changed else { return }
    for observer in observers {
      observer(snapshot)
    }
  }

  private func setRunning(_ running: Bool) {
    lock.lock()
    let changed = isRunning != running
    isRunning = running
    let snapshot = OnboardingState(wizard: wizard, isRunning: running)
    let observers = listeners
    lock.unlock()
    guard changed else { return }
    for observer in observers {
      observer(snapshot)
    }
  }

  // MARK: - Lifecycle

  /// Loads any saved progress and adopts it.
  ///
  /// Returns the state after the load. A failing or absent snapshot leaves the
  /// flow at its first step; onboarding is always re-collectable, so a broken
  /// sink is never fatal.
  @discardableResult
  public func start() async -> OnboardingState {
    let saved = try? await sink.loadProgress()
    update { wizard in
      wizard = OnboardingWizard(configuration: wizard.configuration, progress: saved)
    }
    return state
  }

  /// Discards saved progress and starts over.
  public func reset() async {
    try? await sink.clearProgress()
    update { $0 = OnboardingWizard(configuration: $0.configuration) }
  }

  /// Persists the current progress.
  ///
  /// Called after every transition. A failure is ignored: the flow keeps the
  /// in-memory state, so the user is never blocked by a storage problem.
  private func persist() async {
    let snapshot = state.progress
    try? await sink.saveProgress(snapshot)
  }

  // MARK: - Navigation

  /// Advances one step, persisting the result.
  public func advance() async {
    update { $0.advance() }
    await persist()
  }

  /// Advances past the active step by skipping it.
  public func skip() async {
    update { $0.skip() }
    await persist()
  }

  /// Steps back one step.
  public func goBack() async {
    update { $0.goBack() }
    await persist()
  }

  /// Jumps past the find-contacts pair.
  public func skipContacts() async {
    update { $0.skipContacts() }
    await persist()
  }

  /// Moves to a specific step.
  @discardableResult
  public func move(to step: OnboardingStep) async -> Bool {
    var moved = false
    update { moved = $0.move(to: step) }
    if moved { await persist() }
    return moved
  }

  /// Moves to the first step that still needs work.
  @discardableResult
  public func resumeAtFirstUnsettledStep() async -> OnboardingStep {
    var landed = OnboardingStep.profile
    update { landed = $0.jumpToFirstUnsettledStep() }
    await persist()
    return landed
  }

  /// Rebuilds the flow with a new set of enabled steps.
  public func reconfigure(_ configuration: OnboardingStepConfiguration) async {
    update { $0.reconfigure(configuration) }
    await persist()
  }

  // MARK: - Step execution

  /// Runs the profile step and advances on success.
  @discardableResult
  public func runProfileStep(
    displayName: String,
    handle: String? = nil,
    avatarImageData: Data? = nil,
    avatarMimeType: String? = nil
  ) async -> StepOutcome {
    setRunning(true)
    defer { setRunning(false) }
    let outcome = await runner.runProfileStep(
      displayName: displayName, handle: handle, avatarImageData: avatarImageData,
      avatarMimeType: avatarMimeType)
    adoptRunnerWizard()
    await settle(outcome)
    return outcome
  }

  /// Runs the interests step and advances on success.
  @discardableResult
  public func runInterestsStep(selected: [String], required: Bool = false) async -> StepOutcome {
    setRunning(true)
    defer { setRunning(false) }
    let outcome = await runner.runInterestsStep(selected: selected, required: required)
    adoptRunnerWizard()
    await settle(outcome)
    return outcome
  }

  /// Runs the suggested-accounts step and advances on success.
  @discardableResult
  public func runSuggestedAccountsStep(
    selectedDIDs: [String], via: StarterPackRef? = nil
  ) async -> StepOutcome {
    setRunning(true)
    defer { setRunning(false) }
    let outcome = await runner.runSuggestedAccountsStep(
      selectedDIDs: selectedDIDs, via: via)
    adoptRunnerWizard()
    await settle(outcome)
    return outcome
  }

  /// Records the chosen starter pack and advances.
  @discardableResult
  public func runStarterPacksStep(joinedStarterPackURI: String?) async -> StepOutcome {
    setRunning(true)
    defer { setRunning(false) }
    let outcome = await runner.runStarterPacksStep(joinedStarterPackURI: joinedStarterPackURI)
    adoptRunnerWizard()
    await settle(outcome)
    return outcome
  }

  /// Runs the completion step and, when it settles, finishes the flow.
  @discardableResult
  public func finish(
    displayName: String? = nil,
    avatarImageData: Data? = nil,
    avatarMimeType: String? = nil
  ) async -> StepOutcome {
    setRunning(true)
    defer { setRunning(false) }
    let outcome = await runner.runCompletionStep(
      displayName: displayName, avatarImageData: avatarImageData,
      avatarMimeType: avatarMimeType)
    adoptRunnerWizard()
    // RN's completion block swallows failures and lets the user through, so
    // the flow always ends at the finished step. The outcome still reports the
    // first error so the caller can log it.
    update { wizard in
      wizard.move(to: .finished)
      wizard.settle(.finished, skipped: false)
    }
    await persist()
    return outcome
  }

  /// Applies the adult-content preference without moving the wizard.
  @discardableResult
  public func applyAdultContentGate(enabled: Bool) async -> StepOutcome {
    await runner.applyAdultContentGate(enabled: enabled)
  }

  /// Copies the runner's wizard back into the flow.
  ///
  /// The runner accumulates step *results* (which are not navigation), so the
  /// flow adopts them without emitting a step transition it would have to
  /// undo.
  private func adoptRunnerWizard() {
    lock.lock()
    let runnerWizard = runner.currentWizard
    wizard.setProfileResult(runnerWizard.results.profile)
    wizard.setInterestsResult(runnerWizard.results.interests)
    wizard.setSuggestedAccountsResult(runnerWizard.results.suggestedAccounts)
    wizard.setStarterPacksResult(runnerWizard.results.starterPacks)
    lock.unlock()
  }

  /// Settles a step's outcome into the wizard and persists.
  private func settle(_ outcome: StepOutcome) async {
    switch outcome {
    case .advanced:
      update { $0.advance() }
      await persist()
    case .completed:
      update { $0.settle($0.activeStep, skipped: false) }
      await persist()
    case .failed(let error):
      // A best-effort step is settled anyway; the caller sees the error but
      // the user is not blocked. Mirrors RN's completion block.
      if StepFailurePolicy.policy(for: state.activeStep) == .bestEffort {
        update { $0.advance() }
        await persist()
      }
      _ = error
    }
  }
}
