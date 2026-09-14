import Foundation
import Testing

import ATProtoClient
import Lexicons

@testable import SettingsLogic

/// Handle validation and composition, ported from `lib/strings/handles.ts`.
@Suite struct HandleRulesTests {

  /// `createFullHandle` joins and trims dots.
  @Test func createFullHandle() {
    #expect(HandleRules.createFullHandle(name: "alice", domain: "example.com")
      == "alice.example.com")
    // A trailing dot on the name is trimmed.
    #expect(HandleRules.createFullHandle(name: "alice.", domain: "example.com")
      == "alice.example.com")
    // A leading dot on the domain is trimmed.
    #expect(HandleRules.createFullHandle(name: "alice", domain: ".example.com")
      == "alice.example.com")
    // Empty input yields the bare join, matching the TS behaviour.
    #expect(HandleRules.createFullHandle(name: "", domain: "") == ".")
  }

  /// `makeValidHandle` truncates, lowercases, and strips.
  @Test func makeValidHandle() {
    #expect(HandleRules.makeValidHandle("Alice") == "alice")
    #expect(HandleRules.makeValidHandle("alice.blue") == "aliceblue")
    #expect(HandleRules.makeValidHandle("---alice") == "alice")
    #expect(HandleRules.makeValidHandle("alice blue") == "aliceblue")
    // Truncated to 20 characters before the other rules apply.
    #expect(HandleRules.makeValidHandle(String(repeating: "a", count: 30)).count == 20)
  }

  /// `isInvalidHandle` recognizes the appview sentinel.
  @Test func isInvalidHandle() {
    #expect(HandleRules.isInvalidHandle("handle.invalid"))
    #expect(!HandleRules.isInvalidHandle("alice.example.com"))
  }

  /// `validateServiceHandle`'s per-field checks.
  @Test func validateServiceHandle() {
    let ok = HandleRules.validateServiceHandle("alice", userDomain: "bsky.social")
    #expect(ok.handleChars)
    #expect(ok.hyphenStartOrEnd)
    #expect(ok.frontLengthNotTooShort)
    #expect(ok.frontLengthNotTooLong)
    #expect(ok.totalLength)
    #expect(ok.overall)
    #expect(!ok.isInvalid)
  }

  /// A name containing a dot fails the character rule.
  @Test func nameWithDotRejected() {
    let validation = HandleRules.validateServiceHandle("alice.blue", userDomain: "bsky.social")
    #expect(!validation.handleChars)
    #expect(validation.isInvalid)
  }

  /// A leading or trailing hyphen fails the hyphen rule.
  @Test func hyphenAtEdgeRejected() {
    #expect(!HandleRules.validateServiceHandle("-alice", userDomain: "bsky.social")
      .hyphenStartOrEnd)
    #expect(!HandleRules.validateServiceHandle("alice-", userDomain: "bsky.social")
      .hyphenStartOrEnd)
    // An interior hyphen is fine.
    #expect(HandleRules.validateServiceHandle("al-ice", userDomain: "bsky.social")
      .hyphenStartOrEnd)
  }

  /// A name shorter than 3 characters fails the short check.
  @Test func shortNameRejected() {
    #expect(!HandleRules.validateServiceHandle("ab", userDomain: "bsky.social")
      .frontLengthNotTooShort)
    #expect(HandleRules.validateServiceHandle("abc", userDomain: "bsky.social")
      .frontLengthNotTooShort)
  }

  /// A name longer than 18 characters fails the long check.
  @Test func longNameRejected() {
    #expect(!HandleRules.validateServiceHandle(
      String(repeating: "a", count: 19), userDomain: "bsky.social").frontLengthNotTooLong)
    #expect(HandleRules.validateServiceHandle(
      String(repeating: "a", count: 18), userDomain: "bsky.social").frontLengthNotTooLong)
  }

  /// An empty name is allowed by the character rule (RN short-circuits on `!str`).
  @Test func emptyNameCharacterRule() {
    #expect(HandleRules.validateServiceHandle("", userDomain: "bsky.social").handleChars)
    // But it still fails the length rule.
    #expect(!HandleRules.validateServiceHandle("", userDomain: "bsky.social").overall)
  }

  /// `isInvalid` uses only the three checks RN uses for the field state.
  @Test func invalidUsesThreeChecks() {
    // A too-short name is `overall`-invalid but not field-invalid, exactly as
    // RN treats it.
    let short = HandleRules.validateServiceHandle("ab", userDomain: "bsky.social")
    #expect(!short.overall)
    #expect(!short.isInvalid)
  }
}

/// The change-handle flow, ported from `ChangeHandleDialog.tsx`.
@Suite struct ChangeHandleFlowTests {

  /// The dialog starts on the provided-handle page.
  @Test func initialState() {
    let state = ChangeHandleState()
    #expect(state.page == .providedHandle)
    #expect(state.subdomain.isEmpty)
    #expect(state.domain.isEmpty)
    #expect(state.verificationMethod == .dns)
    #expect(state.verification == nil)
    #expect(!state.isSubmitting)
    #expect(!state.didSucceed)
  }

  /// Switching pages clears the verification result.
  @Test func pageSwitchResetsVerification() {
    let flow = ChangeHandleFlow(
      handles: FakeHandleService(), availability: FakeHandleAvailability())
    flow.setPage(.ownHandle)
    #expect(flow.state.page == .ownHandle)
    flow.setPage(.providedHandle)
    #expect(flow.state.page == .providedHandle)
    #expect(flow.state.verification == nil)
  }

  /// Typing a domain resets the verification result, as RN's `resetVerification`
  /// does on every `onChangeText`.
  @Test func typingDomainResetsVerification() async {
    let handles = FakeHandleService()
    handles.setResolution("alice.com", did: "did:plc:testaccount")
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    flow.setPage(.ownHandle)
    flow.setDomain("alice.com")
    _ = await flow.verifyDomain(expectedDID: "did:plc:testaccount")
    #expect(flow.state.verification == .verified)

    flow.setDomain("alice.co")
    #expect(flow.state.verification == nil)
  }

  /// A service-handle submission writes the assembled full handle.
  @Test func submitServiceHandle() async {
    let handles = FakeHandleService()
    let availability = FakeHandleAvailability()
    let flow = ChangeHandleFlow(handles: handles, availability: availability)

    flow.setSubdomain("alice")
    let result = await flow.submitServiceHandle(
      host: "bsky.social", availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(handles.updatedHandles == ["alice.bsky.social"])
    #expect(availability.checks.count == 1)
    #expect(availability.checks[0].handle == "alice.bsky.social")
    #expect(availability.checks[0].serviceDID == SettingsConstants.blueskyServiceDID)
    #expect(flow.state.didSucceed)
    #expect(flow.state.currentHandle == "alice.bsky.social")
  }

  /// A taken handle fails before the update call.
  @Test func submitServiceHandleTaken() async {
    let handles = FakeHandleService()
    let availability = FakeHandleAvailability()
    availability.setResult(.unavailable(suggestions: ["alice2"]))
    let flow = ChangeHandleFlow(handles: handles, availability: availability)

    flow.setSubdomain("alice")
    let result = await flow.submitServiceHandle(
      host: "bsky.social", availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == ChangeHandleStrings.handleTaken)
    // The update never ran.
    #expect(handles.updatedHandles.isEmpty)
  }

  /// An invalid subdomain fails without touching the network.
  @Test func submitServiceHandleInvalidWithoutNetwork() async {
    let handles = FakeHandleService()
    let availability = FakeHandleAvailability()
    let flow = ChangeHandleFlow(handles: handles, availability: availability)

    flow.setSubdomain("alice.blue")
    let result = await flow.submitServiceHandle(
      host: "bsky.social", availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == ChangeHandleStrings.invalidHandle)
    #expect(availability.checks.isEmpty)
    #expect(handles.updatedHandles.isEmpty)
  }

  /// A too-short subdomain also fails locally.
  @Test func submitServiceHandleTooShortWithoutNetwork() async {
    let handles = FakeHandleService()
    let availability = FakeHandleAvailability()
    let flow = ChangeHandleFlow(handles: handles, availability: availability)

    flow.setSubdomain("ab")
    let result = await flow.submitServiceHandle(
      host: "bsky.social", availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .failure = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(availability.checks.isEmpty)
  }

  /// An availability-check failure does not block the submission; the update's
  /// own error path owns the failure, matching RN's silent typeahead.
  @Test func availabilityFailureDoesNotBlock() async {
    let handles = FakeHandleService()
    let availability = FakeHandleAvailability()
    availability.setError(XrpcError(rawCode: nil, message: "offline", status: -1))
    let flow = ChangeHandleFlow(handles: handles, availability: availability)

    flow.setSubdomain("alice")
    let result = await flow.submitServiceHandle(
      host: "bsky.social", availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(handles.updatedHandles == ["alice.bsky.social"])
  }

  /// A PDS rejection is mapped through the known-message table.
  @Test func submitMapsUpdateError() async {
    let handles = FakeHandleService()
    handles.setUpdateError(
      XrpcError(rawCode: nil, message: "Handle already taken: alice.bsky.social", status: 400))
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    flow.setSubdomain("alice")
    let result = await flow.submitServiceHandle(
      host: "bsky.social", availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == ChangeHandleStrings.handleTaken)
    #expect(flow.state.error == ChangeHandleStrings.handleTaken)
    #expect(!flow.state.isSubmitting)
    #expect(!flow.state.didSucceed)
  }

  /// Domain verification succeeds when the resolved DID matches.
  @Test func verifyDomainMatches() async {
    let handles = FakeHandleService()
    handles.setResolution("alice.com", did: "did:plc:testaccount")
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    flow.setDomain("alice.com")
    let outcome = await flow.verifyDomain(expectedDID: "did:plc:testaccount")

    #expect(outcome == .verified)
    #expect(flow.state.verification == .verified)
    #expect(handles.resolvedHandles == ["alice.com"])
  }

  /// A resolved DID that is not the account's is a mismatch, carrying the
  /// received DID so the screen can show it.
  @Test func verifyDomainMismatch() async {
    let handles = FakeHandleService()
    handles.setResolution("alice.com", did: "did:plc:someoneelse")
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    flow.setDomain("alice.com")
    let outcome = await flow.verifyDomain(expectedDID: "did:plc:testaccount")

    #expect(outcome == .didMismatch(received: "did:plc:someoneelse"))
  }

  /// An unresolvable domain reports `unresolved`.
  @Test func verifyDomainUnresolved() async {
    let handles = FakeHandleService()
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    flow.setDomain("not-a-domain.test")
    let outcome = await flow.verifyDomain(expectedDID: "did:plc:testaccount")

    #expect(outcome == .unresolved)
    #expect(flow.state.verification == .unresolved)
  }

  /// An empty domain is not verified and the resolve call is skipped.
  @Test func verifyDomainEmpty() async {
    let handles = FakeHandleService()
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    let outcome = await flow.verifyDomain(expectedDID: "did:plc:testaccount")
    #expect(outcome == .unresolved)
    #expect(handles.resolvedHandles.isEmpty)
  }

  /// Submitting a verified domain writes it verbatim, without the provider
  /// domain suffix.
  @Test func submitVerifiedDomain() async {
    let handles = FakeHandleService()
    handles.setResolution("alice.com", did: "did:plc:testaccount")
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    flow.setPage(.ownHandle)
    flow.setDomain("alice.com")
    _ = await flow.verifyDomain(expectedDID: "did:plc:testaccount")
    let result = await flow.submitVerifiedDomain(
      availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(handles.updatedHandles == ["alice.com"])
  }

  /// Submitting an unverified domain is refused, matching RN's disabled button.
  @Test func submitUnverifiedDomainRefused() async {
    let handles = FakeHandleService()
    let flow = ChangeHandleFlow(handles: handles, availability: FakeHandleAvailability())

    flow.setPage(.ownHandle)
    flow.setDomain("alice.com")
    let result = await flow.submitVerifiedDomain(
      availabilityServiceDID: SettingsConstants.blueskyServiceDID)

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == ChangeHandleStrings.failedToVerify)
    #expect(handles.updatedHandles.isEmpty)
  }

  /// A `.bsky.social` current handle is flagged as staying reserved, which is
  /// what the screen's notice is keyed on.
  @Test func currentHandleStaysReserved() {
    var state = ChangeHandleState()
    state.currentHandle = "alice.bsky.social"
    #expect(state.currentHandleStaysReserved)

    state.currentHandle = "alice.com"
    #expect(!state.currentHandleStaysReserved)

    state.currentHandle = nil
    #expect(!state.currentHandleStaysReserved)
  }

  /// The account context setter records the fields the notices read.
  @Test func accountContext() {
    let flow = ChangeHandleFlow(
      handles: FakeHandleService(), availability: FakeHandleAvailability())
    flow.setAccountContext(currentHandle: "alice.bsky.social", isVerified: true)
    #expect(flow.state.currentHandle == "alice.bsky.social")
    #expect(flow.state.isVerifiedAccount)
    #expect(flow.state.currentHandleStaysReserved)
  }

  /// Observers see each state change.
  @Test func listenerNotified() {
    let flow = ChangeHandleFlow(
      handles: FakeHandleService(), availability: FakeHandleAvailability())
    let counter = Counter()
    flow.addListener { _ in counter.increment() }
    flow.setSubdomain("alice")
    flow.setSubdomain("alice2")
    #expect(counter.value == 2)
  }

  /// The error mapping table, one case per known server message.
  @Test func errorMapping() {
    func mapped(_ message: String) -> String {
      ChangeHandleErrors.map(XrpcError(rawCode: nil, message: message, status: 400)).message
    }
    #expect(mapped("Handle already taken") == ChangeHandleStrings.handleTaken)
    #expect(mapped("Handle already taken: x.y") == ChangeHandleStrings.handleTaken)
    #expect(mapped("Reserved handle") == ChangeHandleStrings.handleReserved)
    #expect(mapped("Handle too long") == ChangeHandleStrings.handleTooLong)
    #expect(
      mapped("Input/handle must be a valid handle") == ChangeHandleStrings.invalidHandle)
    #expect(mapped("Rate Limit Exceeded") == ChangeHandleStrings.rateLimitExceeded)
    #expect(mapped("something else") == ChangeHandleStrings.failedToChange)
  }
}

/// A small thread-safe counter for the listener tests.
final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}
