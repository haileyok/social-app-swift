import DesignTokens
import Foundation
import Observation
import Persistence
import SettingsLogic

/// The SwiftUI-facing adapter over ``SettingsStore``.
///
/// `SettingsStore` publishes a `Sendable` value state through an `addListener`
/// callback rather than being `Observable` itself (it is deliberately usable off
/// the main actor and from Linux CI). This type is the bridge: it registers one
/// listener, republishes every transition on the main actor, and holds the one
/// bit of state the store does not model - the transient confirmation banner.
///
/// The same type serves the fixture surface. Constructed with `store == nil` it
/// keeps the state locally and applies every edit in memory, so the screens, the
/// sheets and the account flows are all exercised with no session and no
/// network. The flows themselves are the real ``ChangeHandleFlow`` /
/// ``DeleteAccountFlow`` types in both modes; only their services differ.
///
/// Every decision still belongs to ``SettingsLogic``. This type calls the store
/// and renders whatever it reports; it re-derives no rule.
@MainActor
@Observable
public final class SettingsViewModel {
  /// The store's state, mirrored so SwiftUI re-reads it on change.
  public private(set) var state: SettingsState

  /// A transient confirmation, e.g. "Feeds updated!".
  public var notice: String?

  /// The last failure, ready to display.
  public private(set) var errorMessage: String?

  /// The signed-in account's DID, used by the delete-account confirmation.
  public var accountDID: String

  private let store: SettingsStore?

  /// Creates an adapter, optionally over a live store.
  ///
  /// - Parameters:
  ///   - store: the live store, or nil for the in-memory fixture mode.
  ///   - initial: the state to start from (the canonical fixture by default).
  ///   - accountDID: the DID the account flows act on.
  public init(
    store: SettingsStore? = nil,
    initial: SettingsState? = nil,
    accountDID: String? = nil
  ) {
    self.store = store
    self.state = initial ?? SettingsFixtures.state
    self.accountDID = accountDID ?? SettingsFixtures.sampleDID
    if let store {
      store.addListener { [weak self] newState in
        Task { @MainActor in
          self?.state = newState
        }
      }
    }
  }

  /// A view model backed by fixture data, with no session and no network.
  public static func fixture(
    accountDID: String? = nil
  ) -> SettingsViewModel {
    SettingsViewModel(initial: SettingsFixtures.state, accountDID: accountDID)
  }

  /// Whether this view model talks to a live store.
  public var isLive: Bool { store != nil }

  // MARK: - Loading

  /// Loads every slice, when there is a store.
  public func load() async {
    guard let store else { return }
    await store.loadAll()
  }

  /// Clears the transient banner.
  public func clearNotice() {
    notice = nil
  }

  /// Clears the error banner.
  public func clearError() {
    errorMessage = nil
  }

  private func present(_ error: any Error) {
    errorMessage = SettingsError.rawMessage(from: error)
  }

  private func present(_ error: SettingsError) {
    errorMessage = error.message
  }

  // MARK: - Appearance

  /// Sets the app colour mode.
  public func setColorMode(_ mode: ColorMode) async {
    guard let store else {
      state.appearance.colorMode = mode
      return
    }
    do {
      try await store.setColorMode(mode)
    } catch {
      present(error)
    }
  }

  /// Sets the dark-theme variant.
  public func setDarkTheme(_ theme: DarkThemeValue?) async {
    guard let store else {
      state.appearance.darkTheme = theme
      return
    }
    do {
      try await store.setDarkTheme(theme)
    } catch {
      present(error)
    }
  }

  /// Sets the font-scale step.
  public func setFontScale(_ step: FontScale.Step) async {
    guard let store else {
      state.appearance.fontScale = step
      return
    }
    do {
      try await store.setFontScale(step)
    } catch {
      present(error)
    }
  }

  /// Sets the font family.
  public func setFontFamily(_ family: FontFamilyValue) async {
    guard let store else {
      state.appearance.fontFamily = family
      return
    }
    do {
      try await store.setFontFamily(family)
    } catch {
      present(error)
    }
  }

  // MARK: - Following feed

  /// Applies one following-feed toggle.
  public func setFollowingFeed(
    _ field: FollowingFeedPreferences.Field, value: Bool
  ) async {
    guard let store else {
      switch field {
      case .showReplies: state.followingFeed.showReplies = value
      case .showReposts: state.followingFeed.showReposts = value
      case .showQuotePosts: state.followingFeed.showQuotePosts = value
      case .mergeFeedEnabled: state.followingFeed.mergeFeedEnabled = value
      }
      return
    }
    do {
      try await store.setFollowingFeedToggle(field, value: value)
    } catch {
      present(error)
    }
  }

  /// Applies a thread-preference change.
  public func setThreadPreferences(_ preferences: ThreadPreferences) async {
    guard let store else {
      state.threads = preferences
      return
    }
    do {
      try await store.setThreadPreferences(preferences)
    } catch {
      present(error)
    }
  }

  // MARK: - Content labels

  /// Applies a label-visibility change.
  public func setLabelVisibility(
    _ visibility: LabelVisibility, for identifier: String
  ) async {
    guard let store else {
      guard let index = state.labelRows.firstIndex(where: { $0.identifier == identifier })
      else { return }
      let row = state.labelRows[index]
      state.labelRows[index] = LabelPreferenceRow(
        identifier: row.identifier,
        name: row.name,
        description: row.description,
        selected: visibility,
        isDisabled: row.isDisabled)
      return
    }
    do {
      try await store.setLabelVisibility(visibility, for: identifier)
    } catch {
      present(error)
    }
  }

  /// Applies the adult-content toggle.
  public func setAdultContentEnabled(_ enabled: Bool) async {
    guard let store else {
      state.adultContentEnabled = enabled
      state.labelRows = enabled ? SettingsFixtures.labelRows : []
      return
    }
    do {
      try await store.setAdultContentEnabled(enabled)
    } catch {
      present(error)
    }
  }

  // MARK: - Saved feeds

  /// Applies an edit to the working list.
  public func editSavedFeeds(_ mutate: (inout SavedFeedsEditor) -> Void) {
    if let store {
      store.editSavedFeeds(mutate)
    } else {
      mutate(&state.savedFeeds)
    }
  }

  /// Writes the working list back.
  public func saveSavedFeeds() async {
    guard let store else {
      state.savedFeeds = SavedFeedsEditor(items: state.savedFeeds.items)
      notice = PreferencesWriteErrors.feedsUpdated
      return
    }
    do {
      try await store.saveSavedFeeds()
      notice = PreferencesWriteErrors.feedsUpdated
    } catch {
      present(error)
    }
  }

  /// Discards local edits, restoring the loaded list.
  public func discardSavedFeedsEdits() {
    if let store {
      store.discardSavedFeedsEdits()
    } else {
      state.savedFeeds.discardChanges()
    }
  }

  /// Seeds the recommended feeds into the working list.
  public func addRecommendedSavedFeeds() {
    if let store {
      store.addRecommendedSavedFeeds()
    } else {
      var editor = state.savedFeeds
      var counter = editor.items.count
      editor.append(
        SavedFeedsEditor.recommendedItems(makeID: {
          counter += 1
          return "fixture-recommended-\(counter)"
        }))
      state.savedFeeds = editor
    }
  }

  // MARK: - App passwords

  /// Validates the create form as data, before anything reaches the network.
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
  /// - Returns: the created password, including the plaintext that is shown once
  ///   and never returned again.
  public func createAppPassword(
    typedName: String, privileged: Bool, generatedName: String
  ) async -> Result<SettingsAppPassword, SettingsError> {
    guard let store else {
      switch validateAppPasswordForm(
        typedName: typedName, generatedName: generatedName) {
      case .invalid(let message):
        return .failure(.appPassword(message: message))
      case .valid(let name):
        let created = SettingsAppPassword(
          name: name,
          privileged: privileged,
          createdAt: nil,
          password: SettingsFixtures.samplePlaintextPassword)
        state.appPasswords = (state.appPasswords + [created]).sorted { $0.name < $1.name }
        state.appPasswordsStatus = .loaded
        return .success(created)
      }
    }
    return await store.createAppPassword(
      typedName: typedName, privileged: privileged, generatedName: generatedName)
  }

  /// Revokes an app password by name.
  public func revokeAppPassword(name: String) async -> Result<Void, SettingsError> {
    guard let store else {
      state.appPasswords.removeAll { $0.name == name }
      return .success(())
    }
    return await store.revokeAppPassword(name: name)
  }

  // MARK: - Account flows

  /// Builds the change-handle flow, over the store's services or the fixtures.
  public func makeChangeHandleFlow() -> ChangeHandleFlow {
    if let store {
      return store.makeChangeHandleFlow()
    }
    return ChangeHandleFlow(
      handles: FixtureHandleService(), availability: FixtureHandleAvailability())
  }

  /// Builds the delete-account flow.
  public func makeDeleteAccountFlow() -> DeleteAccountFlow {
    if let store {
      return store.makeDeleteAccountFlow()
    }
    return DeleteAccountFlow(service: FixtureAccountLifecycle())
  }

  /// Builds the deactivate-account flow.
  public func makeDeactivateAccountFlow() -> DeactivateAccountFlow {
    if let store {
      return store.makeDeactivateAccountFlow()
    }
    return DeactivateAccountFlow(service: FixtureAccountLifecycle())
  }

  /// The repo-export request for the signed-in account.
  public func repoExportRequest() async -> ExportDataRequest? {
    if let store {
      return await store.repoExportRequest()
    }
    return ExportData.repoRequest(did: accountDID)
  }

  /// Fetches the repo-export bytes.
  public func fetchRepoExport() async -> Result<Data, SettingsError> {
    if let store {
      return await store.fetchRepoExport()
    }
    return .success(Data("fixture-repo-export".utf8))
  }

  // MARK: - Languages

  /// Sets the primary (translate-target) language.
  public func setPrimaryLanguage(_ code: String) {
    state.languages.setPrimaryLanguage(code)
  }

  /// Sets the UI translation language.
  public func setAppLanguage(_ code: String) {
    state.languages.setAppLanguage(code)
  }

  /// Adds or removes a content language.
  public func toggleContentLanguage(_ code: String) {
    var languages = state.languages.contentLanguages
    if let index = languages.firstIndex(of: code) {
      languages.remove(at: index)
    } else {
      languages.append(code)
    }
    state.languages.contentLanguages = languages
  }
}
