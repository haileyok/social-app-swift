import Foundation
import Testing

@testable import OnboardingLogic

@Suite("Wizard transitions")
struct OnboardingWizardTransitionTests {

  @Test("advance moves forward and settles the step")
  func advanceSettles() {
    var wizard = OnboardingWizard()
    wizard.advance()
    #expect(wizard.activeStep == .interests)
    #expect(wizard.stepTransitionDirection == .forward)
    #expect(wizard.completion.isSettled(.profile))
    #expect(!wizard.completion.isSkipped(.profile))
  }

  @Test("advance at the last step does not move")
  func advanceAtEnd() {
    var wizard = OnboardingWizard()
    wizard.move(to: .finished)
    wizard.advance()
    #expect(wizard.activeStep == .finished)
  }

  @Test("goBack moves backward and marks the direction")
  func goBackDirection() {
    var wizard = OnboardingWizard()
    wizard.advance()
    wizard.goBack()
    #expect(wizard.activeStep == .profile)
    #expect(wizard.stepTransitionDirection == .backward)
  }

  @Test("goBack at the first step does not move")
  func goBackAtStart() {
    var wizard = OnboardingWizard()
    wizard.goBack()
    #expect(wizard.activeStep == .profile)
  }

  @Test("goBack preserves completion so re-entering a step keeps its results")
  func goBackPreservesCompletion() {
    var wizard = OnboardingWizard()
    wizard.setInterestsResult(InterestsStepResult(selectedInterests: ["art"]))
    wizard.advance()
    wizard.goBack()
    #expect(wizard.completion.isSettled(.profile))
    #expect(wizard.results.interests.selectedInterests == ["art"])
  }

  @Test("canGoBack is false only on the first step")
  func canGoBack() {
    var wizard = OnboardingWizard()
    #expect(!wizard.canGoBack)
    wizard.advance()
    #expect(wizard.canGoBack)
  }

  @Test("skip settles the step as skipped")
  func skipMarksSkipped() {
    var wizard = OnboardingWizard()
    wizard.move(to: .suggestedAccounts)
    wizard.skip()
    #expect(wizard.activeStep == .suggestedStarterPacks)
    #expect(wizard.completion.isSkipped(.suggestedAccounts))
  }

  @Test("skip is refused on a required step")
  func skipRequiredRefused() {
    var wizard = OnboardingWizard()
    #expect(!wizard.canSkipActiveStep)
    wizard.skip()
    #expect(wizard.activeStep == .profile)
    #expect(!wizard.completion.isSettled(.profile))
  }

  @Test("skip is allowed on the starter packs step")
  func skipStarterPacks() {
    var wizard = OnboardingWizard()
    wizard.move(to: .suggestedStarterPacks)
    #expect(wizard.canSkipActiveStep)
    wizard.skip()
    #expect(wizard.activeStep == .finished)
  }

  @Test("skipContacts settles both find-contacts steps")
  func skipContactsSettlesPair() {
    var wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(
        starterPacksStepEnabled: true, findContactsStepEnabled: true))
    wizard.move(to: .findContactsIntro)
    wizard.skipContacts()
    #expect(wizard.activeStep == .finished)
    #expect(wizard.completion.isSettled(.findContactsIntro))
    #expect(wizard.completion.isSkipped(.findContacts))
  }

  @Test("skipContacts is a no-op when find-contacts is disabled")
  func skipContactsDisabled() {
    var wizard = OnboardingWizard()
    wizard.move(to: .suggestedAccounts)
    wizard.skipContacts()
    #expect(wizard.activeStep == .suggestedAccounts)
  }

  @Test("move rejects a disabled step")
  func moveRejectsDisabled() {
    var wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(starterPacksStepEnabled: false))
    let moved = wizard.move(to: .suggestedStarterPacks)
    #expect(!moved)
    #expect(wizard.activeStep == .profile)
  }

  @Test("nextStep and previousStep follow the enabled order")
  func derivedNeighbours() {
    let wizard = OnboardingWizard()
    #expect(wizard.nextStep(after: .profile) == .interests)
    #expect(wizard.nextStep(after: .finished) == nil)
    #expect(wizard.previousStep(before: .profile) == nil)
    #expect(wizard.previousStep(before: .interests) == .profile)
    #expect(wizard.nextStep == .interests)
    #expect(wizard.previousStep == nil)
  }

  @Test("display index folds find-contacts onto its intro")
  func displayIndex() {
    var wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(
        starterPacksStepEnabled: true, findContactsStepEnabled: true))
    wizard.move(to: .findContacts)
    #expect(wizard.displayStepIndex == wizard.progressStepOrder.firstIndex(of: .findContactsIntro))
    #expect(wizard.totalDisplaySteps == 5)
  }

  @Test("reconfigure drops completion for steps it removes")
  func reconfigureDropsCompletion() {
    var wizard = OnboardingWizard()
    wizard.advance()
    wizard.advance()
    wizard.advance()
    #expect(wizard.activeStep == .suggestedStarterPacks)
    wizard.reconfigure(
      OnboardingStepConfiguration(starterPacksStepEnabled: false, findContactsStepEnabled: false))
    // The active step is no longer enabled, so the wizard falls back to the
    // first enabled step.
    #expect(wizard.activeStep == .profile)
    #expect(!wizard.completion.isSettled(.suggestedStarterPacks))
  }

  @Test("reconfigure keeps the active step when it is still enabled")
  func reconfigureKeepsActiveStep() {
    var wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(starterPacksStepEnabled: false))
    wizard.move(to: .suggestedAccounts)
    wizard.reconfigure(OnboardingStepConfiguration(starterPacksStepEnabled: true))
    #expect(wizard.activeStep == .suggestedAccounts)
  }
}

@Suite("Wizard resumability")
struct OnboardingWizardResumeTests {

  @Test("progress round-trips through the snapshot")
  func progressRoundTrip() {
    var wizard = OnboardingWizard()
    wizard.setInterestsResult(InterestsStepResult(selectedInterests: ["art", "music"]))
    wizard.advance()
    let snapshot = wizard.progress

    let restored = OnboardingWizard(configuration: wizard.configuration, progress: snapshot)
    #expect(restored == wizard)
  }

  @Test("a snapshot from another version is discarded")
  func versionMismatchDiscarded() {
    var wizard = OnboardingWizard()
    wizard.advance()
    var snapshot = wizard.progress
    snapshot.version = OnboardingProgress.currentVersion + 1
    let restored = OnboardingWizard(configuration: wizard.configuration, progress: snapshot)
    #expect(restored.activeStep == .profile)
    #expect(restored.completion == StepCompletion())
  }

  @Test("a snapshot naming a disabled step is discarded")
  func disabledStepDiscarded() {
    var wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(
        starterPacksStepEnabled: true, findContactsStepEnabled: true))
    wizard.move(to: .findContacts)
    let snapshot = wizard.progress
    let restored = OnboardingWizard(
      configuration: OnboardingStepConfiguration(starterPacksStepEnabled: false),
      progress: snapshot)
    #expect(restored.activeStep == .profile)
  }

  @Test("a nil snapshot starts fresh")
  func nilSnapshotStartsFresh() {
    let restored = OnboardingWizard(configuration: .default, progress: nil)
    #expect(restored.activeStep == .profile)
  }

  @Test("firstUnsettledStep skips settled steps")
  func firstUnsettledStep() {
    var wizard = OnboardingWizard()
    wizard.advance()
    wizard.advance()
    wizard.goBack()
    // profile and interests settled; back on interests.
    #expect(wizard.activeStep == .interests)
    #expect(wizard.firstUnsettledStep == .suggestedAccounts)
  }

  @Test("firstUnsettledStep is finished when everything is settled")
  func firstUnsettledStepWhenDone() {
    var wizard = OnboardingWizard()
    for step in wizard.stepOrder {
      wizard.settle(step, skipped: false)
    }
    #expect(wizard.firstUnsettledStep == .finished)
  }

  @Test("jumpToFirstUnsettledStep lands on the derived step")
  func jumpToUnsettled() {
    var wizard = OnboardingWizard()
    wizard.advance()
    wizard.settle(.interests, skipped: false)
    wizard.goBack()
    let landed = wizard.jumpToFirstUnsettledStep()
    #expect(landed == .suggestedAccounts)
    #expect(wizard.activeStep == .suggestedAccounts)
  }

  @Test("unsettle makes a step need work again")
  func unsettle() {
    var wizard = OnboardingWizard()
    wizard.advance()
    #expect(wizard.completion.isSettled(.profile))
    wizard.unsettle(.profile)
    #expect(!wizard.completion.isSettled(.profile))
  }
}
