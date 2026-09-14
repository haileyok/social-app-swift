import ATProtoClient
import Foundation
import Persistence
import Testing

@testable import LoginLogic

/// The stored-accounts "choose account" branch, ported from
/// `ChooseAccountForm.tsx` and `state/session`.
@Suite struct StoredAccountTests {

  /// An account with no access token cannot resume.
  @Test func resumeDecisionTable() {
    #expect(
      ResumeDecision.forAccount(makeStoredAccount()) == .resume)
    #expect(
      ResumeDecision.forAccount(makeStoredAccount(accessJwt: .some(nil)))
        == .freshLogin)
    #expect(
      ResumeDecision.forAccount(makeStoredAccount(accessJwt: .some("")))
        == .freshLogin)
  }

  @Test func accountsAreListedMostRecentlyUsedFirst() async {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: harness.store)

    try? await harness.store.upsertAccount(makeStoredAccount(did: "did:plc:one"))
    try? await harness.store.addAccount(
      makeStoredAccount(did: "did:plc:two"),
      session: PasswordSession(
        data: SessionData(
          service: "https://bsky.social", did: "did:plc:two", handle: "two.example.com",
          accessJwt: makeAccessToken(did: "did:plc:two"), refreshJwt: "r")))

    let accounts = await flow.storedAccounts()
    #expect(accounts.map(\.did) == ["did:plc:two", "did:plc:one"])
    #expect(await flow.currentAccountDID() == "did:plc:two")
  }

  @Test func anAccountWithoutTokensGoesBackToTheCredentialStep() async {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: harness.store)

    let outcome = await flow.signInWithStoredAccount(
      makeStoredAccount(handle: "alice.example.com", accessJwt: .some(nil)))
    #expect(outcome == .needsFreshLogin(identifier: "alice.example.com"))
    #expect(flow.state.step == .enteringCredentials)
    // The handle is prefilled and lowercased through the normal path.
    #expect(flow.state.identifier == "alice.example.com")
  }

  @Test func aResumableAccountIsSwitchedToAndBecomesCurrent() async {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: harness.store)
    let account = makeStoredAccount(did: "did:plc:alice", handle: "alice.example.com")
    try? await harness.store.upsertAccount(account)

    let outcome = await flow.signInWithStoredAccount(account)
    guard case .resumed(let resumed) = outcome else {
      Issue.record("expected resumed, got \(outcome)")
      return
    }
    #expect(resumed.did == "did:plc:alice")
    #expect(flow.state.step == .success)
    #expect(flow.state.account?.did == "did:plc:alice")
    #expect(await flow.currentAccountDID() == "did:plc:alice")
  }

  @Test func withoutAStoreResumeIsReportedAsAFailure() async {
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: nil)
    let outcome = await flow.signInWithStoredAccount(makeStoredAccount())
    guard case .failure(let error) = outcome else {
      Issue.record("expected failure, got \(outcome)")
      return
    }
    #expect(error.messageID == .unexpected)
    #expect(flow.state.step != .success)
  }

  @Test func forgettingAnAccountRemovesItEntirely() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: harness.store)
    try? await harness.store.upsertAccount(makeStoredAccount(did: "did:plc:alice"))

    try await flow.forgetAccount("did:plc:alice")
    #expect(await flow.storedAccounts().isEmpty)
    #expect(await flow.currentAccountDID() == nil)
  }

  @Test func forgettingAnUnknownAccountThrows() async {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: harness.store)
    await #expect(throws: SessionStore.StoreError.unknownAccount("did:plc:nope")) {
      try await flow.forgetAccount("did:plc:nope")
    }
  }

  @Test func withoutAStoreListingAccountsIsEmpty() async {
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: nil)
    #expect(await flow.storedAccounts().isEmpty)
    #expect(await flow.currentAccountDID() == nil)
  }

  @Test func aSuccessfulSignInIsRecordedInTheStore() async throws {
    let harness = await SessionStoreHarness()
    defer { harness.cleanUp() }
    let flow = LoginFlow(transport: ScriptedTransport(), sessionStore: harness.store)

    // The flow's own transport is what performs the login.
    let transport = ScriptedTransport(ScriptedTransport.createSession())
    let signedIn = LoginFlow(transport: transport, sessionStore: harness.store)
    _ = await flow.reset()
    let outcome = await signedIn.signIn(identifier: "alice.example.com", password: "hunter2")
    guard case .success = outcome else {
      Issue.record("expected success, got \(outcome)")
      return
    }
    #expect(await signedIn.storedAccounts().map(\.did) == ["did:plc:testaccount"])
    #expect(await signedIn.currentAccountDID() == "did:plc:testaccount")
  }
}
