import Foundation
import Testing

import ATProtoClient
import DesignTokens
import Lexicons
import Persistence

@testable import SettingsLogic

/// The store's per-section state machines, as data.
@Suite struct SettingsStoreTests {

  /// Every section starts idle, with the defaults applied.
  @Test func initialSectionState() {
    let harness = SettingsState()
    #expect(harness.preferencesStatus == .idle)
    #expect(harness.appPasswordsStatus == .idle)
    #expect(harness.appearanceStatus == .idle)
    #expect(harness.languageStatus == .idle)
    #expect(harness.followingFeed == FollowingFeedPreferences.default)
    #expect(harness.threads == ThreadPreferences())
    #expect(harness.labelRows.isEmpty)
    #expect(harness.appPasswords.isEmpty)
    #expect(harness.savedFeeds.isEmpty)
  }

  /// `loadAll` populates every slice from the server and local storage.
  @Test func loadAll() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true},
         {"$type":"app.bsky.actor.defs#threadViewPref","sort":"oldest",
          "lab_treeViewEnabled":true}]
        """,
      passwords: [SettingsAppPassword(name: "Phone", privileged: false)],
      languagePrefs: LanguagePrefs(primaryLanguage: "ja"))
    defer { harness.cleanUp() }

    await harness.store.loadAll()

    let state = harness.store.state
    #expect(state.preferencesStatus == .loaded)
    #expect(state.appPasswordsStatus == .loaded)
    #expect(state.appearanceStatus == .loaded)
    #expect(state.languageStatus == .loaded)
    #expect(state.appPasswords.map(\.name) == ["Phone"])
    #expect(state.threads.sort == .oldest)
    #expect(state.threads.view == .tree)
    #expect(state.labelRows.count == 4)
    #expect(state.languages.primaryLanguage == "ja")
  }

  /// A failure in one slice does not stop the others, which is why the loads
  /// are independent.
  @Test func loadAllIsResilientToOneFailure() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]
        """,
      passwords: [SettingsAppPassword(name: "Phone", privileged: false)])
    defer { harness.cleanUp() }
    // The app-password list fails; the preference read succeeds.
    harness.appPasswords.setListError(
      XrpcError(rawCode: nil, message: "rate limited", status: 429))

    await harness.store.loadAll()

    let state = harness.store.state
    #expect(state.appPasswordsStatus == .failed)
    #expect(state.appPasswordsError != nil)
    // Everything else still populated.
    #expect(state.preferencesStatus == .loaded)
    #expect(state.labelRows.count == 4)
    #expect(state.appearanceStatus == .loaded)
    #expect(state.languageStatus == .loaded)
  }

  /// Observers see each state transition, and only on an actual change.
  @Test func listenerNotifiesOnChange() {
    let harness = SettingsStore(
      dependencies: SettingsStore.Dependencies(
        preferences: FakePreferencesService().engine(),
        appPasswords: FakeAppPasswordService(),
        handles: FakeHandleService(),
        availability: FakeHandleAvailability(),
        accountLifecycle: FakeAccountLifecycleService(),
        appearance: AppearancePreferencesStore()))
    let counter = Counter()
    harness.addListener { _ in counter.increment() }

    harness.editSavedFeeds { editor in
      editor.append([makeSavedFeed(id: "x", pinned: true)])
    }
    #expect(counter.value == 1)

    // A no-op edit produces no transition.
    harness.editSavedFeeds { _ in }
    #expect(counter.value == 1)
  }

  /// The route tree exposes only the in-scope routes.
  @Test func routesInScope() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    let routes = harness.store.routes
    #expect(routes.contains(.appearance))
    #expect(routes.contains(.account))
    #expect(routes.contains(.appPasswords))
    #expect(routes.contains(.savedFeeds))
    #expect(!routes.contains(.appIcon))
    #expect(!routes.contains(.betaFeatures))
  }

  /// The store serves the menu sections per route.
  @Test func sectionsForRoute() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    #expect(harness.store.sections(for: .settings).first?.route == .settings)
    #expect(harness.store.sections(for: .account).first?.route == .account)
    #expect(
      harness.store.sections(for: .privacyAndSecurity).first?.route == .privacyAndSecurity)
    #expect(harness.store.sections(for: .contentAndMedia).first?.route == .contentAndMedia)
    // A leaf route has no sections of its own.
    #expect(harness.store.sections(for: .appearance).isEmpty)
  }

  /// The deep-link path comes straight off the route.
  @Test func pathForRoute() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    #expect(harness.store.path(for: .appearance) == "/settings/appearance")
    #expect(harness.store.path(for: .appPasswords) == "/settings/app-passwords")
  }

  /// The store builds the three account flows over its dependencies.
  @Test func buildsAccountFlows() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    let handleFlow = harness.store.makeChangeHandleFlow()
    #expect(handleFlow.state.page == .providedHandle)

    let deleteFlow = harness.store.makeDeleteAccountFlow()
    #expect(deleteFlow.state.step == .sendCode)

    let deactivateFlow = harness.store.makeDeactivateAccountFlow()
    let result = await deactivateFlow.deactivate()
    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(harness.lifecycle.deactivateCount == 1)
  }

  /// The appearance setters write through the store and refresh the snapshot.
  @Test func appearanceSetters() async throws {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    try await harness.store.setColorMode(.dark)
    #expect(harness.store.state.appearance.colorMode == ColorMode.dark)

    try await harness.store.setFontScale(.plus1)
    #expect(harness.store.state.appearance.fontScale == FontScale.Step.plus1)

    try await harness.store.setFontFamily(.system)
    #expect(harness.store.state.appearance.fontFamily == FontFamilyValue.system)
  }

  /// The resolved theme goes through the store's appearance layer.
  @Test func resolvedThemeThroughStore() async throws {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    try await harness.store.setColorMode(.light)
    #expect(await harness.store.resolvedTheme(systemScheme: .dark) == .light)
  }

  /// The `home` feed-view default is used when the stored prefs carry no
  /// `home` entry.
  ///
  /// The interpreted `Preferences` value is produced by a real hydrating
  /// engine rather than constructed directly, because the engine is the only
  /// supported builder for it.
  @Test func homeFeedPreferenceDefault() async throws {
    let service = FakePreferencesService(rawJSON: "[]")
    let interpreted = try await service.engine().getPreferences()

    let preference = SettingsStore.homeFeedPreference(interpreted)

    // Absent means the engine's default: replies/reposts/quotes shown, merge
    // off, which is `FollowingFeedPreferences.default`.
    #expect(preference.feed == "home")
    #expect(FollowingFeedPreferences(from: preference) == FollowingFeedPreferences.default)
  }

  /// A stored `home` entry is read rather than defaulted.
  @Test func homeFeedPreferenceStored() async throws {
    let service = FakePreferencesService(rawJSON: """
      [{"$type":"app.bsky.actor.defs#feedViewPref","feed":"home",
        "hideReplies":true,"lab_mergeFeedEnabled":true}]
      """)
    let interpreted = try await service.engine().getPreferences()

    let preference = SettingsStore.homeFeedPreference(interpreted)
    let model = FollowingFeedPreferences(from: preference)
    #expect(!model.showReplies)
    #expect(model.mergeFeedEnabled)
  }
}
