import Foundation

/// Device-scoped key/value data: the Swift port of the RN `Device` schema in
/// `src/storage/schema.ts`.
///
/// Only the fields the Swift app needs today are modelled. The schema is an
/// open struct rather than a closed Codable type, because it is written and
/// read one key at a time through ``Storage``; each call declares the type of
/// the single key it touches.
public enum DeviceSchema {
  /// Stable identifier used for logging and metrics (formerly StatSig).
  public static let deviceId = "deviceId"
  /// Native session id, used for event grouping.
  public static let nativeSessionId = "nativeSessionId"
  /// Timestamp of the last session-id event.
  public static let nativeSessionIdLastEventAt = "nativeSessionIdLastEventAt"
  /// UI font scale.
  public static let fontScale = "fontScale"
  /// UI font family choice.
  public static let fontFamily = "fontFamily"
  /// Last NUX dialog shown.
  public static let lastNuxDialog = "lastNuxDialog"
  /// Feature flag for the trending beta.
  public static let trendingBetaEnabled = "trendingBetaEnabled"

  /// Every key this schema defines.
  public static let allKeys: [String] = [
    deviceId, nativeSessionId, nativeSessionIdLastEventAt, fontScale,
    fontFamily, lastNuxDialog, trendingBetaEnabled,
  ]
}

/// Account-scoped key/value data: the Swift port of the RN `Account` schema.
///
/// Scoped by DID. Keys here are preferences that differ per account but are
/// not part of the profile record.
public enum AccountSchema {
  /// The user's saved feeds (pinned/ordered).
  public static let savedFeeds = "savedFeeds"
  /// The user's saved feed preferences (per-feed settings).
  public static let savedFeedsPrefV2 = "savedFeedsPrefV2"
  /// Whether the user has dismissed the "invite friends" nudge.
  public static let invitePromoDismissed = "invitePromoDismissed"
  /// Per-language auto-translate preference.
  public static let autoplayDisabled = "autoplayDisabled"
  /// The user's selected content-language overrides.
  public static let postLanguage = "postLanguage"

  /// Every key this schema defines.
  public static let allKeys: [String] = [
    savedFeeds, savedFeedsPrefV2, invitePromoDismissed, autoplayDisabled,
    postLanguage,
  ]
}

/// The two scoped stores, constructed together so the directory layout is
/// decided in one place.
public struct ScopedStores: Sendable {
  /// Device-scoped store (no per-account scope component).
  public let device: Storage<DeviceSchemaMarker>
  /// Account-scoped store (one scope component: the DID).
  public let account: Storage<AccountSchemaMarker>

  /// Creates both stores under `directory`.
  public init(directory: URL, fileManager: SendableFileManager = SendableFileManager()) {
    self.device = Storage(
      id: "bsky_device", scope: [], directory: directory, fileManager: fileManager)
    self.account = Storage(
      id: "bsky_account", scope: [], directory: directory, fileManager: fileManager,
      migration: PersistedMigrator.closure)
  }
}

/// Marker type giving the device store its generic parameter. Values are
/// written one key at a time, so the schema is a namespace of key names rather
/// than a Codable shape.
public enum DeviceSchemaMarker {}

/// Marker type giving the account store its generic parameter.
public enum AccountSchemaMarker {}
