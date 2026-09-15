import ATProtoClient
import Foundation
import Lexicons

/// The app-password endpoints, behind a protocol so the service can be faked.
///
/// Port of `state/queries/app-passwords.ts`: the list query, the create
/// mutation (which returns the plaintext password once), and the revoke
/// mutation. All three are PDS calls against the account's own host.
public protocol AppPasswordService: Sendable {
  /// `com.atproto.server.listAppPasswords`
  func listAppPasswords() async throws -> [SettingsAppPassword]
  /// `com.atproto.server.createAppPassword`
  func createAppPassword(name: String, privileged: Bool) async throws -> SettingsAppPassword
  /// `com.atproto.server.revokeAppPassword`
  func revokeAppPassword(name: String) async throws
}

/// One app password as the settings screen models it.
///
/// `com.atproto.server.listAppPasswords` returns `createdAt`, `name` and
/// `privileged`, but never the password itself: the plaintext is only ever
/// returned by `createAppPassword`. The model keeps that distinction by making
/// ``password`` optional and only populating it on create.
public struct SettingsAppPassword: Sendable, Equatable, Hashable {
  /// The user-chosen name, which is also the revoke key.
  public let name: String
  /// `privileged` means the password may access direct messages.
  public let privileged: Bool
  /// The creation timestamp, as the raw ISO string the server sends.
  public let createdAt: String?
  /// The plaintext password. Present only in a `createAppPassword` response.
  public let password: String?

  public init(
    name: String,
    privileged: Bool = false,
    createdAt: String? = nil,
    password: String? = nil
  ) {
    self.name = name
    self.privileged = privileged
    self.createdAt = createdAt
    self.password = password
  }
}

/// The live ``AppPasswordService`` over an ``XrpcClient``.
public struct LiveAppPasswordService: AppPasswordService {
  private let client: XrpcClient
  private let authorization: @Sendable () async throws -> String?

  public init(
    client: XrpcClient,
    authorization: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    self.client = client
    self.authorization = authorization
  }

  public func listAppPasswords() async throws -> [SettingsAppPassword] {
    let output: Com.Atproto.ServerListAppPasswords_Output = try await client.get(
      "com.atproto.server.listAppPasswords",
      authorization: try await authorization())
    return output.passwords.map {
      SettingsAppPassword(name: $0.name, privileged: $0.privileged ?? false)
    }
  }

  public func createAppPassword(
    name: String, privileged: Bool
  ) async throws -> SettingsAppPassword {
    let input = Com.Atproto.ServerCreateAppPassword_Input(
      name: name, privileged: privileged)
    let output: Com.Atproto.ServerCreateAppPassword_AppPassword = try await client.procedure(
      "com.atproto.server.createAppPassword", body: input,
      authorization: try await authorization())
    return SettingsAppPassword(
      name: output.name,
      privileged: output.privileged ?? false,
      createdAt: output.createdAt.rawValue,
      password: output.password)
  }

  public func revokeAppPassword(name: String) async throws {
    let input = Com.Atproto.ServerRevokeAppPassword_Input(name: name)
    _ = try await client.procedure(
      "com.atproto.server.revokeAppPassword", body: input,
      authorization: try await authorization()) as XrpcClient.EmptyResponse
  }
}

/// The outcome of authenticating the create form.
public enum AppPasswordValidationOutcome: Sendable, Equatable {
  /// The form is submittable; carries the name that will be used (the typed
  /// name, or the generated one when the field is empty).
  case valid(name: String)
  /// The field failed a rule; carries the message the screen shows inline.
  case invalid(message: String)
}

/// Create-form validation, ported field-for-field from
/// `screens/Settings/components/AddAppPasswordDialog.tsx`.
///
/// Three rules apply, in this order:
///
/// 1. While typing, the field must match `^[a-zA-Z0-9-_ ]*$` - letters,
///    numbers, spaces, hyphens, and underscores only. RN computes this as a
///    *display* error, so it shows on every keystroke even before submit.
/// 2. On submit, the chosen name (trimmed, or the generated default when the
///    field is empty) must be at least 4 characters.
/// 3. On submit, the chosen name must not already be in the account's list.
///
/// The messages are the exact RN copy, so the view layer and the tests agree
/// with the app's catalogs.
public enum AppPasswordValidation {
  /// The RN rule: `^[a-zA-Z0-9-_ ]*$`.
  public static let allowedNamePattern = "^[a-zA-Z0-9-_ ]*$"

  /// The minimum length, from RN's `chosenName.length < 4` check.
  public static let minimumNameLength = 4

  /// `App password names can only contain letters, numbers, spaces, hyphens, and underscores`
  public static let characterRuleMessage =
    "App password names can only contain letters, numbers, spaces, hyphens, and underscores"
  /// `App password names must be at least 4 characters long`
  public static let minimumLengthMessage =
    "App password names must be at least 4 characters long"
  /// `App password name must be unique`
  public static let uniquenessMessage = "App password name must be unique"

  /// Whether a raw field value satisfies the character rule. An empty field is
  /// allowed, because RN falls back to the generated name.
  public static func hasValidCharacters(_ name: String) -> Bool {
    name.range(of: allowedNamePattern, options: .regularExpression) != nil
  }

  /// Resolves the name a submission will use: the trimmed field value, or the
  /// generated default when the field is blank.
  public static func chosenName(typed: String, generated: String) -> String {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? generated : trimmed
  }

  /// Validates a submission, in RN's order (length, then uniqueness).
  ///
  /// The character rule is deliberately not re-checked here: RN checks it
  /// continuously for display and lets the length/uniqueness checks own the
  /// submit path. A caller that wants the display error uses
  /// ``displayError(typed:)``.
  public static func validate(
    typed: String,
    generated: String,
    existingNames: [String]
  ) -> AppPasswordValidationOutcome {
    let chosen = chosenName(typed: typed, generated: generated)
    if chosen.count < minimumNameLength {
      return .invalid(message: minimumLengthMessage)
    }
    if existingNames.contains(chosen) {
      return .invalid(message: uniquenessMessage)
    }
    return .valid(name: chosen)
  }

  /// The display error for the current field value, or nil.
  public static func displayError(typed: String) -> String? {
    hasValidCharacters(typed) ? nil : characterRuleMessage
  }
}

/// The name suggestions the create form pre-fills.
///
/// Port of `useRandomName` in `AddAppPasswordDialog.tsx`: a random entry from
/// the `shadesOfBlue` list, chosen once per dialog open. The list is
/// reproduced verbatim; the index is injectable so tests are deterministic.
public enum AppPasswordNameSuggestions {
  /// The `shadesOfBlue` list, in source order.
  public static let shadesOfBlue: [String] = [
    "AliceBlue", "Aqua", "Aquamarine", "Azure", "BabyBlue", "Blue", "BlueViolet",
    "CadetBlue", "CornflowerBlue", "Cyan", "DarkBlue", "DarkCyan", "DarkSlateBlue",
    "DeepSkyBlue", "DodgerBlue", "ElectricBlue", "LightBlue", "LightCyan",
    "LightSkyBlue", "LightSteelBlue", "MediumAquaMarine", "MediumBlue",
    "MediumSlateBlue", "MidnightBlue", "Navy", "PowderBlue", "RoyalBlue", "SkyBlue",
    "SlateBlue", "SteelBlue", "Teal", "Turquoise",
  ]

  /// The suggestion at an index, wrapping into range. Zero picks the first.
  public static func suggestion(at index: Int) -> String {
    guard !shadesOfBlue.isEmpty else { return "" }
    let wrapped = ((index % shadesOfBlue.count) + shadesOfBlue.count) % shadesOfBlue.count
    return shadesOfBlue[wrapped]
  }
}
