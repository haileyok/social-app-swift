import Foundation
import Testing

import ATProtoClient
import Moderation
import Preferences

@testable import SettingsLogic

/// The following-feed toggle model, ported from
/// `screens/Settings/FollowingFeedPreferences.tsx`.
@Suite struct FollowingFeedPreferencesTests {

  /// The defaults are RN's `DEFAULT_HOME_FEED_PREFS` with the hide fields
  /// inverted into show semantics.
  @Test func defaults() {
    let prefs = FollowingFeedPreferences.default
    #expect(prefs.showReplies)
    #expect(prefs.showReposts)
    #expect(prefs.showQuotePosts)
    #expect(!prefs.mergeFeedEnabled)
  }

  /// The show-semantics model inverts the stored `hide*` fields.
  @Test func fromStored() {
    let stored = FeedViewPreference(
      feed: "home", hideReplies: true, hideReposts: false, hideQuotePosts: true,
      lab_mergeFeedEnabled: true)
    let prefs = FollowingFeedPreferences(from: stored)
    #expect(!prefs.showReplies)
    #expect(prefs.showReposts)
    #expect(!prefs.showQuotePosts)
    #expect(prefs.mergeFeedEnabled)
  }

  /// An absent `lab_mergeFeedEnabled` reads as false, matching RN's `Boolean(...)`.
  @Test func storedAbsentMergeFlag() {
    let prefs = FollowingFeedPreferences(
      from: FeedViewPreference(feed: "home", lab_mergeFeedEnabled: nil))
    #expect(!prefs.mergeFeedEnabled)
  }

  /// Each toggle produces the negated `hide*` patch, which is the inversion the
  /// screen exists to perform.
  @Test func patchesNegate() {
    let prefs = FollowingFeedPreferences(
      showReplies: false, showReposts: true, showQuotePosts: false, mergeFeedEnabled: true)

    #expect(prefs.wireFields(for: .showReplies) == ["hideReplies": true])
    #expect(prefs.wireFields(for: .showReposts) == ["hideReposts": false])
    #expect(prefs.wireFields(for: .showQuotePosts) == ["hideQuotePosts": true])
    // The merge flag is NOT negated: it is stored positively.
    #expect(prefs.wireFields(for: .mergeFeedEnabled) == ["lab_mergeFeedEnabled": true])
  }

  /// Each patch carries exactly one field, so a toggle cannot clobber a
  /// sibling setting.
  @Test func patchesAreSingleField() {
    let prefs = FollowingFeedPreferences()
    for field in FollowingFeedPreferences.fields {
      #expect(
        prefs.wireFields(for: field).count == 1,
        "\(field) patch is not a single field")
    }
  }

  /// The field list is the four rows in screen order.
  @Test func fieldsInOrder() {
    #expect(
      FollowingFeedPreferences.fields.map(\.rawValue) == [
        "showReplies", "showReposts", "showQuotePosts", "mergeFeedEnabled",
      ])
    // Only the merge toggle is in the experimental group.
    #expect(FollowingFeedPreferences.Field.showReplies.isExperimental == false)
    #expect(FollowingFeedPreferences.Field.mergeFeedEnabled.isExperimental)
  }

  /// The toggle titles are the RN copy.
  @Test func titles() {
    #expect(FollowingFeedPreferences.Field.showReplies.title == "Show replies")
    #expect(FollowingFeedPreferences.Field.showReposts.title == "Show reposts")
    #expect(FollowingFeedPreferences.Field.showQuotePosts.title == "Show quote posts")
    #expect(
      FollowingFeedPreferences.Field.mergeFeedEnabled.title
        == "Show samples of your saved feeds in your Following feed")
  }

  /// Reads a field's current value.
  @Test func valueLookup() {
    let prefs = FollowingFeedPreferences(
      showReplies: false, showReposts: true, showQuotePosts: false, mergeFeedEnabled: true)
    #expect(prefs.value(of: .showReplies) == false)
    #expect(prefs.value(of: .showReposts))
    #expect(prefs.value(of: .showQuotePosts) == false)
    #expect(prefs.value(of: .mergeFeedEnabled))
  }

  /// The feed key is `home`, the legacy name RN still writes under.
  @Test func feedKey() {
    #expect(FollowingFeedPreferences.feedKey == "home")
  }
}

/// The thread preferences, ported from `useThreadPreferences.ts`.
@Suite struct ThreadPreferencesTests {

  /// `normalizeSort` maps anything unrecognized onto `top`.
  @Test func normalizeSort() {
    #expect(ThreadPreferences.normalizeSort("oldest") == .oldest)
    #expect(ThreadPreferences.normalizeSort("newest") == .newest)
    #expect(ThreadPreferences.normalizeSort("top") == .top)
    // The historic default `hotness` normalizes to `top`.
    #expect(ThreadPreferences.normalizeSort("hotness") == .top)
    #expect(ThreadPreferences.normalizeSort("") == .top)
    #expect(ThreadPreferences.normalizeSort("nonsense") == .top)
  }

  /// `normalizeView` turns the boolean into the option.
  @Test func normalizeView() {
    #expect(ThreadPreferences.normalizeView(treeViewEnabled: true) == .tree)
    #expect(ThreadPreferences.normalizeView(treeViewEnabled: false) == .linear)
  }

  /// The default sort is `top` (via `hotness`), matching
  /// `DEFAULT_THREAD_VIEW_PREFS`.
  @Test func defaults() {
    #expect(ThreadPreferences().sort == .top)
    #expect(ThreadPreferences().view == .linear)
    #expect(ThreadPreferences.defaultSort == .top)
  }

  /// A stored preference builds the model with both normalizations applied.
  @Test func fromStored() {
    let prefs = ThreadPreferences(
      from: ThreadViewPreference(sort: "hotness", lab_treeViewEnabled: true))
    #expect(prefs.sort == .top)
    #expect(prefs.view == .tree)

    let absent = ThreadPreferences(from: ThreadViewPreference(sort: "oldest"))
    #expect(absent.sort == .oldest)
    #expect(absent.view == .linear)
  }

  /// The patch writes the sort's wire value and the tree boolean.
  @Test func patch() {
    #expect(
      ThreadPreferences(sort: .newest, view: .linear).wireFields
        == ["sort": "newest", "lab_treeViewEnabled": "false"])
    #expect(
      ThreadPreferences(sort: .top, view: .tree).wireFields
        == ["sort": "top", "lab_treeViewEnabled": "true"])
  }

  /// The radio titles are the RN copy.
  @Test func titles() {
    #expect(ThreadSortOption.top.title == "Top replies first")
    #expect(ThreadSortOption.oldest.title == "Oldest replies first")
    #expect(ThreadSortOption.newest.title == "Newest replies first")
  }
}

/// The store's preference mutations, asserted through a real
/// `PreferencesEngine` over a fake service.
@Suite struct PreferencesMutationTests {

  /// A following-feed toggle writes the `home` feed view pref with the negated
  /// field, and leaves the other fields alone.
  @Test func followingFeedToggleWritesNegatedField() async throws {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    // Turn replies off.
    try await harness.store.setFollowingFeedToggle(.showReplies, value: false)

    let record = try #require(
      harness.prefsService.record(ofType: "app.bsky.actor.defs#feedViewPref"))
    #expect(record["feed"] as? String == "home")
    #expect(record["hideReplies"] as? Bool == true)
    // The edit is reflected in the store's model too.
    #expect(!harness.store.state.followingFeed.showReplies)

    // Turn them back on.
    try await harness.store.setFollowingFeedToggle(.showReplies, value: true)
    let updated = try #require(
      harness.prefsService.record(ofType: "app.bsky.actor.defs#feedViewPref"))
    #expect(updated["hideReplies"] as? Bool == false)
  }

  /// The experimental merge toggle is written positively.
  @Test func mergeFeedTogglePositive() async throws {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    try await harness.store.setFollowingFeedToggle(.mergeFeedEnabled, value: true)

    let record = try #require(
      harness.prefsService.record(ofType: "app.bsky.actor.defs#feedViewPref"))
    #expect(record["lab_mergeFeedEnabled"] as? Bool == true)
    #expect(record["feed"] as? String == "home")
  }

  /// Turning one toggle off does not disturb a previously set sibling.
  @Test func togglesDoNotClobberSiblings() async throws {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#feedViewPref","feed":"home",
          "hideReplies":true,"hideReposts":false,"hideQuotePosts":false}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    try await harness.store.setFollowingFeedToggle(.showReposts, value: false)

    let record = try #require(
      harness.prefsService.record(ofType: "app.bsky.actor.defs#feedViewPref"))
    // The untouched field survives.
    #expect(record["hideReplies"] as? Bool == true)
    #expect(record["hideReposts"] as? Bool == true)
  }

  /// The thread preference write sends the exact patch fields.
  @Test func threadPreferencesWrite() async throws {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    try await harness.store.setThreadPreferences(
      ThreadPreferences(sort: .oldest, view: .tree))

    let record = try #require(
      harness.prefsService.record(ofType: "app.bsky.actor.defs#threadViewPref"))
    #expect(record["sort"] as? String == "oldest")
    #expect(record["lab_treeViewEnabled"] as? Bool == true)
    #expect(harness.store.state.threads.sort == .oldest)
    #expect(harness.store.state.threads.view == .tree)
  }

  /// A preference-write failure is mapped and the local model is left alone.
  @Test func feedToggleFailureLeavesModel() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()
    let before = harness.store.state.followingFeed
    harness.prefsService.failNext(
      with: XrpcError(rawCode: nil, message: "offline", status: -1))

    var thrown: SettingsError?
    do {
      try await harness.store.setFollowingFeedToggle(.showReplies, value: false)
    } catch let error as SettingsError {
      thrown = error
    } catch {
      Issue.record("unexpected error type: \(error)")
    }

    #expect(thrown?.message == PreferencesWriteErrors.contactFailed)
    #expect(harness.store.state.followingFeed == before)
  }

  /// The thread preference failure path is mapped the same way.
  @Test func threadPreferencesFailureIsMapped() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()
    harness.prefsService.failNext(
      with: XrpcError(rawCode: nil, message: "offline", status: -1))

    var thrown: SettingsError?
    do {
      try await harness.store.setThreadPreferences(
        ThreadPreferences(sort: .newest, view: .linear))
    } catch let error as SettingsError {
      thrown = error
    } catch {
      Issue.record("unexpected error type: \(error)")
    }

    #expect(thrown?.message == PreferencesWriteErrors.contactFailed)
  }

  /// Loading interprets the stored `home` feed view pref into the model.
  @Test func loadInterpretsStoredFeedPrefs() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#feedViewPref","feed":"home",
          "hideReplies":true,"hideReposts":false,"hideQuotePosts":true,
          "lab_mergeFeedEnabled":true}]
        """)
    defer { harness.cleanUp() }

    await harness.store.loadPreferences()

    #expect(!harness.store.state.followingFeed.showReplies)
    #expect(harness.store.state.followingFeed.showReposts)
    #expect(!harness.store.state.followingFeed.showQuotePosts)
    #expect(harness.store.state.followingFeed.mergeFeedEnabled)
  }

  /// A preference fetch failure records the section's error and status.
  @Test func loadPreferencesFailure() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    harness.prefsService.failNext(
      with: XrpcError(rawCode: nil, message: "offline", status: -1))

    await harness.store.loadPreferences()

    #expect(harness.store.state.preferencesStatus == .failed)
    #expect(harness.store.state.preferencesError == "offline")
  }
}

/// The content-label matrix, ported from the moderation screen's label list and
/// `GlobalLabelPreference`.
@Suite struct ContentLabelMatrixTests {

  /// The row set is empty while adult content is off, matching RN's
  /// `{adultContentEnabled && ...}`.
  @Test func hiddenWhenAdultContentOff() {
    let rows = LabelPreferenceMatrix.rows(
      for: ContentLabelInputs(adultContentEnabled: false))
    #expect(rows.isEmpty)
  }

  /// With adult content on, the four configurable labels appear in screen order.
  @Test func rowOrder() {
    let rows = LabelPreferenceMatrix.rows(
      for: ContentLabelInputs(adultContentEnabled: true))
    #expect(
      rows.map(\.identifier) == ["porn", "sexual", "graphic-media", "nudity"])
  }

  /// An unset label takes the definition's `defaultSetting`.
  @Test func defaultsComeFromDefinitions() {
    let rows = LabelPreferenceMatrix.rows(
      for: ContentLabelInputs(adultContentEnabled: true))
    let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.identifier, $0.selected) })
    // From `defaultLabelSettings` / `Moderation.labels`.
    #expect(byID["porn"] == .hide)
    #expect(byID["sexual"] == .warn)
    #expect(byID["nudity"] == .ignore)
    #expect(byID["graphic-media"] == .warn)
  }

  /// A stored preference overrides the definition default.
  @Test func storedPreferenceWins() {
    let rows = LabelPreferenceMatrix.rows(
      for: ContentLabelInputs(
        adultContentEnabled: true, labels: ["porn": "ignore", "sexual": "hide"]))
    let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.identifier, $0.selected) })
    #expect(byID["porn"] == .ignore)
    #expect(byID["sexual"] == .hide)
    // Untouched labels still take their defaults.
    #expect(byID["nudity"] == .ignore)
  }

  /// The legacy `show` value normalizes to `ignore`.
  @Test func legacyShowValue() {
    let rows = LabelPreferenceMatrix.rows(
      for: ContentLabelInputs(adultContentEnabled: true, labels: ["porn": "show"]))
    #expect(rows.first { $0.identifier == "porn" }?.selected == .ignore)
  }

  /// An unrecognized stored value falls back to `warn`, RN's default.
  @Test func unknownValueFallsBackToWarn() {
    #expect(LabelVisibility.normalize("nonsense") == .warn)
    #expect(LabelVisibility.normalize("") == .warn)
  }

  /// The row copy is RN's `useGlobalLabelStrings`.
  @Test func rowCopy() {
    let rows = LabelPreferenceMatrix.rows(
      for: ContentLabelInputs(adultContentEnabled: true))
    let porn = rows.first { $0.identifier == "porn" }
    #expect(porn?.name == "Adult Content")
    #expect(porn?.description == "Explicit sexual images.")

    let graphic = rows.first { $0.identifier == "graphic-media" }
    #expect(graphic?.name == "Graphic Media")
    #expect(graphic?.description == "Explicit or potentially disturbing media.")

    let nudity = rows.first { $0.identifier == "nudity" }
    #expect(nudity?.name == "Non-sexual Nudity")
    #expect(nudity?.description == "E.g. artistic nudes.")
  }

  /// The three options and their labels.
  @Test func options() {
    #expect(LabelPreferenceMatrix.options == [.ignore, .warn, .hide])
    #expect(LabelVisibility.ignore.title == "Show")
    #expect(LabelVisibility.warn.title == "Warn")
    #expect(LabelVisibility.hide.title == "Hide")
  }

  /// The wire values RN's mutation sends: `show` for ignore, not `ignore`.
  @Test func storedValues() {
    #expect(LabelVisibility.ignore.storedValue == "show")
    #expect(LabelVisibility.warn.storedValue == "warn")
    #expect(LabelVisibility.hide.storedValue == "hide")
  }

  /// The global change carries the label key and no labeler scope.
  @Test func globalChange() {
    let change = LabelPreferenceMatrix.globalChange(identifier: "porn", visibility: .ignore)
    #expect(change.key == "porn")
    #expect(change.visibility == "show")
    #expect(change.labelerDID == nil)
  }

  /// Per-labeler rows read the labeler's overrides and honour `configurable`.
  @Test func labelerRows() {
    let definitions = [
      LabelValueDefinition(
        identifier: "custom", severity: .none, blurs: .media, defaultSetting: .warn,
        flags: [], behaviors: LabelTargetBehaviors(), definedBy: "did:plc:labeler",
        configurable: true),
      LabelValueDefinition(
        identifier: "!hide", severity: .alert, blurs: .content, defaultSetting: .hide,
        flags: [.noOverride], behaviors: LabelTargetBehaviors(), definedBy: "did:plc:labeler",
        configurable: false),
    ]
    let inputs = ContentLabelInputs(
      adultContentEnabled: true,
      labels: [:],
      labelerLabels: ["did:plc:labeler": ["custom": "hide"]])

    let rows = LabelPreferenceMatrix.labelerRows(
      for: inputs, labelerDID: "did:plc:labeler", definitions: definitions)

    // Only the configurable, non-builtin definition is offered.
    #expect(rows.map(\.identifier) == ["custom"])
    #expect(rows[0].selected == .hide)
  }

  /// Per-labeler rows are disabled while adult content is off.
  @Test func labelerRowsDisabled() {
    let definitions = [
      LabelValueDefinition(
        identifier: "custom", severity: .none, blurs: .media, defaultSetting: .warn,
        flags: [], behaviors: LabelTargetBehaviors(), definedBy: "did:plc:labeler",
        configurable: true)
    ]
    let rows = LabelPreferenceMatrix.labelerRows(
      for: ContentLabelInputs(adultContentEnabled: false),
      labelerDID: "did:plc:labeler", definitions: definitions)
    #expect(rows[0].isDisabled)
  }

  /// The store derives the matrix from the loaded preferences.
  @Test func storeDerivesMatrix() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true},
         {"$type":"app.bsky.actor.defs#contentLabelPref","label":"porn","visibility":"ignore"}]
        """)
    defer { harness.cleanUp() }

    await harness.store.loadPreferences()

    #expect(harness.store.state.adultContentEnabled)
    let rows = harness.store.state.labelRows
    #expect(rows.map(\.identifier) == ["porn", "sexual", "graphic-media", "nudity"])
    #expect(rows.first { $0.identifier == "porn" }?.selected == .ignore)
  }

  /// With adult content off, the store's matrix is empty.
  @Test func storeMatrixEmptyWhenOff() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#adultContentPref","enabled":false}]
        """)
    defer { harness.cleanUp() }

    await harness.store.loadPreferences()
    #expect(harness.store.state.labelRows.isEmpty)
  }

  /// Setting a label pref writes the pref, and the engine double-writes the
  /// legacy alias alongside it.
  @Test func setLabelVisibilityWritesAlias() async throws {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    try await harness.store.setLabelVisibility(.ignore, for: "porn")

    // The primary record.
    let primary = TestJSON.contentLabelPrefs(harness.prefsService, label: "porn")
    #expect(primary.count == 1)
    #expect(primary[0]["visibility"] as? String == "show")
    #expect(primary[0]["labelerDid"] == nil)

    // The legacy alias the engine double-writes.
    let alias = TestJSON.contentLabelPrefs(harness.prefsService, label: "nsfw")
    #expect(alias.count == 1)
    #expect(alias[0]["visibility"] as? String == "show")

    // And the derived row reflects it.
    #expect(
      harness.store.state.labelRows.first { $0.identifier == "porn" }?.selected == .ignore)
  }

  /// A scoped label pref carries the labeler DID and does not double-write the
  /// global alias.
  @Test func setScopedLabelVisibility() async throws {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    try await harness.store.setLabelVisibility(
      .hide, for: "porn", labelerDID: "did:plc:labeler")

    let primary = TestJSON.contentLabelPrefs(harness.prefsService, label: "porn")
    #expect(primary.count == 1)
    #expect(primary[0]["labelerDid"] as? String == "did:plc:labeler")
    #expect(primary[0]["visibility"] as? String == "hide")
    // No global alias was written.
    #expect(TestJSON.contentLabelPrefs(harness.prefsService, label: "nsfw").isEmpty)
  }

  /// The adult-content toggle writes the pref and clears the derived rows when
  /// turned off.
  @Test func setAdultContent() async throws {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#adultContentPref","enabled":false}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    try await harness.store.setAdultContentEnabled(true)
    #expect(harness.store.state.adultContentEnabled)
    #expect(
      harness.prefsService.record(ofType: "app.bsky.actor.defs#adultContentPref")?["enabled"]
        as? Bool == true)
    #expect(harness.store.state.labelRows.count == 4)

    try await harness.store.setAdultContentEnabled(false)
    #expect(!harness.store.state.adultContentEnabled)
    #expect(harness.store.state.labelRows.isEmpty)
  }

  /// A label-write failure is mapped.
  @Test func labelWriteFailureIsMapped() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()
    harness.prefsService.failNext(
      with: XrpcError(rawCode: nil, message: "offline", status: -1))

    var thrown: SettingsError?
    do {
      try await harness.store.setLabelVisibility(.hide, for: "porn")
    } catch let error as SettingsError {
      thrown = error
    } catch {
      Issue.record("unexpected error type: \(error)")
    }

    #expect(thrown?.message == PreferencesWriteErrors.contactFailed)
  }
}
