import ATProtoClient
import Domain
import Foundation

/// A settings failure with a message a screen can show.
///
/// The settings flows each map errors from a different service into copy that
/// differs per flow (the app-password screen and the handle screen word the
/// same network failure differently), so this type is deliberately a thin
/// carrier of already-localized text plus the raw server message for logging.
public struct SettingsError: Error, Sendable, Equatable {
  /// The user-facing message.
  public let message: String
  /// The raw server message, for `logger.error`. Nil when the failure was
  /// client-side.
  public let raw: String?

  private init(message: String, raw: String?) {
    self.message = message
    self.raw = raw
  }

  /// A failure with no server-side counterpart.
  public static func unexpected(message: String) -> SettingsError {
    SettingsError(message: message, raw: nil)
  }

  /// A handle change that failed after mapping, carrying the display copy.
  public static func handleChange(message: String) -> SettingsError {
    SettingsError(message: message, raw: nil)
  }

  /// The form's own validation rejected the input, with the inline message.
  public static func invalidHandle(_ message: String) -> SettingsError {
    SettingsError(message: message, raw: nil)
  }

  /// A custom domain was submitted without a successful verification.
  public static func unverifiedDomain(_ message: String) -> SettingsError {
    SettingsError(message: message, raw: nil)
  }

  /// A handle was taken, with the display copy.
  public static func handleTaken(_ message: String) -> SettingsError {
    SettingsError(message: message, raw: nil)
  }

  /// An account-lifecycle failure, with the display copy and the raw message.
  public static func accountAction(message: String, raw: String? = nil) -> SettingsError {
    SettingsError(message: message, raw: raw)
  }

  /// An app-password failure, with the display copy and the raw message.
  public static func appPassword(message: String, raw: String? = nil) -> SettingsError {
    SettingsError(message: message, raw: raw)
  }

  /// A preference-write failure.
  public static func preferences(message: String, raw: String? = nil) -> SettingsError {
    SettingsError(message: message, raw: raw)
  }
}

extension SettingsError {
  /// The raw message a thrown error carries.
  ///
  /// `XrpcError` is the common case (it exposes both a code and a message); any
  /// other error falls back to its `localizedDescription`, which is what RN's
  /// `error.message` reads.
  public static func rawMessage(from error: any Error) -> String {
    if let xrpc = error as? XrpcError { return xrpc.message ?? "" }
    if let shape = error as? XRPCErrorShape { return shape.message }
    return (error as NSError).localizedDescription
  }
  /// The message used for matching against the known server strings.
  public static func message(from error: any Error) -> String {
    rawMessage(from: error)
  }
}
/// The mapping of app-password failures onto display copy.
///
/// Port of the two error sites in `AddAppPasswordDialog.tsx`: a form-level
/// validation error shows inline, while any other failure shows the generic
/// message. The distinction is carried by ``AppPasswordValidationOutcome`` for
/// validation; this covers the network side.
public enum AppPasswordErrors {
  /// `Failed to create app password. Please try again.`
  public static let createFailed = "Failed to create app password. Please try again."
  /// `There was an issue fetching your app passwords`
  public static let fetchFailed = "There was an issue fetching your app passwords"
  /// A revoke failure, shown as a toast in RN.
  public static let revokeFailed = "Failed to delete app password. Please try again."

  /// Maps a create failure. A thrown ``PreferencesError``-shaped validation
  /// error passes its own message through; everything else is generic.
  public static func create(_ error: any Error) -> SettingsError {
    SettingsError.appPassword(
      message: createFailed, raw: SettingsError.rawMessage(from: error))
  }

  /// Maps a list failure.
  public static func list(_ error: any Error) -> SettingsError {
    SettingsError.appPassword(
      message: fetchFailed, raw: SettingsError.rawMessage(from: error))
  }

  /// Maps a revoke failure.
  public static func revoke(_ error: any Error) -> SettingsError {
    SettingsError.appPassword(
      message: revokeFailed, raw: SettingsError.rawMessage(from: error))
  }
}

/// The generic preference-write failure copy.
public enum PreferencesWriteErrors {
  /// `There was an issue contacting the server`
  public static let contactFailed = "There was an issue contacting the server"
  /// `Feeds updated!`
  public static let feedsUpdated = "Feeds updated!"

  /// Maps a preference-write failure.
  public static func map(_ error: any Error) -> SettingsError {
    SettingsError.preferences(
      message: contactFailed, raw: SettingsError.rawMessage(from: error))
  }
}
