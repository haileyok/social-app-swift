import Foundation
import Testing

@testable import StarterPacksLogic

/// Asserts the wizard state machine.
///
/// Ports the `reducer` in `src/screens/StarterPack/Wizard/State.tsx`, including
/// the two guards that read oddly until you look at RN's source: the profile cap
/// is `length > MAX`, and the name is sliced to 50.
@Suite("StarterPackWizard")
struct StarterPackWizardTests {
  private func freshWizard() -> StarterPackWizard {
    StarterPackWizard(targetProfile: Fixtures.wizardProfile(Fixtures.authorDID, handle: "author"))
  }

  // MARK: - Initial state

  @Test("a fresh wizard starts on details seeded with the target profile")
  func freshInitialState() {
    let wizard = freshWizard()
    #expect(wizard.currentStep == .details)
    #expect(wizard.profiles.count == 1)
    #expect(wizard.profiles.first?.did == Fixtures.authorDID)
    #expect(wizard.feeds.isEmpty)
    #expect(wizard.name == nil)
    #expect(wizard.description == nil)
    #expect(wizard.canNext)
    #expect(wizard.processing == false)
    #expect(wizard.transitionDirection == .forward)
    #expect(wizard.targetDID == Fixtures.authorDID)
  }

  @Test("an edit wizard seeds name, description, members and feeds from the pack")
  func editInitialState() {
    let wizard = StarterPackWizard(
      editingName: "Existing",
      description: "Desc",
      listItems: [
        Fixtures.wizardProfile(Fixtures.memberDID), Fixtures.wizardProfile(Fixtures.otherDID),
      ],
      feeds: [Fixtures.wizardFeed("a")],
      targetProfile: Fixtures.wizardProfile(Fixtures.authorDID))
    #expect(wizard.name == "Existing")
    #expect(wizard.description == "Desc")
    #expect(wizard.profiles.count == 2)
    #expect(wizard.feeds.count == 1)
    #expect(wizard.currentStep == .details)
  }

  // MARK: - Navigation

  @Test("next advances details -> profiles -> feeds and stops at feeds")
  func nextAdvances() {
    var wizard = freshWizard()
    wizard.next()
    #expect(wizard.currentStep == .profiles)
    #expect(wizard.transitionDirection == .forward)
    wizard.next()
    #expect(wizard.currentStep == .feeds)
    // Next at the last step is a no-op.
    wizard.next()
    #expect(wizard.currentStep == .feeds)
  }

  @Test("back steps to details and stops there")
  func backSteps() {
    var wizard = freshWizard()
    wizard.move(to: .feeds)
    wizard.back()
    #expect(wizard.currentStep == .profiles)
    #expect(wizard.transitionDirection == .backward)
    wizard.back()
    #expect(wizard.currentStep == .details)
    // Back at the first step is a no-op and leaves the direction alone.
    wizard.back()
    #expect(wizard.currentStep == .details)
    #expect(wizard.transitionDirection == .backward)
  }

  @Test("moving to the same step changes nothing")
  func moveToSameStep() {
    var wizard = freshWizard()
    #expect(wizard.move(to: .details) == false)
    #expect(wizard.transitionDirection == .forward)
  }

  @Test("moving forward and backward records the direction by order")
  func moveDirection() {
    var wizard = freshWizard()
    wizard.move(to: .feeds)
    #expect(wizard.transitionDirection == .forward)
    wizard.move(to: .details)
    #expect(wizard.transitionDirection == .backward)
  }

  // MARK: - Name and description

  @Test("the name is sliced to 50 characters")
  func nameSliced() {
    var wizard = freshWizard()
    let long = String(repeating: "a", count: 80)
    wizard.setName(long)
    #expect(wizard.name?.count == 50)
  }

  @Test("a name at or under 50 characters is kept whole")
  func nameKept() {
    var wizard = freshWizard()
    let name = String(repeating: "a", count: 50)
    wizard.setName(name)
    #expect(wizard.name == name)
  }

  @Test("the description is not sliced by the reducer")
  func descriptionNotSliced() {
    var wizard = freshWizard()
    let description = String(repeating: "b", count: 400)
    wizard.setDescription(description)
    #expect(wizard.description?.count == 400)
  }

  // MARK: - Caps

  @Test("the profile cap admits the 151st profile and refuses the 152nd")
  func profileCapOffByOne() {
    var wizard = freshWizard()
    // The wizard starts with one profile, so add maxSize more to reach 151.
    for index in 0..<StarterPackConstants.maxSize {
      wizard.addProfile(Fixtures.wizardProfile("did:plc:p\(index)"))
    }
    #expect(wizard.profiles.count == StarterPackConstants.maxSize + 1)

    wizard.clearRefusals()
    wizard.addProfile(Fixtures.wizardProfile("did:plc:over"))
    // Refused: the list stays at 151 and a refusal is recorded.
    #expect(wizard.profiles.count == StarterPackConstants.maxSize + 1)
    #expect(wizard.lastRefusals == [.profileCapReached(limit: StarterPackConstants.maxSize)])
  }

  @Test("the profile cap refusal names the limit in RN's words")
  func profileCapMessage() {
    #expect(WizardRefusal.profileCapReached(limit: 150).message == "You may only add up to 150 profiles")
    #expect(WizardRefusal.feedCapReached(limit: 3).message == "You may only add up to 3 feeds")
  }

  @Test("the feed cap refuses the fourth feed")
  func feedCap() {
    var wizard = freshWizard()
    for rkey in ["a", "b", "c"] {
      wizard.addFeed(Fixtures.wizardFeed(rkey))
    }
    #expect(wizard.feeds.count == 3)

    wizard.clearRefusals()
    wizard.addFeed(Fixtures.wizardFeed("d"))
    #expect(wizard.feeds.count == 3)
    #expect(wizard.lastRefusals == [.feedCapReached(limit: 3)])
  }

  @Test("members can be removed by DID and feeds by URI")
  func removal() {
    var wizard = freshWizard()
    wizard.addProfile(Fixtures.wizardProfile(Fixtures.memberDID))
    wizard.removeProfile(did: Fixtures.memberDID)
    #expect(wizard.profiles.count == 1)

    wizard.addFeed(Fixtures.wizardFeed("a"))
    wizard.addFeed(Fixtures.wizardFeed("b"))
    wizard.removeFeed(uri: Fixtures.wizardFeed("a").uri)
    #expect(wizard.feeds.map(\.uri) == [Fixtures.wizardFeed("b").uri])
  }

  @Test("membership checks report what is already selected")
  func membershipChecks() {
    var wizard = freshWizard()
    wizard.addProfile(Fixtures.wizardProfile(Fixtures.memberDID))
    wizard.addFeed(Fixtures.wizardFeed("a"))
    #expect(wizard.hasProfile(did: Fixtures.memberDID))
    #expect(wizard.hasProfile(did: Fixtures.otherDID) == false)
    #expect(wizard.hasFeed(uri: Fixtures.wizardFeed("a").uri))
    #expect(wizard.hasFeed(uri: Fixtures.wizardFeed("z").uri) == false)
  }

  // MARK: - Step gates

  @Test("the people step needs eight members to continue")
  func minimumProfilesGate() {
    var wizard = freshWizard()
    wizard.move(to: .profiles)
    // One profile: below the minimum.
    #expect(wizard.meetsMinimumProfiles == false)
    #expect(wizard.canSubmitCurrentStep == false)
    #expect(wizard.remainingProfilesNeeded() == 7)

    for index in 0..<7 {
      wizard.addProfile(Fixtures.wizardProfile("did:plc:p\(index)"))
    }
    #expect(wizard.profiles.count == 8)
    #expect(wizard.meetsMinimumProfiles)
    #expect(wizard.canSubmitCurrentStep)
    #expect(wizard.remainingProfilesNeeded() == 0)
  }

  @Test("the details and feeds steps have no minimum")
  func noMinimumOnOtherSteps() {
    var wizard = freshWizard()
    #expect(wizard.canSubmitCurrentStep)
    wizard.move(to: .feeds)
    #expect(wizard.canSubmitCurrentStep)
  }

  @Test("processing disables continue on every step")
  func processingDisablesContinue() {
    var wizard = freshWizard()
    wizard.setProcessing(true)
    #expect(wizard.canSubmitCurrentStep == false)
    wizard.setProcessing(false)
    #expect(wizard.canSubmitCurrentStep)
  }

  @Test("canNext false disables continue")
  func canNextGate() {
    var wizard = freshWizard()
    wizard.canNext = false
    #expect(wizard.canSubmitCurrentStep == false)
  }

  @Test("the footer label is Skip on the feeds step with no feeds, else Finish")
  func footerLabels() {
    var wizard = freshWizard()
    #expect(wizard.nextButtonLabel == "Next")
    wizard.move(to: .profiles)
    #expect(wizard.nextButtonLabel == "Next")
    wizard.move(to: .feeds)
    #expect(wizard.nextButtonLabel == "Skip")
    wizard.addFeed(Fixtures.wizardFeed("a"))
    #expect(wizard.nextButtonLabel == "Finish")
  }

  @Test("the edit affordance is on for more than one person or any feed")
  func editEnabled() {
    var wizard = freshWizard()
    #expect(wizard.isEditEnabled == false)
    wizard.move(to: .profiles)
    #expect(wizard.isEditEnabled == false)
    wizard.addProfile(Fixtures.wizardProfile(Fixtures.memberDID))
    #expect(wizard.isEditEnabled)

    wizard.move(to: .feeds)
    #expect(wizard.isEditEnabled == false)
    wizard.addFeed(Fixtures.wizardFeed("a"))
    #expect(wizard.isEditEnabled)
  }

  @Test("the item count and limit reflect the current step")
  func itemCounts() {
    var wizard = freshWizard()
    wizard.move(to: .profiles)
    #expect(wizard.currentItemsCount == 1)
    #expect(wizard.currentItemsLimit == StarterPackConstants.maxSize)
    wizard.move(to: .feeds)
    #expect(wizard.currentItemsCount == 0)
    #expect(wizard.currentItemsLimit == StarterPackConstants.maximumFeeds)
  }

  @Test("errors are recorded and refusals can be cleared")
  func errorAndRefusals() {
    var wizard = freshWizard()
    wizard.setError("nope")
    #expect(wizard.error == "nope")
    wizard.addFeed(Fixtures.wizardFeed("a"))
    wizard.addFeed(Fixtures.wizardFeed("b"))
    wizard.addFeed(Fixtures.wizardFeed("c"))
    wizard.addFeed(Fixtures.wizardFeed("d"))
    #expect(wizard.lastRefusals.count == 1)
    wizard.clearRefusals()
    #expect(wizard.lastRefusals.isEmpty)
  }

  @Test("first and last step flags follow the order")
  func stepFlags() {
    var wizard = freshWizard()
    #expect(wizard.isFirstStep)
    #expect(wizard.isLastStep == false)
    wizard.move(to: .feeds)
    #expect(wizard.isFirstStep == false)
    #expect(wizard.isLastStep)
  }

  @Test("next and previous step are derived from the order")
  func adjacentSteps() {
    var wizard = freshWizard()
    #expect(wizard.nextStep == .profiles)
    #expect(wizard.previousStep == nil)
    wizard.move(to: .feeds)
    #expect(wizard.nextStep == nil)
    #expect(wizard.previousStep == .profiles)
  }

  // MARK: - Edit list

  @Test("the edit list shows feeds on the feeds step")
  func editListFeeds() {
    var wizard = freshWizard()
    wizard.addFeed(Fixtures.wizardFeed("a"))
    let entries = WizardEditList.entries(for: .feeds, wizard: wizard)
    #expect(entries == .feeds(wizard.feeds))
  }

  @Test("the edit list puts the target profile first on the people step")
  func editListProfiles() {
    var wizard = freshWizard()
    wizard.addProfile(Fixtures.wizardProfile(Fixtures.memberDID))
    wizard.addProfile(Fixtures.wizardProfile(Fixtures.otherDID))
    let entries = WizardEditList.entries(for: .profiles, wizard: wizard)
    guard case .profiles(let profiles) = entries else {
      Issue.record("expected profiles")
      return
    }
    #expect(profiles.first?.did == Fixtures.authorDID)
    #expect(profiles.map(\.did) == [Fixtures.authorDID, Fixtures.memberDID, Fixtures.otherDID])
  }

  @Test("the edit list excludes the target from the trailing members")
  func editListExcludesDuplicateTarget() {
    var wizard = StarterPackWizard(targetProfile: Fixtures.wizardProfile(Fixtures.authorDID))
    // A pack whose list contains the author is common; the author must appear once.
    wizard.addProfile(Fixtures.wizardProfile(Fixtures.authorDID))
    let entries = WizardEditList.entries(for: .profiles, wizard: wizard)
    guard case .profiles(let profiles) = entries else {
      Issue.record("expected profiles")
      return
    }
    #expect(profiles.map(\.did) == [Fixtures.authorDID])
  }

  // MARK: - Display labels

  @Test("a member label prefers the display name and falls back to the handle")
  func memberLabels() {
    let named = Fixtures.wizardProfile("did:plc:x", handle: "x.test", displayName: "Alice")
    #expect(named.displayLabel == "Alice")
    let unnamed = Fixtures.wizardProfile("did:plc:y", handle: "y.test")
    #expect(unnamed.displayLabel == "y.test")
  }

  @Test("a long member label is truncated with an ellipsis at 28 characters")
  func memberLabelTruncation() {
    let long = Fixtures.wizardProfile(
      "did:plc:x", handle: "x.test", displayName: String(repeating: "a", count: 40))
    #expect(long.displayLabel == String(repeating: "a", count: 28) + "\u{2026}")
  }

  @Test("a feed label uses its display name")
  func feedLabels() {
    #expect(Fixtures.wizardFeed("a", displayName: "Cool Feed").displayLabel == "Cool Feed")
  }
}
