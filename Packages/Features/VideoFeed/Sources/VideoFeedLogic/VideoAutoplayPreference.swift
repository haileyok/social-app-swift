import Foundation
import Persistence

/// Reads the persisted autoplay preference into the feed's settings.
///
/// Port of the two reads RN's `useAutoplayDisabled` makes against
/// `src/state/persisted`:
///
/// ```js
/// const [state, setState] = useState(Boolean(persisted.get('disableAutoplay')))
/// ```
///
/// where the schema default is `PlatformInfo.getIsReducedMotionEnabled()`
/// (`src/state/persisted/schema.ts`). The Logic layer cannot read the platform's
/// reduced-motion setting, so the caller passes that default in and this helper
/// only supplies the stored value when one exists.
///
/// The account-scoped key is `AccountSchema.autoplayDisabled`, which is where the
/// Swift port's `PersistedSchema` puts it (`disableAutoplay`, tolerantly decoded).
public enum VideoAutoplayPreference {
  /// The account schema key holding the preference.
  ///
  /// Named after the Swift port's key rather than RN's `disableAutoplay`: see
  /// ``Persistence/AccountSchema/autoplayDisabled``.
  public static let accountKey = AccountSchema.autoplayDisabled

  /// Reads the stored preference for `did`.
  ///
  /// - Parameters:
  ///   - account: the account-scoped store.
  ///   - did: the signed-in account's DID, the store's scope component.
  ///   - reducedMotionEnabled: the platform's reduced-motion setting, which RN
  ///     uses as the schema default.
  /// - Returns: `true` when autoplay should be disabled.
  public static func autoplayDisabled(
    account: Storage<AccountSchemaMarker>,
    did: String,
    reducedMotionEnabled: Bool = VideoAutoplaySettings.reducedMotionDefault
  ) async -> Bool {
    guard
      let stored: Bool = await account.get([did], accountKey, as: Bool.self)
    else {
      // No stored value: RN falls back to the schema default.
      return reducedMotionEnabled
    }
    return stored
  }

  /// Writes the preference for `did`.
  public static func setAutoplayDisabled(
    _ disabled: Bool,
    account: Storage<AccountSchemaMarker>,
    did: String
  ) async throws {
    try await account.set([did], accountKey, value: disabled)
  }

  /// Builds the feed's settings from the persisted preference.
  ///
  /// This is the whole derivation RN's video surfaces perform before a player may
  /// start: the stored autoplay flag, the (initially muted) volume state, and
  /// whether the item sits inside a message thread.
  public static func settings(
    account: Storage<AccountSchemaMarker>,
    did: String,
    muted: Bool = true,
    isWithinMessage: Bool = false,
    reducedMotionEnabled: Bool = VideoAutoplaySettings.reducedMotionDefault
  ) async -> VideoAutoplaySettings {
    VideoAutoplaySettings(
      autoplayDisabled: await autoplayDisabled(
        account: account, did: did, reducedMotionEnabled: reducedMotionEnabled),
      muted: muted,
      isWithinMessage: isWithinMessage)
  }
}
