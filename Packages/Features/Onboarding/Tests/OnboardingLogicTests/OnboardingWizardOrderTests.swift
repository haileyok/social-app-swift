import Foundation
import Testing

@testable import OnboardingLogic

@Suite("Onboarding wizard step order and configuration")
struct OnboardingWizardOrderTests {

  @Test("default configuration matches the RN screen map")
  func defaultConfiguration() {
    let wizard = OnboardingWizard()
    #expect(
      wizard.stepOrder == [
        .profile, .interests, .suggestedAccounts, .suggestedStarterPacks, .finished,
      ])
  }

  @Test("find-contacts steps are included when enabled")
  func findContactsEnabled() {
    let wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(
        starterPacksStepEnabled: false, findContactsStepEnabled: true))
    #expect(
      wizard.stepOrder == [
        .profile, .interests, .suggestedAccounts, .findContactsIntro, .findContacts, .finished,
      ])
  }

  @Test("the active step falls back to the first enabled step")
  func activeStepFallback() {
    let wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(starterPacksStepEnabled: true))
    #expect(wizard.activeStep == .profile)
  }

  @Test("progress order excludes find-contacts and finished")
  func progressOrder() {
    let wizard = OnboardingWizard(
      configuration: OnboardingStepConfiguration(
        starterPacksStepEnabled: true, findContactsStepEnabled: true))
    #expect(
      wizard.progressStepOrder == [
        .profile, .interests, .suggestedAccounts, .suggestedStarterPacks, .findContactsIntro,
      ])
  }
}
