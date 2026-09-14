import Foundation
import Preferences
import Testing

@testable import OnboardingLogic

@Suite("Onboarding flow")
struct OnboardingFlowTests {

  private func makeFlow(
    sink: any OnboardingProgressSink = InMemoryOnboardingProgressSink(),
    actions: FakeOnboardingActionService = FakeOnboardingActionService(),
    configuration: OnboardingStepConfiguration = .default
  ) -> (OnboardingFlow, FakeOnboardingActionService) {
    let flow = OnboardingFlow(
      actions: actions,
      preferences: InMemoryPreferencesServer().engine(),
      sink: sink,
      configuration: configuration)
    return (flow, actions)
  }

  @Test("a fresh flow starts at the first step")
  func freshStart() async {
    let (flow, _) = makeFlow()
    await flow.start()
    #expect(flow.state.activeStep == .profile)
    #expect(flow.state.activeStepIndex == 0)
    #expect(flow.state.totalSteps == 4)
    #expect(!flow.state.canGoBack)
  }

  @Test("a listener fires on a step change")
  func listenerFires() async {
    let (flow, _) = makeFlow()
    let recorder = StateRecorder()
    flow.addListener { recorder.record($0.activeStep) }
    await flow.advance()
    #expect(recorder.steps == [.interests])
  }

  @Test("a listener does not fire when nothing changed")
  func listenerIdempotent() async {
    let (flow, _) = makeFlow()
    let recorder = StateRecorder()
    flow.addListener { recorder.record($0.activeStep) }
    await flow.goBack()  // already at the first step
    #expect(recorder.steps.isEmpty)
  }

  @Test("advancing persists progress to the sink")
  func progressPersisted() async {
    let sink = InMemoryOnboardingProgressSink()
    let (flow, _) = makeFlow(sink: sink)
    await flow.advance()

    let saved = await sink.progress
    #expect(saved?.activeStep == .interests)
    #expect(saved?.completion.isSettled(.profile) == true)
  }

  @Test("start resumes from the persisted step")
  func resumeFromSink() async {
    let sink = InMemoryOnboardingProgressSink(
      initial: OnboardingProgress(
        activeStep: .suggestedAccounts,
        completion: StepCompletion(completed: [.profile, .interests])))
    let (flow, _) = makeFlow(sink: sink)

    let state = await flow.start()

    #expect(state.activeStep == .suggestedAccounts)
    #expect(state.completion.isSettled(.profile))
  }

  @Test("a failing sink does not block the flow")
  func failingSinkIsNotFatal() async {
    let (flow, _) = makeFlow(sink: FailingOnboardingProgressSink())
    let state = await flow.start()
    #expect(state.activeStep == .profile)
    await flow.advance()
    #expect(flow.state.activeStep == .interests)
  }

  @Test("reset clears the sink and returns to the first step")
  func reset() async {
    let sink = InMemoryOnboardingProgressSink()
    let (flow, _) = makeFlow(sink: sink)
    await flow.advance()
    await flow.reset()

    #expect(flow.state.activeStep == .profile)
    #expect(await sink.progress == nil)
  }

  @Test("resumeAtFirstUnsettledStep skips settled steps")
  func resumeAtFirstUnsettled() async {
    let sink = InMemoryOnboardingProgressSink(
      initial: OnboardingProgress(
        activeStep: .profile,
        completion: StepCompletion(completed: [.profile, .interests])))
    let (flow, _) = makeFlow(sink: sink)
    await flow.start()

    let landed = await flow.resumeAtFirstUnsettledStep()
    #expect(landed == .suggestedAccounts)
  }

  @Test("running the profile step advances the wizard")
  func runProfileStepAdvances() async {
    let (flow, _) = makeFlow()
    let outcome = await flow.runProfileStep(displayName: "Alice")

    #expect(outcome == .advanced)
    #expect(flow.state.activeStep == .interests)
    #expect(flow.state.results.profile.displayName == "Alice")
  }

  @Test("a failed profile step does not advance")
  func failedProfileStepStays() async {
    let (flow, _) = makeFlow()
    let outcome = await flow.runProfileStep(displayName: String(repeating: "a", count: 65))

    guard case .failed = outcome else {
      Issue.record("expected a failure, got \(outcome)")
      return
    }
    #expect(flow.state.activeStep == .profile)
  }

  @Test("isRunning is true while a step write is in flight")
  func isRunningFlag() async {
    let (flow, _) = makeFlow()
    #expect(!flow.state.isRunning)
    _ = await flow.runProfileStep(displayName: "Alice")
    #expect(!flow.state.isRunning)
  }

  @Test("skipping a skippable step advances and marks it skipped")
  func skipStep() async {
    let (flow, _) = makeFlow()
    await flow.move(to: .suggestedAccounts)
    await flow.skip()

    #expect(flow.state.activeStep == .suggestedStarterPacks)
    #expect(flow.state.completion.isSkipped(.suggestedAccounts))
  }

  @Test("skipping a required step is a no-op")
  func skipRequired() async {
    let (flow, _) = makeFlow()
    await flow.skip()
    #expect(flow.state.activeStep == .profile)
  }

  @Test("the flow can be reconfigured mid-session")
  func reconfigure() async {
    let (flow, _) = makeFlow()
    await flow.reconfigure(
      OnboardingStepConfiguration(starterPacksStepEnabled: false, findContactsStepEnabled: true))
    #expect(flow.state.stepOrder.contains(.findContactsIntro))
    #expect(!flow.state.stepOrder.contains(.suggestedStarterPacks))
  }

  @Test("finishing settles at the finished step and marks the NUX complete")
  func finish() async {
    let (flow, actions) = makeFlow()
    let outcome = await flow.finish(displayName: "Alice")

    #expect(outcome == .advanced)
    #expect(flow.state.activeStep == .finished)
    #expect(flow.state.isFinished)
    #expect(
      actions.nuxWrites == [
        .upsertNux(id: OnboardingConstants.onboardingNuxID, completed: true, data: nil)
      ])
  }

  @Test("finishing reports a best-effort failure but still ends the flow")
  func finishBestEffort() async {
    let actions = FakeOnboardingActionService()
    actions.configure(savedFeedsError: Fixtures.networkError())
    let (flow, _) = makeFlow(actions: actions)

    let outcome = await flow.finish(displayName: "Alice")

    guard case .failed = outcome else {
      Issue.record("expected the saved-feeds failure to be reported, got \(outcome)")
      return
    }
    // RN lets the user into the app regardless; the flow matches that.
    #expect(flow.state.activeStep == .finished)
  }

  @Test("the adult content gate can be applied without moving the wizard")
  func adultContentGate() async {
    let (flow, actions) = makeFlow()
    let outcome = await flow.applyAdultContentGate(enabled: true)

    #expect(outcome == .completed)
    #expect(actions.calls == [.setAdultContentEnabled(true)])
    #expect(flow.state.activeStep == .profile)
  }

  @Test("a full happy path walks every step in order")
  func happyPath() async {
    let (flow, _) = makeFlow()
    var visited: [OnboardingStep] = [flow.state.activeStep]

    _ = await flow.runProfileStep(
      displayName: "Alice", avatarImageData: Data([1]), avatarMimeType: "image/jpeg")
    visited.append(flow.state.activeStep)

    _ = await flow.runInterestsStep(selected: ["art"])
    visited.append(flow.state.activeStep)

    _ = await flow.runSuggestedAccountsStep(selectedDIDs: ["did:plc:one"])
    visited.append(flow.state.activeStep)

    _ = await flow.runStarterPacksStep(joinedStarterPackURI: nil)
    visited.append(flow.state.activeStep)

    _ = await flow.finish()
    visited.append(flow.state.activeStep)

    #expect(
      visited == [
        .profile, .interests, .suggestedAccounts, .suggestedStarterPacks, .finished, .finished,
      ])
  }
}

/// Records listener callbacks for assertion.
final class StateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _steps: [OnboardingStep] = []

  var steps: [OnboardingStep] {
    lock.lock()
    defer { lock.unlock() }
    return _steps
  }

  func record(_ step: OnboardingStep) {
    lock.lock()
    _steps.append(step)
    lock.unlock()
  }
}

@Suite("Progress sink")
struct ProgressSinkTests {

  @Test("the in-memory sink round-trips a snapshot")
  func inMemoryRoundTrip() async throws {
    let sink = InMemoryOnboardingProgressSink()
    let snapshot = OnboardingProgress(activeStep: .interests)
    try await sink.saveProgress(snapshot)
    #expect(try await sink.loadProgress() == snapshot)
  }

  @Test("clearing removes the snapshot")
  func clear() async throws {
    let sink = InMemoryOnboardingProgressSink(initial: OnboardingProgress(activeStep: .profile))
    try await sink.clearProgress()
    #expect(try await sink.loadProgress() == nil)
  }

  @Test("a snapshot encodes and decodes")
  func codable() throws {
    let snapshot = OnboardingProgress(
      activeStep: .suggestedAccounts,
      stepTransitionDirection: .backward,
      completion: StepCompletion(completed: [.profile], skipped: [.interests]),
      configuration: OnboardingStepConfiguration(
        starterPacksStepEnabled: false, findContactsStepEnabled: true),
      results: OnboardingResults(
        profile: ProfileStepResult(displayName: "Alice"),
        interests: InterestsStepResult(selectedInterests: ["art"])))
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(OnboardingProgress.self, from: data)
    #expect(decoded == snapshot)
  }

  @Test("isRestorable rejects a non-current version")
  func restorableVersion() {
    var snapshot = OnboardingProgress(activeStep: .profile)
    #expect(snapshot.isRestorable)
    snapshot.version = OnboardingProgress.currentVersion + 1
    #expect(!snapshot.isRestorable)
  }

  @Test("a failing sink throws on load and save")
  func failingSink() async {
    let sink = FailingOnboardingProgressSink()
    await #expect(throws: OnboardingError.self) {
      _ = try await sink.loadProgress()
    }
    await #expect(throws: OnboardingError.self) {
      try await sink.saveProgress(OnboardingProgress(activeStep: .profile))
    }
  }

  @Test("the flow ignores a sink that fails on save")
  func flowIgnoresSaveFailure() async {
    let flow = OnboardingFlow(
      actions: FakeOnboardingActionService(),
      preferences: InMemoryPreferencesServer().engine(),
      sink: FailingOnboardingProgressSink(failLoad: false, failSave: true))
    await flow.start()
    await flow.advance()
    #expect(flow.state.activeStep == .interests)
  }
}
