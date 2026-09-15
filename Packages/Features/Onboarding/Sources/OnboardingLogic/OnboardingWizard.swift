import Foundation

/// The wizard's step machine, with no I/O.
///
/// Port of the `reducer` in `screens/Onboarding/state.ts`, widened in three
/// places the reducer could not express:
///
/// 1. **Explicit completion.** RN infers "done" from whether results were set
///    and from the current index. This machine records the settled steps, so a
///    resumed session knows which steps it already passed.
/// 2. **Skipping is per-step.** RN has one `skip-contacts` action that jumps to
///    whatever follows `find-contacts`. Here any step whose definition is
///    ``StepSkippability/skippable`` can be skipped, which is the same set of
///    screens (`suggested-accounts`, `suggested-starterpacks`, the two
///    find-contacts steps) plus room for the optional-step gate to change.
/// 3. **Derived next step.** RN recomputes the order on every action from the
///    `screens` map. This machine derives the order once per configuration and
///    exposes ``nextStep``/``previousStep`` over it.
///
/// The type is a value type: every transition returns a new value, and the
/// flow that owns it is the only thing that mutates.
public struct OnboardingWizard: Sendable, Equatable {
  /// Which optional steps this session includes.
  public private(set) var configuration: OnboardingStepConfiguration
  /// The step the user is on.
  public private(set) var activeStep: OnboardingStep
  /// The direction of the most recent change.
  public private(set) var stepTransitionDirection: StepTransitionDirection
  /// Which steps the user settled.
  public private(set) var completion: StepCompletion
  /// Everything the flow has collected.
  public private(set) var results: OnboardingResults

  /// The enabled steps, in order.
  public var stepOrder: [OnboardingStep] { configuration.stepOrder }

  /// The enabled steps that count toward the progress indicator.
  public var progressStepOrder: [OnboardingStep] {
    stepOrder.filter { OnboardingSteps.definition(for: $0).countsTowardProgress }
  }

  /// The index of the active step within ``stepOrder``, or nil if the active
  /// step is not enabled (which a restored snapshot can produce).
  public var activeStepIndex: Int? {
    stepOrder.firstIndex(of: activeStep)
  }

  /// The position shown in the progress indicator.
  ///
  /// ``OnboardingStep/findContacts`` is folded onto
  /// ``OnboardingStep/findContactsIntro`` for display, matching RN's
  /// `activeStepIndex` (`state.ts`) - the two screens are one conceptual step
  /// and RN explicitly warns not to navigate on the folded index.
  public var displayStepIndex: Int {
    let displayed = activeStep == .findContacts ? OnboardingStep.findContactsIntro : activeStep
    return progressStepOrder.firstIndex(of: displayed) ?? 0
  }

  /// How many steps the progress indicator shows.
  public var totalDisplaySteps: Int { progressStepOrder.count }

  /// Whether the user can go back. RN: `activeStep !== stepOrder[0]`.
  public var canGoBack: Bool {
    activeStep != progressStepOrder.first
  }

  /// Whether the active step can be skipped.
  public var canSkipActiveStep: Bool {
    OnboardingSteps.definition(for: activeStep).skippability == .skippable
  }

  /// Whether the active step has been settled already.
  public var isActiveStepSettled: Bool {
    completion.isSettled(activeStep)
  }

  /// Whether the flow reached its final step.
  public var isFinished: Bool { activeStep == .finished }

  /// Creates an initial wizard.
  public init(configuration: OnboardingStepConfiguration = .default) {
    self.configuration = configuration
    self.activeStep = configuration.stepOrder.first ?? .profile
    self.stepTransitionDirection = .forward
    self.completion = StepCompletion()
    self.results = OnboardingResults()
  }

  /// Restores a wizard from a snapshot, or starts fresh when the snapshot
  /// cannot be used.
  ///
  /// A snapshot is rejected when it was written at a different schema version
  /// or names a step this configuration does not include. Both cases are
  /// recoverable by starting over, which is what RN does when the persisted
  /// shell step is unrecognized.
  public init(configuration: OnboardingStepConfiguration, progress: OnboardingProgress?) {
    let usable = progress.flatMap { snapshot -> OnboardingProgress? in
      snapshot.version == OnboardingProgress.currentVersion
        && configuration.includes(snapshot.activeStep) ? snapshot : nil
    }
    guard let usable else {
      self.init(configuration: configuration)
      return
    }
    self.init(
      configuration: configuration, activeStep: usable.activeStep,
      stepTransitionDirection: usable.stepTransitionDirection,
      completion: usable.completion, results: usable.results)
  }

  /// Creates a wizard with explicit state, for restore paths.
  private init(
    configuration: OnboardingStepConfiguration,
    activeStep: OnboardingStep,
    stepTransitionDirection: StepTransitionDirection,
    completion: StepCompletion,
    results: OnboardingResults
  ) {
    self.configuration = configuration
    self.activeStep = activeStep
    self.stepTransitionDirection = stepTransitionDirection
    self.completion = completion
    self.results = results
  }

  /// The snapshot to persist.
  public var progress: OnboardingProgress {
    OnboardingProgress(
      activeStep: activeStep,
      stepTransitionDirection: stepTransitionDirection,
      completion: completion,
      configuration: configuration,
      results: results)
  }

  // MARK: - Derived navigation

  /// The step after `step`, or nil at the end.
  public func nextStep(after step: OnboardingStep) -> OnboardingStep? {
    guard let index = stepOrder.firstIndex(of: step), index + 1 < stepOrder.count else {
      return nil
    }
    return stepOrder[index + 1]
  }

  /// The step before `step`, or nil at the start.
  public func previousStep(before step: OnboardingStep) -> OnboardingStep? {
    guard let index = stepOrder.firstIndex(of: step), index > 0 else { return nil }
    return stepOrder[index - 1]
  }

  /// The step after the active one.
  public var nextStep: OnboardingStep? { nextStep(after: activeStep) }

  /// The step before the active one.
  public var previousStep: OnboardingStep? { previousStep(before: activeStep) }

  /// The next step that still needs work, starting from the active step.
  ///
  /// This is the "derived next step" the wizard uses on resume: steps already
  /// settled are passed over, so a session that comes back after completing
  /// profile and interests lands on suggested accounts. Returns
  /// ``OnboardingStep/finished`` when everything is settled.
  public var firstUnsettledStep: OnboardingStep {
    guard let index = stepOrder.firstIndex(of: activeStep) else {
      return stepOrder.first ?? .finished
    }
    for step in stepOrder[index...] where !completion.isSettled(step) {
      return step
    }
    return stepOrder.last ?? .finished
  }

  // MARK: - Transitions

  /// Advances one step, settling the current one as completed.
  ///
  /// At the last step the active step does not move, matching RN's `next`
  /// branch (`if (nextStep) next.activeStep = nextStep`).
  public mutating func advance() {
    settle(activeStep, skipped: false)
    move(to: nextStep ?? activeStep)
  }

  /// Advances one step, settling the current one as skipped.
  ///
  /// Skipping a step that is not ``StepSkippability/skippable`` is refused:
  /// the active step does not change.
  public mutating func skip() {
    guard canSkipActiveStep else { return }
    settle(activeStep, skipped: true)
    move(to: nextStep ?? activeStep)
  }

  /// Steps back one step, without disturbing completion state.
  ///
  /// Going back does not un-settle a step: RN keeps the results and only moves
  /// the pointer, so re-entering a finished step shows what was entered.
  ///
  /// A step back from ``OnboardingStep/finished`` lands on the last
  /// non-finished step, since the find-contacts pair is presented as one unit
  /// only when going forward.
  public mutating func goBack() {
    guard let previous = previousStep else { return }
    move(to: previous)
  }

  /// Jumps to a specific step, when it is enabled.
  ///
  /// The transition is recorded as forward or backward based on the order, and
  /// the step is *not* settled: this is the resume path, not the advance path.
  @discardableResult
  public mutating func move(to step: OnboardingStep) -> Bool {
    guard configuration.includes(step), let from = stepOrder.firstIndex(of: activeStep),
      let to = stepOrder.firstIndex(of: step)
    else { return false }
    activeStep = step
    stepTransitionDirection = to >= from ? .forward : .backward
    return true
  }

  /// Jumps to the first step that still needs work.
  ///
  /// Returns the step landed on. Used on resume.
  @discardableResult
  public mutating func jumpToFirstUnsettledStep() -> OnboardingStep {
    let target = firstUnsettledStep
    move(to: target)
    return target
  }

  /// Skips straight past the find-contacts pair, port of `skip-contacts`.
  ///
  /// Unlike ``skip()`` this settles both find-contacts steps, because RN's
  /// action jumps over the whole pair in one go.
  public mutating func skipContacts() {
    guard configuration.findContactsStepEnabled else { return }
    completion.completed.insert(.findContactsIntro)
    completion.skipped.insert(.findContacts)
    let target = nextStep(after: .findContacts) ?? .finished
    move(to: target)
  }

  /// Records a step as settled.
  public mutating func settle(_ step: OnboardingStep, skipped: Bool) {
    completion.completed.insert(step)
    if skipped {
      completion.skipped.insert(step)
    } else {
      completion.skipped.remove(step)
    }
  }

  /// Clears settlement for a step, so it is treated as needing work again.
  public mutating func unsettle(_ step: OnboardingStep) {
    completion.completed.remove(step)
    completion.skipped.remove(step)
  }

  // MARK: - Results

  /// Stores the profile step's result.
  public mutating func setProfileResult(_ result: ProfileStepResult) {
    results.profile = result
  }

  /// Stores the interests step's result.
  public mutating func setInterestsResult(_ result: InterestsStepResult) {
    results.interests = result
  }

  /// Stores the suggested-accounts step's result.
  public mutating func setSuggestedAccountsResult(_ result: SuggestedAccountsStepResult) {
    results.suggestedAccounts = result
  }

  /// Stores the starter-packs step's result.
  public mutating func setStarterPacksResult(_ result: StarterPacksStepResult) {
    results.starterPacks = result
  }

  /// Rebuilds the wizard with a new configuration, keeping what still applies.
  ///
  /// The active step is preserved when the new configuration still includes
  /// it, otherwise the wizard falls back to the first enabled step.
  /// Completion for steps the new configuration drops is discarded.
  public mutating func reconfigure(_ configuration: OnboardingStepConfiguration) {
    self.configuration = configuration
    let enabled = Set(configuration.stepOrder)
    completion.completed = completion.completed.intersection(enabled)
    completion.skipped = completion.skipped.intersection(enabled)
    if !enabled.contains(activeStep) {
      activeStep = configuration.stepOrder.first ?? .profile
    }
  }
}
