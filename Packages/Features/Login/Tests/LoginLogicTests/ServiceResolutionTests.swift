import ATProtoClient
import Foundation
import Testing

@testable import LoginLogic

/// Service-address normalization, ported from
/// `components/dialogs/ServerInput.tsx`.
@Suite struct ServiceNormalizationTests {

  @Test(arguments: [
    ("bsky.social", "https://bsky.social/"),
    ("BSKY.SOCIAL", "https://bsky.social/"),
    ("  bsky.social  ", "https://bsky.social/"),
    ("https://bsky.social", "https://bsky.social/"),
    ("http://pds.example.com", "http://pds.example.com/"),
    ("pds.example.com/", "https://pds.example.com/"),
    ("localhost", "http://localhost/"),
    ("localhost:3000", "http://localhost:3000/"),
    ("127.0.0.1:8080", "https://127.0.0.1:8080/"),
    ("https://pds.example.com/base", "https://pds.example.com/base"),
  ])
  func normalizationTable(raw: String, expected: String) {
    #expect(ServiceURL.normalize(raw) == expected)
  }

  @Test(arguments: ["", "   ", "https://", "not a url", "://nope"])
  func unusableAddressesAreRejected(raw: String) {
    #expect(ServiceURL.normalize(raw) == nil)
  }

  @Test(arguments: ["", "  "])
  func emptyAddressIsReportedAsEmpty(raw: String) {
    #expect(ServiceURL.validate(raw) == .empty)
    #expect(ServiceURL.normalize(raw) == nil)
  }

  @Test(arguments: ["https://", "not a url"])
  func malformedAddressIsReportedAsInvalid(raw: String) {
    #expect(ServiceURL.validate(raw) == .invalid)
  }

  @Test func aBareHostValidatesToItsNormalizedForm() {
    #expect(ServiceURL.validate("pds.example.com") == .valid("https://pds.example.com/"))
  }

  /// The request base drops the trailing slash the stored form keeps, so that
  /// `XrpcClient`'s `baseURL + "/xrpc/" + method` join produces a single slash.
  @Test(arguments: [
    ("bsky.social", "https://bsky.social"),
    ("https://bsky.social", "https://bsky.social"),
    ("localhost:3000", "http://localhost:3000"),
    ("https://pds.example.com/base", "https://pds.example.com/base"),
  ])
  func requestBaseDropsTheTrailingSlash(raw: String, expected: String) {
    #expect(ServiceURL.requestBase(raw) == expected)
  }

  @Test func requestURLsNeverContainADoubleSlash() {
    let base = ServiceURL.requestBase("bsky.social")
    let url = XrpcClient(baseURL: base, transport: ScriptedTransport())
      .url(method: "com.atproto.server.createSession")
    #expect(url == "https://bsky.social/xrpc/com.atproto.server.createSession")
    #expect(!url.contains("//xrpc"))
  }

  @Test(arguments: [
    "https://bsky.social",
    "https://bsky.social/",
    "https://shimeji.us-west.host.bsky.network",
    "https://example.host.bsky.network",
  ])
  func blueskyHostedAddressesAreRecognised(url: String) {
    #expect(ServiceURL.isBlueskyHosted(url))
  }

  @Test(arguments: [
    "https://pds.example.com",
    "https://bsky.network",
    "https://notbsky.social.evil.com",
  ])
  func nonBlueskyAddressesAreNotRecognised(url: String) {
    #expect(!ServiceURL.isBlueskyHosted(url))
  }
}

/// Identifier normalization and the `createSession` identifier rule, ported
/// from `pds-detection.ts` and `LoginForm.tsx`.
@Suite struct IdentifierNormalizationTests {

  @Test(arguments: [
    ("Alice.Example.com", "alice.example.com"),
    ("  @alice.example.com  ", "alice.example.com"),
    ("@Alice.Example.com", "alice.example.com"),
    ("alice@example.com", "alice@example.com"),
    ("", ""),
  ])
  func normalizationTable(raw: String, expected: String) {
    #expect(LoginIdentifier.normalize(raw) == expected)
  }

  @Test func aLeadingAtIsStrippedSoHandlesDoNotLookLikeEmails() {
    #expect(LoginIdentifier.normalize("@alice.example.com") == "alice.example.com")
    #expect(!LoginIdentifier.isEmail("@alice.example.com"))
    // A real email keeps its interior `@` and still classifies as one.
    #expect(LoginIdentifier.isEmail("alice@example.com"))
  }

  @Test(arguments: [
    ("alice.example.com", true),
    ("did:plc:abc123", true),
    ("alice", false),
    ("", false),
    ("alice@example.com", false),
  ])
  func plausibleHandleTable(identifier: String, expected: Bool) {
    #expect(LoginIdentifier.isPlausibleHandle(identifier) == expected)
  }

  /// The `createFullHandle` branch in `LoginForm.tsx`: a bare username on a
  /// server that advertises handle domains gets the first one appended.
  @Test func aBareUsernameGetsTheFirstAdvertisedDomain() {
    #expect(
      LoginIdentifier.fullIdentifier(
        identifier: "alice", serviceProviderDomains: ["example.com", "other.com"])
        == "alice.example.com")
  }

  @Test func anIdentifierAlreadyEndingInAnAdvertisedDomainIsLeftAlone() {
    #expect(
      LoginIdentifier.fullIdentifier(
        identifier: "alice.example.com", serviceProviderDomains: ["example.com"])
        == "alice.example.com")
  }

  @Test func aQualifiedHandleIsNeverRewrittenForAnotherServiceDomain() {
    #expect(
      LoginIdentifier.fullIdentifier(
        identifier: "hailey.at", serviceProviderDomains: [".bsky.social"])
        == "hailey.at")
  }

  @Test func anEmailIsNeverCompletedWithADomain() {
    #expect(
      LoginIdentifier.fullIdentifier(
        identifier: "alice@example.com", serviceProviderDomains: ["example.com"])
        == "alice@example.com")
  }

  @Test func aDidIsNeverCompletedWithADomain() {
    #expect(
      LoginIdentifier.fullIdentifier(
        identifier: "did:plc:abc", serviceProviderDomains: ["example.com"])
        == "did:plc:abc")
  }

  @Test func withNoAdvertisedDomainsTheIdentifierIsUnchanged() {
    #expect(
      LoginIdentifier.fullIdentifier(identifier: "alice", serviceProviderDomains: [])
        == "alice")
    #expect(
      LoginIdentifier.fullIdentifier(identifier: "alice", serviceProviderDomains: [""])
        == "alice")
  }
}

/// The `describeServer` preflight and its actionable failures.
@Suite struct ServiceResolutionTests {

  @Test func describeServerReturnsTheDomainsAndDid() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.describeServer(domains: ["example.com"], did: "did:web:example.com"))
    let description = try await ServiceResolver.describe(
      service: "bsky.social", transport: transport)
    #expect(description == ServiceDescription(
      availableUserDomains: ["example.com"], did: "did:web:example.com"))
    #expect(
      transport.lastRequest?.url == "https://bsky.social/xrpc/com.atproto.server.describeServer")
    // Pre-auth calls carry no Authorization header.
    #expect(transport.lastRequest?.headers["Authorization"] == nil)
  }

  @Test func aDeadHostIsReportedAsUnreachable() async {
    let transport = ScriptedTransport.failing(with: makeNetworkError())
    await #expect(throws: ServiceResolutionError.unreachable(underlying: XRPCErrorShapes.shape(fromXrpc: makeNetworkError()))) {
      _ = try await ServiceResolver.describe(service: "bsky.social", transport: transport)
    }
  }

  @Test func aHostThatIsNotAPdsIsReportedAsSuch() async {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["detail": "Not Found"], status: 404))
    let error = await #expect(throws: ServiceResolutionError.self) {
      _ = try await ServiceResolver.describe(service: "example.com", transport: transport)
    }
    guard case .notAPDS = error else {
      Issue.record("expected .notAPDS, got \(String(describing: error))")
      return
    }
  }

  @Test func anUnexpectedServerFailureIsReportedAsFailed() async {
    let transport = ScriptedTransport(
      ScriptedTransport.xrpcError("InternalServerError", message: "boom", status: 500))
    let error = await #expect(throws: ServiceResolutionError.self) {
      _ = try await ServiceResolver.describe(service: "example.com", transport: transport)
    }
    guard case .failed(let underlying) = error else {
      Issue.record("expected .failed, got \(String(describing: error))")
      return
    }
    #expect(underlying?.error == "InternalServerError")
  }

  @Test func anUnparseableAddressNeverReachesTheNetwork() async {
    let transport = ScriptedTransport()
    await #expect(throws: ServiceResolutionError.invalidURL) {
      _ = try await ServiceResolver.describe(service: "   ", transport: transport)
    }
    #expect(transport.received.isEmpty)
  }

  @Test func resolutionCanSkipThePreflight() async throws {
    let transport = ScriptedTransport()
    let resolved = try await ServiceResolver.resolve(
      service: "pds.example.com", transport: transport, requireDescription: false)
    #expect(resolved.service == "https://pds.example.com/")
    #expect(resolved.description == nil)
    #expect(transport.received.isEmpty)
  }

  @Test func everyFailureHasUserFacingCopy() {
    let cases: [ServiceResolutionError] = [
      .invalidURL,
      .notAPDS(underlying: nil),
      .unreachable(underlying: XRPCErrorShapes.shape(fromXrpc: makeNetworkError())),
      .failed(underlying: nil),
    ]
    for error in cases {
      #expect(!error.message.isEmpty)
    }
  }

  @Test func selectingACustomServiceDescribesThenAdoptsIt() async {
    let transport = ScriptedTransport(
      ScriptedTransport.describeServer(domains: ["example.com"], did: "did:web:example.com"))
    let flow = LoginFlow(transport: transport)

    let result = await flow.selectCustomService("pds.example.com")
    guard case .success(let resolved) = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(resolved.service == "https://pds.example.com/")
    #expect(flow.state.service == "https://pds.example.com/")
    #expect(flow.state.serviceOverride == "https://pds.example.com/")
    #expect(flow.state.serviceDescription?.did == "did:web:example.com")
  }

  @Test func selectingAnUnreachableCustomServiceReportsAndKeepsTheAddress() async {
    let transport = ScriptedTransport.failing(with: makeNetworkError())
    let flow = LoginFlow(transport: transport)

    let result = await flow.selectCustomService("pds.example.com")
    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error == .unreachable(underlying: XRPCErrorShapes.shape(fromXrpc: makeNetworkError())))
    // The typed address is retained so the user can see and correct it.
    #expect(flow.state.service == "https://pds.example.com/")
    #expect(flow.state.serviceDescription == nil)
  }

  @Test func anEmptyCustomAddressIsRejectedWithoutTheNetwork() async {
    let transport = ScriptedTransport()
    let flow = LoginFlow(transport: transport)
    let result = await flow.selectCustomService("   ")
    #expect(result == .failure(.invalidURL))
    #expect(transport.received.isEmpty)
    // Nothing was adopted.
    #expect(flow.state.serviceOverride == nil)
  }

  @Test func refreshingTheDescriptionAdoptsTheAdvertisedDomains() async {
    let transport = ScriptedTransport.sticky(
      ScriptedTransport.describeServer(domains: ["example.com"], did: "did:web:example.com"))
    let flow = LoginFlow(transport: transport)
    let description = await flow.refreshServiceDescription()
    #expect(description?.availableUserDomains == ["example.com"])
    #expect(flow.state.availableUserDomains == ["example.com"])
  }

  @Test func aFailedDescriptionRefreshClearsTheAdvertisedDomains() async {
    let transport = ScriptedTransport()
    let flow = LoginFlow(transport: transport)
    let description = await flow.refreshServiceDescription()
    #expect(description == nil)
    #expect(flow.state.serviceDescription == nil)
  }
}

/// Hosting-provider detection, ported from `useHostingProvider`.
@Suite struct ServiceSelectionTests {

  @Test func anEmailSelectsTheDefaultService() {
    let selection = ServiceSelection(identifier: "alice@example.com")
    #expect(selection.state == .email)
    #expect(selection.service == LoginConstants.defaultService)
  }

  @Test func aBareUsernameIsIdleAndUsesTheDefaultService() {
    let selection = ServiceSelection(identifier: "alice")
    #expect(selection.state == .idle)
    #expect(selection.service == LoginConstants.defaultService)
  }

  @Test func anUnsettledDebounceReportsDetectingNotTheStaleResult() {
    let selection = ServiceSelection(
      identifier: "alice.example.com",
      isDebounceSettled: false,
      lookup: .resolved(did: "did:plc:alice", pdsUrl: "https://pds.example.com"))
    #expect(selection.state == .detecting)
    #expect(selection.service == LoginConstants.defaultService)
  }

  @Test func aResolvedHandleSelectsItsPds() {
    let selection = ServiceSelection(
      identifier: "alice.example.com",
      lookup: .resolved(did: "did:plc:alice", pdsUrl: "https://pds.example.com"))
    #expect(selection.state == .detected(pdsUrl: "https://pds.example.com"))
    #expect(selection.service == "https://pds.example.com")
  }

  @Test func aResolvedDidWithNoPdsEndpointIsUnresolved() {
    let selection = ServiceSelection(
      identifier: "alice.example.com",
      lookup: .resolved(did: "did:plc:alice", pdsUrl: nil))
    #expect(selection.state == .unresolved)
    #expect(selection.service == LoginConstants.defaultService)
  }

  @Test func aNetworkFailureIsAnErrorNotAnUnresolvedHandle() {
    let selection = ServiceSelection(
      identifier: "alice.example.com", lookup: .failed(isNetwork: true))
    #expect(selection.state == .error)
  }

  @Test func anUnknownHandleIsUnresolved() {
    let selection = ServiceSelection(
      identifier: "alice.example.com", lookup: .failed(isNetwork: false))
    #expect(selection.state == .unresolved)
  }

  @Test func anOverrideBypassesDetectionEntirely() {
    let selection = ServiceSelection(
      identifier: "alice.example.com",
      override: "https://pds.example.com",
      lookup: .failed(isNetwork: true))
    #expect(selection.state == .overridden(pdsUrl: "https://pds.example.com"))
    #expect(selection.service == "https://pds.example.com")
  }

  @Test func resolvingAnOverrideNeverLooksUpTheHandle() async throws {
    let selection = ServiceSelection(
      identifier: "alice.example.com", override: "https://pds.example.com")
    let resolution = try await selection.resolveService(
      identifier: "alice.example.com") { _ in
        Issue.record("the lookup must not run when an override is set")
        return nil
      }
    #expect(resolution == ServiceResolution(service: "https://pds.example.com", did: nil))
  }

  @Test func resolvingAnEmailSkipsTheLookup() async throws {
    let selection = ServiceSelection(identifier: "alice@example.com")
    let resolution = try await selection.resolveService(identifier: "alice@example.com") { _ in
      Issue.record("the lookup must not run for an email")
      return nil
    }
    #expect(resolution == ServiceResolution(
      service: LoginConstants.defaultService, did: nil))
  }

  @Test func resolvingAPlausibleHandleUsesTheLookupResult() async throws {
    let selection = ServiceSelection(identifier: "alice.example.com")
    let resolution = try await selection.resolveService(
      identifier: "alice.example.com"
    ) { handle in
      #expect(handle == "alice.example.com")
      return ResolvedPDSEndpoint(did: "did:plc:alice", pdsUrl: "https://pds.example.com")
    }
    #expect(resolution == ServiceResolution(
      service: "https://pds.example.com", did: "did:plc:alice"))
  }

  @Test func anUnresolvableHandleFallsBackToTheDefaultServiceButKeepsTheDid() async throws {
    let selection = ServiceSelection(identifier: "alice.example.com")
    let resolution = try await selection.resolveService(
      identifier: "alice.example.com"
    ) { _ in ResolvedPDSEndpoint(did: "did:plc:alice", pdsUrl: nil) }
    #expect(resolution == ServiceResolution(
      service: LoginConstants.defaultService, did: "did:plc:alice"))
  }

  @Test func aNetworkErrorDuringResolutionPropagates() async {
    let selection = ServiceSelection(identifier: "alice.example.com")
    await #expect(throws: XrpcError.self) {
      _ = try await selection.resolveService(identifier: "alice.example.com") { _ in
        throw makeNetworkError()
      }
    }
  }

  @Test func signInUsesTheLookedUpServiceAndFailsOnANetworkError() async {
    // A network error during resolution must fail the attempt rather than
    // silently sending the password to the default service.
    let transport = ScriptedTransport()
    let flow = LoginFlow(
      transport: transport,
      lookupHandle: { _ in throw makeNetworkError() })
    let outcome = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    #expect(outcome == .failure(LoginError.networkOffline(
      underlying: XRPCErrorShapes.shape(fromXrpc: makeNetworkError()))))
    #expect(transport.received.isEmpty)
  }

  @Test func signInTargetsTheLookedUpPds() async {
    let transport = ScriptedTransport(ScriptedTransport.createSession())
    let flow = LoginFlow(
      transport: transport,
      lookupHandle: { _ in
        ResolvedPDSEndpoint(did: "did:plc:alice", pdsUrl: "https://pds.example.com")
      })
    _ = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    #expect(
      transport.lastRequest?.url
        == "https://pds.example.com/xrpc/com.atproto.server.createSession")
  }

  @Test func theHostingProviderConfirmationRule() {
    // A non-Bluesky, auto-detected host needs confirmation.
    #expect(
      LoginFlow.requiresHostingProviderConfirmation(
        service: "https://pds.example.com", override: nil, did: "did:plc:alice",
        knownDIDs: []))
    // A manual choice is explicit consent.
    #expect(
      !LoginFlow.requiresHostingProviderConfirmation(
        service: "https://pds.example.com", override: "https://pds.example.com",
        did: nil, knownDIDs: []))
    // A Bluesky host is trusted.
    #expect(
      !LoginFlow.requiresHostingProviderConfirmation(
        service: "https://bsky.social", override: nil, did: "did:plc:alice",
        knownDIDs: []))
    // A DID already signed in on this device is trusted.
    #expect(
      !LoginFlow.requiresHostingProviderConfirmation(
        service: "https://pds.example.com", override: nil, did: "did:plc:alice",
        knownDIDs: ["did:plc:alice"]))
  }

  @Test func niceHostRendering() {
    #expect(
      ServiceSelection(
        identifier: "alice", override: "https://shimeji.us-west.host.bsky.network"
      ).niceHost == "Bluesky")
    #expect(
      ServiceSelection(identifier: "alice", override: "https://pds.example.com").niceHost
        == "pds.example.com")
  }
}
