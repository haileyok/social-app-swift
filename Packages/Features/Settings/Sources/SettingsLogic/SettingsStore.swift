import ATProtoClient
import DesignTokens
import Foundation
import Persistence
import Preferences
import QueryStore
import Synchronization

/// The settings store: the sections model plus one state machine per section,
/// held as data.
///
/// This is the package's front door. It owns:
///
/// - the navigation tree (``SettingsRoute``) and the menu rows
///   (``SettingsMenu``);
/// - the loaded slices each screen reads - appearance, following-feed and
///   thread preferences, the label matrix, the saved-feeds editor, the
///   app-password list, and the language preferences;
/// - the per-section loading state, so a view can tell "not fetched" from
///   "fetched and empty".
///
/// It does **not** own the interactive flows (change handle, delete account).
/// Those are separate types (``ChangeHandleFlow``, ``DeleteAccountFlow``)
/// because they have their own multi-step state and outlive a single screen
/// refresh; the store constructs them on request instead.
///
/// `@unchecked Sendable`: the state is lock-guarded. Dependencies are all
/// `Sendable` actors or value types.
public final class SettingsStore: @unchecked Sendable {

  /// A state observer, invoked with the new snapshot after every change.
  public typealias Listener = @Sendable (SettingsState) -> Void

  /// The per-section dependencies, bundled so a test can swap any one.
  public struct Dependencies: Sendable {
    /// The preference engine, for every server-side preference write.
    public let preferences: PreferencesEngine
    /// The app-password endpoints.
    public let appPasswords: AppPasswordService
    /// The handle endpoints.
    public let handles: HandleService
    /// The handle-availability checker.
    public let availability: HandleAvailabilityChecking
    /// The account-lifecycle endpoints.
    public let accountLifecycle: AccountLifecycleService
    /// Device-scope appearance storage.
    public let appearance: AppearancePreferencesStore
    /// A client for the repo export.
    public let exportClient: LiveExportDataService?
    /// The DID of the signed-in account, for the export request. Read lazily
    /// because the store may be constructed before the session is known.
    public let currentDID: @Sendable () async -> String?
    /// The persisted language slice. RN keeps these in the persisted root
    /// rather than the server, so they are read through a closure that a test
    /// can back with an in-memory document.
    public let languageSource: @Sendable () async -> Persistence.LanguagePrefs

    public init(
      preferences: PreferencesEngine,
      appPasswords: AppPasswordService,
      handles: HandleService,
      availability: HandleAvailabilityChecking,
      accountLifecycle: AccountLifecycleService,
      appearance: AppearancePreferencesStore,
      exportClient: LiveExportDataService? = nil,
      currentDID: @escaping @Sendable () async -> String? = { nil },
      languageSource: @escaping @Sendable () async -> Persistence.LanguagePrefs = {
        Persistence.LanguagePrefs()
      }
    ) {
      self.preferences = preferences
      self.appPasswords = appPasswords
      self.handles = handles
      self.availability = availability
      self.accountLifecycle = accountLifecycle
      self.appearance = appearance
      self.exportClient = exportClient
      self.currentDID = currentDID
      self.languageSource = languageSource
    }
  }

  private let dependencies: Dependencies
  private let lock = NSLock()
  private var listeners: [Listener] = []
  private var current = SettingsState()

  public init(dependencies: Dependencies) {
    self.dependencies = dependencies
  }

  // MARK: - Navigation

  /// The route tree this store serves, filtered to the v1 scope.
  public var routes: [SettingsRoute] {
    SettingsRoute.allCases.filter(\.isInScope)
  }

  /// The menu sections for a route, or the root menu for `.settings`.
  public func sections(for route: SettingsRoute) -> [SettingsSection] {
    switch route {
    case .settings: return SettingsMenu.root
    case .account: return SettingsMenu.account
    case .privacyAndSecurity: return SettingsMenu.privacyAndSecurity
    case .contentAndMedia: return SettingsMenu.contentAndMedia
    default: return []
    }
  }

  /// The route a row leads to, resolved through the tree.
  public func destination(of row: SettingsRow) -> SettingsRoute? {
    row.route
  }

  /// The path for a route, for a deep link.
  public func path(for route: SettingsRoute) -> String {
    route.path
  }

  // MARK: - Observation

  /// The current state snapshot.
  public var state: SettingsState {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  /// Registers a state observer.
  public func addListener(_ listener: @escaping Listener) {
    lock.lock()
    listeners.append(listener)
    lock.unlock()
  }

  private func update(_ mutate: (inout SettingsState) -> Void) {
    lock.lock()
    let previous = current
    mutate(&current)
    let snapshot = current
    let changed = snapshot != previous
    let observers = listeners
    lock.unlock()
    guard changed else { return }
    for observer in observers { observer(snapshot) }
  }

  // MARK: - Section loading

  /// Loads everything the settings screens need from the server.
  ///
  /// Each slice is loaded independently: one failing slice records its own
  /// error and the rest still populate. That matters because the account
  /// screens must render even when, say, the app-password list is rate limited.
  public func loadAll() async {
    await loadPreferences()
    await loadAppPasswords()
    await loadAppearance()
    await loadLanguages()
  }

  /// Reads and interprets the server preferences, then derives every
  /// preference-backed slice.
  public func loadPreferences() async {
    update { $0.preferencesStatus = .loading }
    do {
      let preferences = try await dependencies.preferences.getPreferences()
      update { state in
        state.preferencesStatus = .loaded
        state.preferencesError = nil
        state.followingFeed = FollowingFeedPreferences(from: Self.homeFeedPreference(preferences))
        state.threads = ThreadPreferences(from: preferences.threadViewPrefs)
        state.labelRows = LabelPreferenceMatrix.rows(for: ContentLabelInputs.from(preferences))
        state.adultContentEnabled = preferences.moderationPrefs.adultContentEnabled
        state.savedFeeds = SavedFeedsEditor(prefs: preferences.savedFeeds)
      }
    } catch {
      update { state in
        state.preferencesStatus = .failed
        state.preferencesError = SettingsError.rawMessage(from: error)
      }
    }
  }

  /// Reads the app-password list.
  public func loadAppPasswords() async {
    update { $0.appPasswordsStatus = .loading }
    do {
      let passwords = try await dependencies.appPasswords.listAppPasswords()
      update { state in
        state.appPasswordsStatus = .loaded
        state.appPasswords = passwords.sorted { $0.name < $1.name }
        state.appPasswordsError = nil
      }
    } catch {
      update { state in
        state.appPasswordsStatus = .failed
        state.appPasswordsError = AppPasswordErrors.list(error)
      }
    }
  }

  /// Reads the device-scope appearance preferences.
  public func loadAppearance() async {
    update { $0.appearanceStatus = .loading }
    let appearance = await dependencies.appearance.snapshot()
    update { state in
      state.appearanceStatus = .loaded
      state.appearance = appearance
    }
  }

  /// Reads the language preferences out of the persisted document.
  ///
  /// RN stores these in the persisted root, so this goes through
  /// ``SettingsStore/Dependencies``'s persistence rather than the server.
  public func loadLanguages() async {
    update { $0.languageStatus = .loading }
    let stored = await dependencies.languageSource()
    update { state in
      state.languageStatus = .loaded
      state.languages = LanguagePreferences(from: stored)
    }
  }

  // MARK: - Appearance

  /// Sets the color mode and mirrors it into the state.
  public func setColorMode(_ mode: ColorMode) async throws {
    try await dependencies.appearance.setColorMode(mode)
    await loadAppearance()
  }

  /// Sets the dark-theme variant.
  public func setDarkTheme(_ theme: DarkThemeValue?) async throws {
    try await dependencies.appearance.setDarkTheme(theme)
    await loadAppearance()
  }

  /// Sets the font scale step.
  public func setFontScale(_ step: FontScale.Step) async throws {
    try await dependencies.appearance.setFontScale(step)
    await loadAppearance()
  }

  /// Sets the font family.
  public func setFontFamily(_ family: FontFamilyValue) async throws {
    try await dependencies.appearance.setFontFamily(family)
    await loadAppearance()
  }

  /// The resolved theme for the current appearance and an OS scheme.
  public func resolvedTheme(systemScheme: ThemeScheme) async -> ThemeName {
    await dependencies.appearance.resolvedTheme(systemScheme: systemScheme)
  }

  // MARK: - Following feed preferences

  /// Applies one following-feed toggle.
  ///
  /// The write goes to the `home` feed key with the negated `hide*` field,
  /// which is exactly what the RN screen does.
  public func setFollowingFeedToggle(
    _ field: FollowingFeedPreferences.Field, value: Bool
  ) async throws {
    var updated = state.followingFeed
    switch field {
    case .showReplies: updated.showReplies = value
    case .showReposts: updated.showReposts = value
    case .showQuotePosts: updated.showQuotePosts = value
    case .mergeFeedEnabled: updated.mergeFeedEnabled = value
    }
    do {
      try await dependencies.preferences.setFeedViewPrefs(
        feed: FollowingFeedPreferences.feedKey, patch: updated.patch(for: field))
    } catch {
      throw PreferencesWriteErrors.map(error)
    }
    update { $0.followingFeed = updated }
  }

  // MARK: - Thread preferences

  /// Applies a thread preference change.
  public func setThreadPreferences(_ preferences: ThreadPreferences) async throws {
    do {
      try await dependencies.preferences.setThreadViewPrefs(preferences.patch)
    } catch {
      throw PreferencesWriteErrors.map(error)
    }
    update { $0.threads = preferences }
  }

  // MARK: - Content labels

  /// Applies a content-label visibility change.
  ///
  /// The engine's `setContentLabelPref` also double-writes the legacy aliases,
  /// so this is a thin wrapper that reloads the derived matrix afterwards.
  public func setLabelVisibility(
    _ visibility: LabelVisibility, for identifier: String, labelerDID: String? = nil
  ) async throws {
    do {
      try await dependencies.preferences.setContentLabelPref(
        key: identifier, value: visibility.storedValue, labelerDid: labelerDID)
    } catch {
      throw PreferencesWriteErrors.map(error)
    }
    await refreshLabelRows()
  }

  /// Applies the adult-content toggle.
  public func setAdultContentEnabled(_ enabled: Bool) async throws {
    do {
      try await dependencies.preferences.setAdultContentEnabled(enabled)
    } catch {
      throw PreferencesWriteErrors.map(error)
    }
    update { state in
      state.adultContentEnabled = enabled
      // RN renders the label rows only when adult content is on, so the row
      // set is recomputed rather than filtered at render time.
      state.labelRows = enabled ? state.labelRows : []
    }
    await refreshLabelRows()
  }

  /// Re-reads the preferences and rebuilds the label matrix.
  private func refreshLabelRows() async {
    guard let preferences = try? await dependencies.preferences.getPreferences() else {
      return
    }
    update { state in
      state.labelRows = LabelPreferenceMatrix.rows(
        for: ContentLabelInputs.from(preferences))
    }
  }

  // MARK: - Saved feeds

  /// The current editor, as a value.
  public var savedFeeds: SavedFeedsEditor {
    state.savedFeeds
  }

  /// Applies an edit to the working list.
  ///
  /// Nothing is written here: RN keeps the edits local and writes once on
  /// "Save changes", so the store does the same and ``saveSavedFeeds()``
  /// performs the single ordered write.
  public func editSavedFeeds(_ mutate: (inout SavedFeedsEditor) -> Void) {
    update { state in
      var editor = state.savedFeeds
      mutate(&editor)
      state.savedFeeds = editor
    }
  }

  /// Writes the working list back with one `overwriteSavedFeeds` call.
  ///
  /// `overwriteSavedFeeds` is the operation RN uses here, and the engine
  /// dedupes by id and re-partitions pinned-first on the way through, so the
  /// order this sends is the order the user arranged.
  public func saveSavedFeeds() async throws {
    let editor = state.savedFeeds
    do {
      try await dependencies.preferences.overwriteSavedFeeds(
        editor.items.map(\.prefObject))
    } catch {
      throw PreferencesWriteErrors.map(error)
    }
    await loadPreferences()
  }

  /// Discards local edits, restoring the server's list.
  public func discardSavedFeedsEdits() {
    update { state in
      var editor = state.savedFeeds
      editor.discardChanges()
      state.savedFeeds = editor
    }
  }

  /// Seeds the recommended feeds into the working list, for the empty state.
  public func addRecommendedSavedFeeds() {
    update { state in
      var editor = state.savedFeeds
      editor.append(
        SavedFeedsEditor.recommendedItems(makeID: { TIDPlaceholder.next() }))
      state.savedFeeds = editor
    }
  }

  // MARK: - App passwords

  /// The create form's current state.
  ///
  /// The form is validated as data first; nothing reaches the network until
  /// ``createAppPassword(typedName:privileged:)`` returns ``valid``.
  public func validateAppPasswordForm(
    typedName: String, generatedName: String
  ) -> AppPasswordValidationOutcome {
    AppPasswordValidation.validate(
      typed: typedName,
      generated: generatedName,
      existingNames: state.appPasswords.map(\.name))
  }

  /// Creates an app password.
  ///
  /// - Returns: the created password, including the plaintext that is shown
  ///   once and never returned again.
  public func createAppPassword(
    typedName: String, privileged: Bool, generatedName: String
  ) async -> Result<SettingsAppPassword, SettingsError> {
    switch validateAppPasswordForm(typedName: typedName, generatedName: generatedName) {
    case .invalid(let message):
      return .failure(.appPassword(message: message))
    case .valid(let name):
      do {
        let created = try await dependencies.appPasswords.createAppPassword(
          name: name, privileged: privileged)
        await loadAppPasswords()
        return .success(created)
      } catch {
        return .failure(AppPasswordErrors.create(error))
      }
    }
  }

  /// Revokes an app password by name.
  public func revokeAppPassword(name: String) async -> Result<Void, SettingsError> {
    do {
      try await dependencies.appPasswords.revokeAppPassword(name: name)
      await loadAppPasswords()
      return .success(())
    } catch {
      return .failure(AppPasswordErrors.revoke(error))
    }
  }

  // MARK: - Account flows

  /// Builds a change-handle flow over this store's dependencies.
  public func makeChangeHandleFlow(
    state: ChangeHandleState = ChangeHandleState()
  ) -> ChangeHandleFlow {
    ChangeHandleFlow(
      handles: dependencies.handles,
      availability: dependencies.availability,
      state: state)
  }

  /// Builds a delete-account flow.
  public func makeDeleteAccountFlow(
    onBeforeDelete: @escaping @Sendable () async throws -> Void = {}
  ) -> DeleteAccountFlow {
    DeleteAccountFlow(
      service: dependencies.accountLifecycle, onBeforeDelete: onBeforeDelete)
  }

  /// Builds a deactivate-account flow.
  public func makeDeactivateAccountFlow() -> DeactivateAccountFlow {
    DeactivateAccountFlow(service: dependencies.accountLifecycle)
  }

  /// The export request for the signed-in account, or nil when there is no
  /// session.
  public func repoExportRequest() async -> ExportDataRequest? {
    guard let did = await dependencies.currentDID() else { return nil }
    return ExportData.repoRequest(did: did)
  }

  /// Fetches the repo export bytes.
  public func fetchRepoExport() async -> Result<Data, SettingsError> {
    guard let did = await dependencies.currentDID() else {
      return .failure(.unexpected(message: SettingsStrings.invalidDid))
    }
    guard let exportClient = dependencies.exportClient else {
      return .failure(.unexpected(message: SettingsStrings.exportUnavailable))
    }
    do {
      return .success(try await exportClient.fetchRepo(did: did))
    } catch {
      return .failure(
        .unexpected(message: SettingsStrings.exportFailed(error: error)))
    }
  }

  // MARK: - Helpers

  /// The `home` feed view preference, defaulted the way the RN read path
  /// defaults it (`DEFAULT_HOME_FEED_PREFS` merged under the stored entry).
  static func homeFeedPreference(_ preferences: Preferences) -> FeedViewPreference {
    preferences.feedViewPrefs[FollowingFeedPreferences.feedKey]
      ?? FeedViewPreference(feed: FollowingFeedPreferences.feedKey)
  }
}

/// The settings store's observable state.
public struct SettingsState: Sendable, Equatable {
  /// The load state of a section.
  public enum LoadStatus: String, Sendable, Equatable {
    case idle
    case loading
    case loaded
    case failed
  }

  /// Server preferences.
  public var preferencesStatus: LoadStatus = .idle
  /// The raw preference-fetch error message, for logging.
  public var preferencesError: String?
  /// The following-feed toggles.
  public var followingFeed: FollowingFeedPreferences = .default
  /// The thread preferences.
  public var threads: ThreadPreferences = ThreadPreferences()
  /// The derived content-label matrix.
  public var labelRows: [LabelPreferenceRow] = []
  /// Whether adult content is enabled, which gates the label rows.
  public var adultContentEnabled: Bool = false
  /// The saved-feeds working list.
  public var savedFeeds: SavedFeedsEditor = SavedFeedsEditor(items: [])

  /// App-password list.
  public var appPasswordsStatus: LoadStatus = .idle
  /// The app passwords, sorted by name.
  public var appPasswords: [SettingsAppPassword] = []
  /// The app-password list error, ready to display.
  public var appPasswordsError: SettingsError?

  /// Device-scope appearance.
  public var appearanceStatus: LoadStatus = .idle
  /// The current appearance.
  public var appearance: AppearancePreferences = AppearancePreferences()

  /// Language preferences.
  public var languageStatus: LoadStatus = .idle
  /// The current language preferences.
  public var languages: LanguagePreferences = LanguagePreferences()

  public init() {}
}

/// A monotonically increasing id source for locally-created saved feeds.
///
/// RN uses `TID.nextStr()` here. This is only for items that have not been
/// written yet; the engine mints the authoritative id on `addSavedFeeds`, so
/// the exact format does not matter, only uniqueness within a session.
enum TIDPlaceholder {
  private static let counter = Mutex(0)

  static func next() -> String {
    counter.withLock { value in
      value += 1
      return "local-\(value)"
    }
  }
}
