import Foundation
import Preferences
import Testing

@testable import OnboardingLogic

@Suite("Profile step orchestration")
struct ProfileStepTests {

  private func makeRunner(
    wizard: OnboardingWizard = OnboardingWizard(),
    actions: FakeOnboardingActionService = FakeOnboardingActionService()
  ) -> (OnboardingStepRunner, FakeOnboardingActionService) {
    let preferences = InMemoryPreferencesServer().engine()
    return (
      OnboardingStepRunner(wizard: wizard, actions: actions, preferences: preferences), actions
    )
  }

  @Test("a display name and avatar produce an upload then a profile write")
  func uploadThenProfileWrite() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runProfileStep(
      displayName: "  Alice  ", avatarImageData: Data([1, 2, 3]),
      avatarMimeType: "image/jpeg")

    #expect(outcome == .advanced)
    #expect(
      actions.calls == [
        .uploadAvatar(mimeType: "image/jpeg", byteCount: 3),
        .upsertProfile(displayName: "Alice", avatarRef: "bafkreifakeblobref", viaURI: nil),
      ])
    #expect(runner.currentWizard.results.profile.displayName == "Alice")
    // The uploaded bytes are not retained on the result.
    #expect(runner.currentWizard.results.profile.avatarImageData == nil)
  }

  @Test("no avatar means no upload call")
  func noAvatarNoUpload() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runProfileStep(displayName: "Alice")

    #expect(outcome == .advanced)
    #expect(actions.uploadedAvatar == nil)
    #expect(
      actions.calls == [
        .upsertProfile(displayName: "Alice", avatarRef: nil, viaURI: nil)
      ])
    #expect(runner.currentWizard.results.profile.isCreatedAvatar)
  }

  @Test("an over-long display name is rejected before any network call")
  func overLongNameRejected() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runProfileStep(displayName: String(repeating: "a", count: 65))

    #expect(outcome == .failed(.displayNameTooLong(maxLength: 64)))
    #expect(actions.calls.isEmpty)
  }

  @Test("an invalid handle is rejected before any network call")
  func invalidHandleRejected() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runProfileStep(displayName: "Alice", handle: "nope")

    guard case .failed(.handleInvalid) = outcome else {
      Issue.record("expected an invalid-handle failure, got \(outcome)")
      return
    }
    #expect(actions.calls.isEmpty)
  }

  @Test("a valid handle passes validation and is not written")
  func validHandleNotWritten() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runProfileStep(displayName: "Alice", handle: "alice.test")

    #expect(outcome == .advanced)
    // The handle is not a profile field: no extra write accompanies it.
    #expect(actions.profileWrites.count == 1)
  }

  @Test("an empty display name is accepted and clears the field")
  func emptyDisplayNameAccepted() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runProfileStep(displayName: "   ")

    #expect(outcome == .advanced)
    #expect(
      actions.calls == [.upsertProfile(displayName: "", avatarRef: nil, viaURI: nil)])
  }

  @Test("an upload failure surfaces as a profile failure and writes nothing")
  func uploadFailure() async {
    let actions = FakeOnboardingActionService()
    actions.configure(uploadError: Fixtures.networkError())
    let (runner, _) = makeRunner(actions: actions)

    let outcome = await runner.runProfileStep(
      displayName: "Alice", avatarImageData: Data([1]), avatarMimeType: "image/jpeg")

    guard case .failed(.avatarUploadFailed(let underlying)) = outcome else {
      Issue.record("expected an avatar upload failure, got \(outcome)")
      return
    }
    // A network error carries no XRPC error code.
    #expect(underlying?.error == nil)
    #expect(actions.profileWrites.isEmpty)
  }

  @Test("a profile write failure is reported")
  func profileWriteFailure() async {
    let actions = FakeOnboardingActionService()
    actions.configure(profileError: Fixtures.xrpcError("InvalidRequest", message: "bad"))
    let (runner, _) = makeRunner(actions: actions)

    let outcome = await runner.runProfileStep(displayName: "Alice")

    guard case .failed(.profileWriteFailed(let underlying)) = outcome else {
      Issue.record("expected a profile write failure, got \(outcome)")
      return
    }
    #expect(underlying?.error == "InvalidRequest")
  }
}

@Suite("Interests step orchestration")
struct InterestsStepTests {

  private func makeRunner(
    actions: FakeOnboardingActionService = FakeOnboardingActionService()
  ) -> (OnboardingStepRunner, FakeOnboardingActionService) {
    let preferences = InMemoryPreferencesServer().engine()
    return (
      OnboardingStepRunner(wizard: OnboardingWizard(), actions: actions, preferences: preferences),
      actions
    )
  }

  @Test("the selection is written as given")
  func writesSelection() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runInterestsStep(selected: ["art", "music"])

    #expect(outcome == .advanced)
    #expect(actions.calls == [.setInterests(tags: ["art", "music"])])
    #expect(runner.currentWizard.results.interests.selectedInterests == ["art", "music"])
  }

  @Test("off-vocabulary tags are dropped before the write")
  func dropsUnknownTags() async {
    let (runner, actions) = makeRunner()
    _ = await runner.runInterestsStep(selected: ["art", "not-a-tag"])
    #expect(actions.calls == [.setInterests(tags: ["art"])])
    #expect(runner.currentWizard.results.interests.selectedInterests == ["art"])
  }

  @Test("an empty selection is allowed by default")
  func emptyAllowed() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runInterestsStep(selected: [])
    #expect(outcome == .advanced)
    #expect(actions.calls == [.setInterests(tags: [])])
  }

  @Test("an empty selection is refused when interests are required")
  func emptyRefusedWhenRequired() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runInterestsStep(selected: [], required: true)

    guard case .failed = outcome else {
      Issue.record("expected a failure, got \(outcome)")
      return
    }
    #expect(actions.calls.isEmpty)
  }

  @Test("a write failure is reported as an interests failure")
  func writeFailure() async {
    let actions = FakeOnboardingActionService()
    actions.configure(interestsError: Fixtures.xrpcError("InternalServerError"))
    let (runner, _) = makeRunner(actions: actions)

    let outcome = await runner.runInterestsStep(selected: ["art"])

    guard case .failed(.interestsWriteFailed(let underlying)) = outcome else {
      Issue.record("expected an interests failure, got \(outcome)")
      return
    }
    #expect(underlying?.error == "InternalServerError")
  }
}

@Suite("Suggested accounts step orchestration")
struct SuggestedAccountsStepTests {

  private func makeRunner(
    actions: FakeOnboardingActionService = FakeOnboardingActionService(),
    wizard: OnboardingWizard = OnboardingWizard()
  ) -> (OnboardingStepRunner, FakeOnboardingActionService) {
    let preferences = InMemoryPreferencesServer().engine()
    return (
      OnboardingStepRunner(wizard: wizard, actions: actions, preferences: preferences), actions
    )
  }

  @Test("a selection is followed in one batch, preserving order")
  func followsSelection() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runSuggestedAccountsStep(
      selectedDIDs: ["did:plc:one", "did:plc:two"])

    #expect(outcome == .advanced)
    #expect(
      actions.calls == [
        .createFollows(dids: ["did:plc:one", "did:plc:two"], viaURI: nil)
      ])
    #expect(
      runner.currentWizard.results.suggestedAccounts.followedDIDs
        == ["did:plc:one", "did:plc:two"])
  }

  @Test("an empty selection makes no follow call")
  func emptySelection() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.runSuggestedAccountsStep(selectedDIDs: [])
    #expect(outcome == .advanced)
    #expect(actions.calls.isEmpty)
    #expect(runner.currentWizard.results.suggestedAccounts.followedDIDs == [])
  }

  @Test("a starter-pack context is passed as `via`")
  func viaStarterPack() async {
    let (runner, actions) = makeRunner()
    let via = StarterPackRef(uri: "at://did:plc:creator/app.bsky.graph.starterpack/1", cid: "cid")
    _ = await runner.runSuggestedAccountsStep(selectedDIDs: ["did:plc:one"], via: via)

    #expect(
      actions.calls == [
        .createFollows(
          dids: ["did:plc:one"],
          viaURI: "at://did:plc:creator/app.bsky.graph.starterpack/1")
      ])
  }

  @Test("a follow failure is reported")
  func followFailure() async {
    let actions = FakeOnboardingActionService()
    actions.configure(followError: Fixtures.xrpcError("InvalidSwap"))
    let (runner, _) = makeRunner(actions: actions)

    let outcome = await runner.runSuggestedAccountsStep(selectedDIDs: ["did:plc:one"])

    guard case .failed(.followFailed(let underlying)) = outcome else {
      Issue.record("expected a follow failure, got \(outcome)")
      return
    }
    #expect(underlying?.error == "InvalidSwap")
  }
}

@Suite("Starter packs and adult-content steps")
struct StarterPacksAndGateTests {

  private func makeRunner(
    actions: FakeOnboardingActionService = FakeOnboardingActionService()
  ) -> (OnboardingStepRunner, FakeOnboardingActionService) {
    let preferences = InMemoryPreferencesServer().engine()
    return (
      OnboardingStepRunner(wizard: OnboardingWizard(), actions: actions, preferences: preferences),
      actions
    )
  }

  @Test("choosing a pack records its URI without writing anything")
  func choosePackRecordsOnly() async {
    let (runner, actions) = makeRunner()
    let uri = "at://did:plc:creator/app.bsky.graph.starterpack/1"
    let outcome = await runner.runStarterPacksStep(joinedStarterPackURI: uri)

    #expect(outcome == .advanced)
    #expect(actions.calls.isEmpty)
    #expect(runner.currentWizard.results.starterPacks.joinedStarterPackURI == uri)
  }

  @Test("declining to choose a pack records nil")
  func declinePack() async {
    let (runner, _) = makeRunner()
    _ = await runner.runStarterPacksStep(joinedStarterPackURI: nil)
    #expect(runner.currentWizard.results.starterPacks.joinedStarterPackURI == nil)
  }

  @Test("the adult-content gate writes the preference")
  func adultContentWrite() async {
    let (runner, actions) = makeRunner()
    let outcome = await runner.applyAdultContentGate(enabled: true)

    #expect(outcome == .completed)
    #expect(actions.calls == [.setAdultContentEnabled(true)])
  }

  @Test("the adult-content gate reports a write failure")
  func adultContentFailure() async {
    let actions = FakeOnboardingActionService()
    actions.configure(adultContentError: Fixtures.networkError())
    let (runner, _) = makeRunner(actions: actions)
    let outcome = await runner.applyAdultContentGate(enabled: false)
    guard case .failed(.preferencesUnavailable) = outcome else {
      Issue.record("expected a preferences failure, got \(outcome)")
      return
    }
  }
}
