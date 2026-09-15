import Foundation
import Observation
import OnboardingLogic
import SwiftUI

/// The SwiftUI-facing adapter over ``OnboardingFlow``.
///
/// `OnboardingFlow` exposes a `Sendable` value state plus an `addListener`
/// callback rather than being `Observable` itself (it is deliberately usable off
/// the main actor and from Linux CI). This type is the bridge: it registers one
/// listener, republishes every transition on the main actor, and holds the parts
/// of state that are genuinely the view's own - the in-progress profile name,
/// the interest selection not yet committed, the suggestion lists, and which
/// failure is on screen.
///
/// Every decision still belongs to the flow. This type calls
/// ``OnboardingFlow/advance()``, ``skip()``, ``goBack()``, ``skipContacts()``,
/// ``runProfileStep(displayName:handle:avatarImageData:avatarMimeType:)``,
/// ``runInterestsStep(selected:required:)``,
/// ``runSuggestedAccountsStep(selectedDIDs:via:)``,
/// ``runStarterPacksStep(joinedStarterPackURI:)`` and
/// ``OnboardingFlow/finish(displayName:avatarImageData:avatarMimeType:)`` and
/// renders whatever they report; it re-derives no rule.
@MainActor
@Observable
public final class OnboardingWizardModel {
  /// The flow's state, mirrored so SwiftUI re-reads it on change.
  public private(set) var state: OnboardingState

  /// The flow this adapter renders.
  public let flow: OnboardingFlow

  /// The app-supplied pieces the flow does not own.
  public let dependencies: OnboardingViewDependencies

  // MARK: - View-owned state

  /// The display name being edited on the profile step.
  public var displayName = ""
  /// The interests selected on the interests step, not yet committed.
  public var selectedInterests: [String] = []
  /// The suggested accounts the user chose to follow.
  public var selectedSuggestedDIDs: Set<String> = []
  /// The suggested starter pack the user chose to join.
  public var selectedStarterPackURI: String?
  /// The failure on screen, when a step write failed.
  public private(set) var failure: OnboardingError?
  /// The suggested accounts for the current interests, best-effort.
  public private(set) var suggestedUsers: [SuggestedUser] = []
  /// The suggested starter packs for the current interests, best-effort.
  public private(set) var suggestedStarterPacks: [SuggestedStarterPack] = []
  /// Whether a suggestion fetch is in flight.
  public private(set) var isLoadingSuggestions = false
  /// Whether the suggestion fetch failed, so the step can offer a retry.
  public private(set) var suggestionsFailed = false

  private var hasStarted = false

  /// Creates an adapter over a flow.
  ///
  /// - Parameters:
  ///   - flow: the logic flow, defaulting to a session-free one that can still
  ///     render and navigate every step.
  ///   - dependencies: the app-supplied suggestion service and completion hook.
  public init(
    flow: OnboardingFlow = OnboardingFlow(
      actions: InertOnboardingActionService(),
      preferences: OnboardingViewDependencies.defaultPreferencesEngine()),
    dependencies: OnboardingViewDependencies = .default
  ) {
    self.flow = flow
    self.dependencies = dependencies
    self.state = flow.state
    self.selectedInterests = flow.state.results.interests.selectedInterests
    self.displayName = flow.state.results.profile.displayName
    flow.addListener { [weak self] newState in
      Task { @MainActor in
        self?.state = newState
      }
    }
  }

  // MARK: - Derived view state

  /// The step the user is on.
  public var activeStep: OnboardingStep { state.activeStep }

  /// The transition direction, for the container's animated step change.
  public var transitionDirection: StepTransitionDirection { state.stepTransitionDirection }

  /// Whether a step write is in flight.
  public var isRunning: Bool { state.isRunning }

  /// The text the progress indicator shows, or nil when there is nothing to show.
  public var progressText: String? {
    guard !state.isFinished, state.totalSteps > 0 else { return nil }
    return OnboardingCopy.stepPosition(state.activeStepIndex, of: state.totalSteps)
  }

  /// Whether the header's back affordance should render.
  public var canGoBack: Bool { state.canGoBack }

  /// Whether the footer's skip affordance should render.
  ///
  /// This is exactly the logic layer's skippability model - the step definition's
  /// ``StepSkippability`` - so the view never decides which steps may be
  /// bypassed.
  public var canSkip: Bool { state.canSkipActiveStep }

  /// The display name validation result for the current field value.
  public var displayNameValidation: ProfileValidation.DisplayNameValidation {
    ProfileValidation.validateDisplayName(displayName)
  }

  /// Whether the profile step's continue affordance may proceed.
  public var canContinue: Bool { !isRunning }

  // MARK: - Lifecycle

  /// Loads saved progress and adopts it. Called once from the screen's `task`.
  public func start() async {
    guard !hasStarted else { return }
    hasStarted = true
    let restored = await flow.start()
    if restored.results.interests.selectedInterests.isEmpty == false {
      selectedInterests = restored.results.interests.selectedInterests
    }
    if !restored.results.profile.displayName.isEmpty {
      displayName = restored.results.profile.displayName
    }
    await loadSuggestionsIfNeeded()
  }

  // MARK: - Navigation

  /// Advances one step through the flow.
  public func advance() async {
    clearFailure()
    await flow.advance()
    await loadSuggestionsIfNeeded()
  }

  /// Advances past the active step by skipping it.
  public func skip() async {
    clearFailure()
    await flow.skip()
    await loadSuggestionsIfNeeded()
  }

  /// Steps back one step.
  public func goBack() async {
    clearFailure()
    await flow.goBack()
  }

  /// Skips the find-contacts pair.
  public func skipContacts() async {
    clearFailure()
    await flow.skipContacts()
    await loadSuggestionsIfNeeded()
  }

  /// Records an interest toggle without committing it.
  public func toggleInterest(_ tag: String) {
    if let index = selectedInterests.firstIndex(of: tag) {
      selectedInterests.remove(at: index)
    } else {
      selectedInterests.append(tag)
    }
  }

  /// Whether a tag is selected.
  public func isSelected(_ tag: String) -> Bool {
    selectedInterests.contains(tag)
  }

  /// Toggles a suggested account's follow selection.
  public func toggleSuggestedAccount(_ did: String) {
    if selectedSuggestedDIDs.contains(did) {
      selectedSuggestedDIDs.remove(did)
    } else {
      selectedSuggestedDIDs.insert(did)
    }
  }

  /// Selects every suggested account that is neither blocked nor muted.
  public func selectAllSuggestedAccounts() {
    selectedSuggestedDIDs = Set(
      suggestedUsers.filter { !$0.isBlockedOrBlocking && !$0.isMuted }.map(\.did))
  }

  /// Selects a starter pack, or clears the choice when the same one is toggled.
  public func selectStarterPack(_ uri: String) {
    selectedStarterPackURI = selectedStarterPackURI == uri ? nil : uri
  }

  /// Jumps to a specific step, for the fixture surface's per-step capture.
  ///
  /// The move goes through the flow, so a step the current configuration does
  /// not include is refused by the wizard rather than by the view.
  public func setStep(_ step: OnboardingStep) async {
    clearFailure()
    await flow.move(to: step)
    await loadSuggestionsIfNeeded()
  }

  // MARK: - Step execution

  /// Runs the profile step and advances on success.
  public func submitProfile(
    avatarImageData: Data? = nil, avatarMimeType: String? = nil
  ) async {
    clearFailure()
    let outcome = await flow.runProfileStep(
      displayName: displayName, avatarImageData: avatarImageData,
      avatarMimeType: avatarMimeType)
    handle(outcome)
  }

  /// Runs the interests step and advances on success.
  public func submitInterests() async {
    clearFailure()
    let outcome = await flow.runInterestsStep(
      selected: selectedInterests, required: dependencies.interestsRequired)
    handle(outcome)
  }

  /// Runs the suggested-accounts step and advances on success.
  public func submitSuggestedAccounts() async {
    clearFailure()
    let outcome = await flow.runSuggestedAccountsStep(
      selectedDIDs: Array(selectedSuggestedDIDs))
    handle(outcome)
  }

  /// Records the chosen starter pack and advances.
  public func submitStarterPacks() async {
    clearFailure()
    let outcome = await flow.runStarterPacksStep(joinedStarterPackURI: selectedStarterPackURI)
    handle(outcome)
  }

  /// Finishes the flow, then reports completion to the app.
  public func finish() async {
    clearFailure()
    let outcome = await flow.finish(displayName: displayName.isEmpty ? nil : displayName)
    handle(outcome)
    dependencies.onFinished()
  }

  /// Loads the suggestions the current step needs, once per entry.
  public func loadSuggestionsIfNeeded() async {
    switch activeStep {
    case .suggestedAccounts:
      await loadSuggestedUsers()
    case .suggestedStarterPacks:
      await loadSuggestedStarterPacks()
    default:
      break
    }
  }

  /// Dismisses the failure banner.
  public func clearFailure() {
    failure = nil
  }

  // MARK: - Internals

  /// Fetches the suggested accounts for the current interests.
  private func loadSuggestedUsers() async {
    isLoadingSuggestions = true
    suggestionsFailed = false
    defer { isLoadingSuggestions = false }
    do {
      let page = try await dependencies.suggestionService.suggestedUsers(
        category: nil, limit: 25, interests: selectedInterests)
      suggestedUsers = page.actors
    } catch {
      suggestedUsers = []
      suggestionsFailed = true
    }
  }

  /// Fetches the suggested starter packs for the current interests.
  private func loadSuggestedStarterPacks() async {
    isLoadingSuggestions = true
    suggestionsFailed = false
    defer { isLoadingSuggestions = false }
    do {
      suggestedStarterPacks = try await dependencies.suggestionService.suggestedStarterPacks(
        limit: 10, interests: selectedInterests)
    } catch {
      suggestedStarterPacks = []
      suggestionsFailed = true
    }
  }

  /// Surfaces a failed outcome and re-seeds the flow-owned results.
  private func handle(_ outcome: StepOutcome) {
    switch outcome {
    case .advanced, .completed:
      failure = nil
    case .failed(let error):
      failure = error
    }
  }
}
