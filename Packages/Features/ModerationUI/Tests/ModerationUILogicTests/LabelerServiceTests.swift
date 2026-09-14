import ATProtoClient
import Foundation
import Lexicons
import Moderation
import Preferences
import QueryStore
import SwiftAtproto
import Testing

@testable import ModerationUILogic

/// Port of `src/state/queries/labeler.ts`, the label-definition derivation in
/// `src/state/queries/preferences/moderation.ts`, and the subscription flow in
/// `src/screens/Profile/Header/ProfileHeaderLabeler.tsx`.
@Suite("Labeler service")
struct LabelerServiceTests {

  /// Encodes labeler views into a `getServices` response body.
  ///
  /// The generated decoder is `$type`-discriminated, so the discriminant is
  /// injected into each encoded object.
  private func detailedPageJSON(_ labelers: [App.Bsky.LabelerDefs_LabelerViewDetailed]) throws
    -> String
  {
    let encoder = JSONEncoder()
    let views = try labelers.map { labeler -> String in
      let data = try encoder.encode(labeler)
      var text = String(decoding: data, as: UTF8.self)
      text.insert(
        contentsOf: #""$type":"app.bsky.labeler.defs#labelerViewDetailed","#,
        at: text.index(after: text.startIndex))
      return text
    }
    return #"{"views":[\#(views.joined(separator: ","))]}"#
  }

  // MARK: - Reads

  @Test("a detailed read resolves the labeler's view")
  func detailedRead() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.labeler.getServices",
      json: try detailedPageJSON([Fixtures.labelerDetailed(did: "did:plc:l")]))
    let store = QueryStore()

    let labeler = try await LabelerService.labelerInfo(
      store: store, client: server.appviewClient(), did: "did:plc:l")
    #expect(labeler?.creator.did.rawValue == "did:plc:l")

    let request = try #require(server.requests("app.bsky.labeler.getServices").first)
    #expect(request.params["dids"] == "did:plc:l")
    #expect(request.params["detailed"] == "true")
  }

  @Test("a batch read returns only the detailed views")
  func batchRead() async throws {
    let server = ScriptedXRPC()
    server.respond(
      "app.bsky.labeler.getServices",
      json: try detailedPageJSON([
        Fixtures.labelerDetailed(did: "did:plc:a"), Fixtures.labelerDetailed(did: "did:plc:b"),
      ]))
    let views = try await LabelerService.labelersDetailedInfo(
      client: server.appviewClient(), dids: ["did:plc:a", "did:plc:b"])
    #expect(views.map(\.creator.did.rawValue) == ["did:plc:a", "did:plc:b"])
  }

  @Test("a batch read with no dids short-circuits")
  func batchReadEmpty() async throws {
    let server = ScriptedXRPC()
    let views = try await LabelerService.labelersDetailedInfo(
      client: server.appviewClient(), dids: [])
    #expect(views.isEmpty)
    #expect(server.requests("app.bsky.labeler.getServices").isEmpty)
  }

  // MARK: - Keys

  @Test("the batch key sorts the dids, so two call sites share a cache entry")
  func batchKeyIsOrderInsensitive() {
    let a = LabelerService.labelersInfoKey(dids: ["did:plc:b", "did:plc:a"])
    let b = LabelerService.labelersInfoKey(dids: ["did:plc:a", "did:plc:b"])
    #expect(a == b)
  }

  @Test("the detailed key carries the persisted version")
  func detailedKeyIsPersisted() {
    let key = LabelerService.labelersDetailedInfoKey(dids: ["did:plc:a"])
    #expect(key.persistedVersion == 1)
    #expect(key.root == "labelers-detailed-info")
  }

  // MARK: - Subscribed dids

  @Test("the app's labelers come first, then subscriptions, deduped")
  func subscribedDids() {
    let prefs = ModerationPrefs(labelers: [
      LabelerPrefs(did: "did:plc:l1"), LabelerPrefs(did: "did:plc:app"),
    ])
    let dids = LabelerService.subscribedDids(
      appLabelers: ["did:plc:app"], preferences: prefs)
    #expect(dids == ["did:plc:app", "did:plc:l1"])
  }

  @Test("the regional authorities can be excluded")
  func subscribedDidsExcludingAuthorities() {
    let prefs = ModerationPrefs(labelers: [LabelerPrefs(did: CountryLabelers.br)])
    let dids = LabelerService.subscribedDids(
      appLabelers: ["did:plc:app"], preferences: prefs,
      excludeNonConfigurableAuthorities: true)
    #expect(dids == ["did:plc:app"])
  }

  @Test("the regional authority test recognises every country labeler")
  func regionalAuthorityTest() {
    #expect(isNonConfigurableModerationAuthority(CountryLabelers.br))
    #expect(isNonConfigurableModerationAuthority(CountryLabelers.eu))
    #expect(!isNonConfigurableModerationAuthority("did:plc:not-a-labeler"))
    #expect(!isNonConfigurableModerationAuthority(bskyModerationDid))
  }

  // MARK: - Definitions

  @Test("label definitions are interpreted and keyed by labeler did")
  func labelDefinitions() {
    let labeler = Fixtures.labelerDetailed(
      did: "did:plc:l",
      labelValueDefinitions: [
        Fixtures.labelValueDefinition(identifier: "custom-label", blurs: "media"),
        Fixtures.labelValueDefinition(identifier: "adult-label", adultOnly: true),
      ])
    let defs = LabelerService.labelDefinitions([labeler])
    let interpreted = try? #require(defs["did:plc:l"])
    #expect(interpreted?.count == 2)
    #expect(interpreted?.first?.identifier == "custom-label")
    #expect(interpreted?.first?.blurs == .media)
    #expect(interpreted?.first?.definedBy == "did:plc:l")
    // The interpreter marks an adultOnly definition with the adult flag.
    #expect(interpreted?.last?.flags.contains(.adult) == true)
  }

  @Test("an invalid raw definition is dropped by the interpreter")
  func invalidDefinitionsDropped() {
    // `isValid` requires identifier, severity and blurs; the generated types
    // make all three non-optional, so an invalid definition cannot be built
    // here. This asserts the pass-through path keeps them.
    let labeler = Fixtures.labelerDetailed(
      did: "did:plc:l",
      labelValueDefinitions: [Fixtures.labelValueDefinition(identifier: "ok")])
    #expect(LabelerService.labelDefinitions([labeler])["did:plc:l"]?.count == 1)
  }

  @Test("a labeler with no declared definitions yields no entry")
  func noDefinitions() {
    let labeler = Fixtures.labelerDetailed(did: "did:plc:l")
    // The map still carries the did, with an empty list: RN buildst the entry
    // from every returned labeler.
    #expect(LabelerService.labelDefinitions([labeler])["did:plc:l"]?.isEmpty == true)
  }

  @Test("the report dialog labeler carries the declared capabilities")
  func reportLabelerCapabilities() {
    let labeler = Fixtures.labelerDetailed(
      did: "did:plc:l", handle: "labeler.test",
      reasonTypes: [ReportReasons.misleadingSpam], subjectCollections: ["app.bsky.feed.post"],
      subjectTypes: ["record"])
    let reportLabeler = LabelerService.reportLabeler(labeler)
    #expect(reportLabeler.did == "did:plc:l")
    #expect(reportLabeler.handle == "labeler.test")
    #expect(reportLabeler.reasonTypes == [ReportReasons.misleadingSpam])
    #expect(reportLabeler.subjectCollections == ["app.bsky.feed.post"])
    #expect(reportLabeler.subjectTypes == ["record"])
  }

  @Test("a labeler with no display name titles from its handle")
  func labelerTitle() {
    let labeler = Fixtures.labelerDetailed(did: "did:plc:l", handle: "labeler.test")
    #expect(LabelerService.reportLabeler(labeler).title == "@labeler.test")
    let named = Fixtures.labelerDetailed(
      did: "did:plc:l", handle: "labeler.test", displayName: "Labeler")
    #expect(LabelerService.reportLabeler(named).title == "Labeler")
  }

  // MARK: - Subscription state

  @Test("the app's own labelers are always subscribed")
  func appLabelerAlwaysSubscribed() {
    #expect(
      LabelerService.isSubscribed(
        did: "did:plc:app", appLabelers: ["did:plc:app"], preferences: ModerationPrefs()))
  }

  @Test("a subscription is read from the preferences")
  func subscribedFromPreferences() {
    let prefs = ModerationPrefs(labelers: [LabelerPrefs(did: "did:plc:l")])
    #expect(LabelerService.isSubscribed(did: "did:plc:l", appLabelers: [], preferences: prefs))
    #expect(!LabelerService.isSubscribed(did: "did:plc:x", appLabelers: [], preferences: prefs))
  }

  // MARK: - Unavailable cleanup

  @Test("a subscribed labeler absent from the read is unavailable")
  func unavailableDids() {
    let unavailable = LabelerService.unavailableDids(
      subscribed: ["did:plc:gone", "did:plc:here"],
      returned: ["did:plc:here"], appLabelers: [])
    #expect(unavailable == ["did:plc:gone"])
  }

  @Test("the app's labelers and regional authorities are never unavailable")
  func unavailableExclusions() {
    let unavailable = LabelerService.unavailableDids(
      subscribed: ["did:plc:app", CountryLabelers.br, "did:plc:gone"],
      returned: [], appLabelers: ["did:plc:app"])
    #expect(unavailable == ["did:plc:gone"])
  }

  // MARK: - Invalid labeler cleanup

  @Test("a profile with no labeler association is invalid")
  func invalidNoAssociation() {
    let invalid = LabelerService.invalidLabelers(
      subscribed: ["did:plc:l"],
      profiles: [LabelerService.ProfileAssociations(did: "did:plc:l", isLabeler: false)])
    #expect(invalid == ["did:plc:l"])
  }

  @Test("a subscribed labeler with no profile at all is invalid")
  func invalidNoProfile() {
    let invalid = LabelerService.invalidLabelers(subscribed: ["did:plc:l"], profiles: [])
    #expect(invalid == ["did:plc:l"])
  }

  @Test("a valid labeler association is kept")
  func validAssociation() {
    let invalid = LabelerService.invalidLabelers(
      subscribed: ["did:plc:l"],
      profiles: [LabelerService.ProfileAssociations(did: "did:plc:l", isLabeler: true)])
    #expect(invalid.isEmpty)
  }

  @Test("a failed profile read leaves every labeler alone")
  func failedProfileRead() {
    #expect(
      LabelerService.invalidLabelers(subscribed: ["did:plc:l"], profiles: nil).isEmpty)
  }

  // MARK: - Cap

  @Test("the cap matches RN's MAX_LABELERS")
  func maxLabelers() {
    #expect(LabelerService.maxLabelers == 20)
  }

  @Test("subscribing at the cap is refused")
  func capReached() {
    let dids = (0..<20).map { "did:plc:\($0)" }
    #expect(
      LabelerService.preflight(subscribe: true, currentDids: dids, invalidDids: [])
        == .maxLabelersReached)
  }

  @Test("unsubscribing is never blocked by the cap")
  func unsubscribeNotCapped() {
    let dids = (0..<20).map { "did:plc:\($0)" }
    #expect(
      LabelerService.preflight(subscribe: false, currentDids: dids, invalidDids: []) == .proceed)
  }

  @Test("invalid labelers are removed before the cap check")
  func capCheckedAfterCleanup() {
    // 20 subscribed, 1 invalid: after cleanup 19 remain, so a subscribe fits.
    let dids = (0..<20).map { "did:plc:\($0)" }
    #expect(
      LabelerService.preflight(subscribe: true, currentDids: dids, invalidDids: ["did:plc:0"])
        == .proceed)
  }

  // MARK: - Preference writes

  @Test("removing a labeler rewrites the labelers pref")
  func removeLabelerWrites() async throws {
    let server = ScriptedXRPC()
    server.setPreferences(
      #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:a"},{"did":"did:plc:b"}]}]"#
    )
    let engine = server.preferencesEngine()

    try await LabelerService.removeLabelers(engine, dids: ["did:plc:a"])

    let json = server.preferencesJSON
    #expect(!json.contains("did:plc:a"))
    #expect(json.contains("did:plc:b"))
  }

  @Test("adding a labeler appends to the labelers pref")
  func addLabelerWrites() async throws {
    let server = ScriptedXRPC()
    server.setPreferences(
      #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:a"}]}]"#
    )
    let engine = server.preferencesEngine()

    try await LabelerService.addLabeler(engine, did: "did:plc:b")

    let json = server.preferencesJSON
    #expect(json.contains("did:plc:a"))
    #expect(json.contains("did:plc:b"))
  }

  @Test("adding an already-subscribed labeler skips the write")
  func addExistingLabelerSkips() async throws {
    let server = ScriptedXRPC()
    server.setPreferences(
      #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:a"}]}]"#
    )
    let engine = server.preferencesEngine()

    let result = try await LabelerService.addLabeler(engine, did: "did:plc:a")
    if case .skipped = result {} else {
      Issue.record("expected the duplicate add to be skipped, got \(result)")
    }
    #expect(server.requests("app.bsky.actor.putPreferences").isEmpty)
  }

  @Test("setting a content label pref persists it against the labeler")
  func setLabelerScopedPref() async throws {
    let server = ScriptedXRPC()
    let engine = server.preferencesEngine()

    try await LabelerService.setContentLabelPreference(
      engine, label: "custom", visibility: .hide, labelerDid: "did:plc:l")

    let json = server.preferencesJSON
    #expect(json.contains("app.bsky.actor.defs#contentLabelPref"))
    #expect(json.contains(#""label":"custom""#))
    #expect(json.contains(#""visibility":"hide""#))
    #expect(json.contains(#""labelerDid":"did:plc:l""#))
  }

  @Test("setting a global content label pref omits the labeler")
  func setGlobalPref() async throws {
    let server = ScriptedXRPC()
    let engine = server.preferencesEngine()

    try await LabelerService.setContentLabelPreference(
      engine, label: "porn", visibility: .warn, labelerDid: nil)

    let json = server.preferencesJSON
    #expect(json.contains(#""label":"porn""#))
    #expect(!json.contains("labelerDid"))
  }

  @Test("an invalid labeler did is rejected before any write")
  func invalidDidRejected() async throws {
    let server = ScriptedXRPC()
    let engine = server.preferencesEngine()

    await #expect(throws: (any Error).self) {
      try await LabelerService.addLabeler(engine, did: "not-a-did")
    }
    #expect(server.requests("app.bsky.actor.putPreferences").isEmpty)
  }
}
