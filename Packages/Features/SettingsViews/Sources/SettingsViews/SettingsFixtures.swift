import Foundation
import SettingsLogic

/// The fixture data the settings surfaces render with no session and no network.
///
/// The fixture is deliberately built out of the *same* value types the live
/// screens read (``SettingsState``, ``SavedFeedItem``, ``LabelPreferenceRow``),
/// so a fixture-backed screen and a store-backed one take the identical code
/// path through the views.
public enum SettingsFixtures {
  /// A stand-in DID for the account flows that need one.
  public static let sampleDID = "did:plc:fixturesettings"

  /// The provider host the change-handle sheet offers subdomains under.
  public static let providerHost = "bsky.social"

  /// The plaintext password a fixture-created app password reports once.
  public static let samplePlaintextPassword = "fixture-1a2b-3c4d-5e6f"

  /// The fixture label matrix: the configurable labels, all at `warn`.
  public static let labelRows: [LabelPreferenceRow] =
    LabelPreferenceMatrix.configurableIdentifiers.map { identifier in
      let copy = LabelPreferenceMatrix.strings[identifier]
        ?? (name: identifier, description: "")
      return LabelPreferenceRow(
        identifier: identifier,
        name: copy.name,
        description: copy.description,
        selected: .warn)
    }

  /// The fixture saved feeds: the two recommended ones, pinned, plus one feed.
  public static let savedFeeds: [SavedFeedItem] = [
    SavedFeedItem(
      id: "fixture-timeline", type: "timeline", value: "following", isPinned: true),
    SavedFeedItem(
      id: "fixture-discover", type: "feed",
      value: SettingsConstants.discoverFeedURI, isPinned: true),
    SavedFeedItem(
      id: "fixture-quiet-posters", type: "feed",
      value: "at://did:plc:fixture/app.bsky.feed.generator/quiet-posters",
      isPinned: false),
  ]

  /// The fixture app passwords.
  public static let appPasswords: [SettingsAppPassword] = [
    SettingsAppPassword(name: "AliceBlue", privileged: false),
    SettingsAppPassword(name: "Studio", privileged: true),
  ]

  /// A fully-populated, fully-loaded settings state.
  public static var state: SettingsState {
    var state = SettingsState()
    state.preferencesStatus = .loaded
    state.appPasswordsStatus = .loaded
    state.appearanceStatus = .loaded
    state.languageStatus = .loaded
    state.followingFeed = .default
    state.threads = ThreadPreferences()
    state.labelRows = labelRows
    state.adultContentEnabled = true
    state.savedFeeds = SavedFeedsEditor(items: savedFeeds)
    state.appPasswords = appPasswords
    state.appearance = AppearancePreferences()
    state.languages = LanguagePreferences()
    return state
  }
}

/// Handle endpoints that succeed without a network, for the fixture surface.
///
/// The methods are `nonisolated` because ``HandleService`` is a `Sendable`
/// protocol whose requirements are nonisolated, while this module's default
/// isolation is `MainActor`. The bodies read no shared state, so there is
/// nothing to hop for.
///
/// The fixture does not fake the *flows*: ``ChangeHandleFlow`` and
/// ``DeleteAccountFlow`` are the real types in both modes, and only their
/// services differ.
struct FixtureHandleService: HandleService {
  nonisolated func updateHandle(_ handle: String) async throws {}
  nonisolated func resolveHandle(_ handle: String) async throws -> String {
    "did:plc:fixturesettings"
  }
}

/// An availability checker that always reports the handle as free.
struct FixtureHandleAvailability: HandleAvailabilityChecking {
  nonisolated func checkHandleAvailability(
    handle: String, serviceDID: String
  ) async throws -> HandleAvailabilityResult {
    .available
  }
}

/// Account-lifecycle endpoints that succeed without a network.
struct FixtureAccountLifecycle: AccountLifecycleService {
  nonisolated func deactivateAccount() async throws {}
  nonisolated func requestAccountDelete() async throws {}
  nonisolated func deleteAccount(did: String, password: String, token: String) async throws {}
}
