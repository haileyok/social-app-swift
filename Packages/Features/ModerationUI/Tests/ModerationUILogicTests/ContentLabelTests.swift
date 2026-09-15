import Foundation
import Moderation
import Testing

@testable import ModerationUILogic

/// Port of the row derivation in
/// `src/components/moderation/LabelPreference.tsx` (`LabelerLabelPreference`)
/// and the list construction in `src/screens/Profile/Sections/Labels.tsx`.
@Suite("Content label matrix")
struct ContentLabelTests {

  private func prefs(
    adultContentEnabled: Bool = false,
    labels: [String: LabelPreference] = [:],
    labelers: [LabelerPrefs] = []
  ) -> ModerationPrefs {
    ModerationPrefs(
      adultContentEnabled: adultContentEnabled, labels: labels, labelers: labelers)
  }

  private func definition(
    _ identifier: String, severity: LabelSeverity = .none, blurs: LabelBlurs = .none,
    defaultSetting: LabelPreference = .warn, flags: [LabelFlag] = [], definedBy: String = "app.bsky"
  ) -> LabelValueDefinition {
    LabelValueDefinition(
      identifier: identifier, severity: severity, blurs: blurs, defaultSetting: defaultSetting,
      flags: flags, behaviors: LabelTargetBehaviors(), definedBy: definedBy)
  }

  // MARK: - Saved-pref lookup

  @Test("a labeler-scoped non-global label reads the labeler's map")
  func labelerScopedLookup() {
    let prefs = prefs(
      labels: ["custom": .hide],
      labelers: [LabelerPrefs(did: "did:plc:l", labels: ["custom": .ignore])])
    #expect(
      ContentLabels.savedPreference(
        identifier: "custom", labelerDid: "did:plc:l", isGlobalLabel: false, prefs: prefs)
        == .ignore)
  }

  @Test("a global label reads the global map even when scoped to a labeler")
  func globalLookupIgnoresLabelerScope() {
    let prefs = prefs(
      labels: ["porn": .warn],
      labelers: [LabelerPrefs(did: "did:plc:l", labels: ["porn": .ignore])])
    #expect(
      ContentLabels.savedPreference(
        identifier: "porn", labelerDid: "did:plc:l", isGlobalLabel: true, prefs: prefs)
        == .warn)
  }

  @Test("an unscoped label reads the global map")
  func unscopedLookup() {
    let prefs = prefs(labels: ["nudity": .hide])
    #expect(
      ContentLabels.savedPreference(
        identifier: "nudity", labelerDid: nil, isGlobalLabel: false, prefs: prefs) == .hide)
  }

  @Test("an unset label has no saved preference")
  func unsetLookup() {
    #expect(
      ContentLabels.savedPreference(
        identifier: "unset", labelerDid: nil, isGlobalLabel: false, prefs: prefs()) == nil)
  }

  // MARK: - Preference resolution

  @Test("a stored pref wins over the definition default")
  func storedPrefWins() {
    let row = ContentLabels.row(
      definition: definition("custom", defaultSetting: .warn, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l",
      prefs: prefs(labelers: [LabelerPrefs(did: "did:plc:l", labels: ["custom": .hide])]))
    #expect(row.preference == .hide)
    #expect(row.savedPreference == .hide)
  }

  @Test("with no stored pref the definition default applies")
  func defaultApplies() {
    let row = ContentLabels.row(
      definition: definition("custom", defaultSetting: .ignore, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l", prefs: prefs())
    #expect(row.preference == .ignore)
    #expect(row.savedPreference == nil)
  }

  @Test("a warn default is kept when the label can warn")
  func warnDefaultKept() {
    let row = ContentLabels.row(
      definition: definition("custom", severity: .alert, blurs: .media, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l", prefs: prefs())
    #expect(row.preference == .warn)
  }

  // MARK: - canWarn

  @Test("a label that blurs nothing and warns nothing cannot warn")
  func cannotWarnWhenInert() {
    let row = ContentLabels.row(
      definition: definition("inert", severity: .none, blurs: .none, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l", prefs: prefs())
    #expect(!row.canWarn)
    #expect(row.options == [.ignore, .hide])
  }

  @Test("a label that has a severity can warn")
  func canWarnWithSeverity() {
    let row = ContentLabels.row(
      definition: definition("alerting", severity: .alert, blurs: .none, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l", prefs: prefs())
    #expect(row.canWarn)
    #expect(row.options == [.ignore, .warn, .hide])
  }

  @Test("a label that blurs content can warn")
  func canWarnWithBlurs() {
    let row = ContentLabels.row(
      definition: definition("blurring", severity: .none, blurs: .content, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l", prefs: prefs())
    #expect(row.canWarn)
  }

  @Test("a stored warn on an inert label is coerced to ignore")
  func storedWarnCoercedOnInertLabel() {
    let row = ContentLabels.row(
      definition: definition("inert", severity: .none, blurs: .none, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l",
      prefs: prefs(labelers: [LabelerPrefs(did: "did:plc:l", labels: ["inert": .warn])]))
    #expect(row.savedPreference == .warn)
    #expect(row.preference == .ignore)
  }

  @Test("a stored hide on an inert label is untouched")
  func storedHideUntouchedOnInertLabel() {
    let row = ContentLabels.row(
      definition: definition("inert", severity: .none, blurs: .none, definedBy: "did:plc:l"),
      labelerDid: "did:plc:l",
      prefs: prefs(labelers: [LabelerPrefs(did: "did:plc:l", labels: ["inert": .hide])]))
    #expect(row.preference == .hide)
  }

  // MARK: - Adult gating

  @Test("an adult label with adult content off is forced to hide")
  func adultDisabledForcesHide() {
    let row = ContentLabels.row(
      definition: definition("adult-thing", flags: [.adult], definedBy: "did:plc:l"),
      labelerDid: "did:plc:l",
      prefs: prefs(adultContentEnabled: false))
    #expect(row.adultDisabled)
    #expect(row.preference == .hide)
    #expect(!row.configurable)
  }

  @Test("an adult label with adult content off overrides a stored ignore")
  func adultDisabledOverridesStoredIgnore() {
    let row = ContentLabels.row(
      definition: definition("adult-thing", flags: [.adult], definedBy: "did:plc:l"),
      labelerDid: "did:plc:l",
      prefs: prefs(
        adultContentEnabled: false,
        labelers: [LabelerPrefs(did: "did:plc:l", labels: ["adult-thing": .ignore])]))
    #expect(row.savedPreference == .ignore)
    #expect(row.preference == .hide)
  }

  @Test("an adult label is configurable once adult content is on")
  func adultEnabledConfigurable() {
    let row = ContentLabels.row(
      definition: definition("adult-thing", flags: [.adult], definedBy: "did:plc:l"),
      labelerDid: "did:plc:l", prefs: prefs(adultContentEnabled: true))
    #expect(!row.adultDisabled)
    #expect(row.configurable)
  }

  @Test("a non-adult label is unaffected by the adult toggle")
  func nonAdultUnaffected() {
    let row = ContentLabels.row(
      definition: definition("plain", definedBy: "did:plc:l"), labelerDid: "did:plc:l",
      prefs: prefs(adultContentEnabled: false))
    #expect(!row.adultDisabled)
    #expect(row.configurable)
  }

  // MARK: - Global labels

  @Test("a label defined by the app is a global label")
  func globalLabelDetection() {
    let row = ContentLabels.row(
      definition: definition("porn", flags: [.adult]), labelerDid: nil,
      prefs: prefs(adultContentEnabled: true))
    #expect(row.isGlobalLabel)
  }

  @Test("a labeler-defined label is not global")
  func labelerLabelDetection() {
    let row = ContentLabels.row(
      definition: definition("custom", definedBy: "did:plc:l"), labelerDid: "did:plc:l",
      prefs: prefs())
    #expect(!row.isGlobalLabel)
  }

  @Test("a global label is not configurable on a labeler page")
  func globalLabelNotConfigurable() {
    let row = ContentLabels.row(
      definition: definition("porn", flags: [.adult]), labelerDid: "did:plc:l",
      prefs: prefs(adultContentEnabled: true))
    #expect(!row.configurable)
    #expect(row.showsStaticValue)
  }

  @Test("the global rows are porn, sexual, graphic-media, nudity in order")
  func globalRowOrder() {
    let rows = ContentLabels.globalRows(prefs: prefs(adultContentEnabled: true))
    #expect(rows.map(\.identifier) == ["porn", "sexual", "graphic-media", "nudity"])
  }

  @Test("the global label block is hidden while adult content is off")
  func globalRowsGatedOnAdultContent() {
    #expect(!ContentLabels.showsGlobalRows(prefs: prefs(adultContentEnabled: false)))
    #expect(ContentLabels.showsGlobalRows(prefs: prefs(adultContentEnabled: true)))
  }

  // MARK: - Subscription gating

  @Test("an unsubscribed labeler's rows are not configurable")
  func unsubscribedNotConfigurable() {
    let row = ContentLabels.row(
      definition: definition("custom", definedBy: "did:plc:l"), labelerDid: "did:plc:l",
      isSubscribed: false, prefs: prefs())
    #expect(!row.configurable)
  }

  @Test("a subscribed labeler's rows are configurable")
  func subscribedConfigurable() {
    let row = ContentLabels.row(
      definition: definition("custom", definedBy: "did:plc:l"), labelerDid: "did:plc:l",
      isSubscribed: true, prefs: prefs())
    #expect(row.configurable)
  }

  // MARK: - Lookup

  @Test("a custom definition shadows the global table for a non-! value")
  func customShadowsGlobal() {
    let custom = definition("porn", defaultSetting: .ignore, definedBy: "did:plc:l")
    let found = ContentLabels.lookupLabelValueDefinition("porn", customDefinitions: [custom])
    #expect(found?.definedBy == "did:plc:l")
  }

  @Test("a !-prefixed value never looks in the custom set")
  func bangValueSkipsCustom() {
    let custom = definition("!hide", definedBy: "did:plc:l")
    let found = ContentLabels.lookupLabelValueDefinition("!hide", customDefinitions: [custom])
    #expect(found?.definedBy == "app.bsky")
  }

  @Test("an unknown value with no custom definitions is nil")
  func unknownValueNil() {
    #expect(ContentLabels.lookupLabelValueDefinition("nope", customDefinitions: nil) == nil)
  }

  // MARK: - Row list construction

  @Test("rows are built from the declared values, deduped, in order")
  func rowsDedupedAndOrdered() {
    let custom = [
      definition("alpha", definedBy: "did:plc:l"),
      definition("beta", definedBy: "did:plc:l"),
    ]
    let rows = ContentLabels.rows(
      labelerDid: "did:plc:l", labelValues: ["beta", "alpha", "beta"],
      customDefinitions: custom, prefs: prefs())
    #expect(rows.map(\.identifier) == ["beta", "alpha"])
  }

  @Test("a declared value with no definition is skipped")
  func unknownValueSkipped() {
    let rows = ContentLabels.rows(
      labelerDid: "did:plc:l", labelValues: ["ghost"],
      customDefinitions: [], prefs: prefs())
    #expect(rows.isEmpty)
  }

  @Test("a non-configurable definition is skipped")
  func nonConfigurableSkipped() {
    var custom = definition("locked", definedBy: "did:plc:l")
    custom.configurable = false
    let rows = ContentLabels.rows(
      labelerDid: "did:plc:l", labelValues: ["locked"], customDefinitions: [custom],
      prefs: prefs())
    #expect(rows.isEmpty)
  }

  @Test("a declared global label resolves through the global table")
  func declaredGlobalLabelResolves() {
    let rows = ContentLabels.rows(
      labelerDid: "did:plc:l", labelValues: ["porn"], customDefinitions: [], prefs: prefs())
    #expect(rows.map(\.identifier) == ["porn"])
    #expect(rows.first?.isGlobalLabel == true)
  }

  // MARK: - User-facing label filtering

  @Test("system labels are filtered out of user-facing labels")
  func systemLabelsFiltered() {
    let values = [
      Label(src: "did:plc:l", uri: "u", val: "!hide"),
      Label(src: "did:plc:l", uri: "u", val: "porn"),
    ]
    let filtered = ContentLabels.filterUserFacingLabels(values, currentAccountDid: nil)
    #expect(filtered.map(\.val) == ["porn"])
  }

  @Test("the viewer's own bot self-label is filtered out")
  func ownBotLabelFiltered() {
    let values = [
      Label(src: "did:plc:me", uri: "u", val: "bot"),
      Label(src: "did:plc:someone", uri: "u", val: "bot"),
    ]
    let filtered = ContentLabels.filterUserFacingLabels(values, currentAccountDid: "did:plc:me")
    #expect(filtered.map(\.src) == ["did:plc:someone"])
  }

  @Test("a bot label from another labeler shows when logged out")
  func botLabelWithoutAccount() {
    let values = [Label(src: "did:plc:me", uri: "u", val: "bot")]
    #expect(ContentLabels.filterUserFacingLabels(values, currentAccountDid: nil).count == 1)
  }
}
