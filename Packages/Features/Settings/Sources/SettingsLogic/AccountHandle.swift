import ATProtoClient
import Foundation
import Lexicons
import SwiftAtproto

/// The handle operations the account screens need.
///
/// Port of `state/queries/handle.ts` and `state/queries/handle-availability.ts`.
/// Three distinct reads/writes are involved, and they target three different
/// services, which is why they are separate protocol methods rather than one
/// multi-purpose call:
///
/// - `com.atproto.identity.updateHandle` - a PDS write against the account's
///   own host.
/// - `com.atproto.temp.checkHandleAvailability` - an entryway read, described
///   below.
/// - `com.atproto.identity.resolveHandle` - a public appview read, the
///   fallback for services that do not run the temp endpoint.
public protocol HandleService: Sendable {
  /// `com.atproto.identity.updateHandle`
  func updateHandle(_ handle: String) async throws
  /// Resolves a name/domain to its DID, for the custom-domain verification
  /// step. `com.atproto.identity.resolveHandle` against the public appview.
  func resolveHandle(_ handle: String) async throws -> String
}

/// The live ``HandleService``.
public struct LiveHandleService: HandleService {
  /// The account's own PDS.
  private let pds: XrpcClient
  /// The public appview, used for `resolveHandle`.
  private let appview: XrpcClient
  private let authorization: @Sendable () async throws -> String?

  public init(
    pds: XrpcClient,
    appview: XrpcClient,
    authorization: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    self.pds = pds
    self.appview = appview
    self.authorization = authorization
  }

  public func updateHandle(_ handle: String) async throws {
    let input = Com.Atproto.IdentityUpdateHandle_Input(
      handle: FormatString<Handle>(rawValue: handle))
    _ = try await pds.procedure(
      "com.atproto.identity.updateHandle", body: input,
      authorization: try await authorization()) as XrpcClient.EmptyResponse
  }

  public func resolveHandle(_ handle: String) async throws -> String {
    let output: Com.Atproto.IdentityResolveHandle_Output = try await appview.get(
      "com.atproto.identity.resolveHandle",
      params: [("handle", handle)],
      authorization: try await authorization())
    return output.did.rawValue
  }
}

/// Which page of the change-handle dialog is showing.
///
/// Port of the `page` state in `ChangeHandleDialog.tsx`: the dialog splits into
/// "pick a subdomain under your provider's domain" and "bring your own domain".
public enum ChangeHandlePage: String, Sendable, Equatable, CaseIterable {
  /// `provided-handle` - a subdomain of a domain the provider offers.
  case providedHandle
  /// `own-handle` - a domain the user controls.
  case ownHandle
}

/// How the user intends to prove they own their own domain.
///
/// Port of the `dnsPanel` boolean in `OwnHandlePage`.
public enum DomainVerificationMethod: String, Sendable, Equatable, CaseIterable {
  /// Put a `_atproto` TXT record in DNS.
  case dns
  /// Serve a text file from the domain.
  case file
}

/// The custom-domain verification result.
public enum DomainVerificationOutcome: Sendable, Equatable {
  /// The domain resolved to the signed-in account's DID.
  case verified
  /// The domain resolved to a different DID.
  case didMismatch(received: String)
  /// The domain could not be resolved at all.
  case unresolved
}

/// A field-level problem with the subdomain being typed.
///
/// Port of `IsValidHandle` in `lib/strings/handles.ts`: the RN screen reads
/// `handleChars`, `hyphenStartOrEnd` and `totalLength` to decide whether the
/// field is marked invalid. All three are carried here so the view can show the
/// same inline state.
public struct ServiceHandleValidation: Sendable, Equatable {
  /// `validateServiceHandle`'s `handleChars`: the full handle matches the
  /// handle regex and the name part contains no dot.
  public let handleChars: Bool
  /// The name does not start or end with a hyphen.
  public let hyphenStartOrEnd: Bool
  /// The name is at least 3 characters.
  public let frontLengthNotTooShort: Bool
  /// The name is at most 18 characters.
  public let frontLengthNotTooLong: Bool
  /// The full handle is at most 253 characters.
  public let totalLength: Bool

  /// Every check passed.
  public var overall: Bool {
    handleChars && hyphenStartOrEnd && frontLengthNotTooShort
      && frontLengthNotTooLong && totalLength
  }

  /// The three checks the RN screen actually uses for its red field state.
  ///
  /// The two length-on-the-name checks are enforced by the input's
  /// `maxLength`-style behaviour rather than by the field state, so they are
  /// available but not part of `isInvalid`.
  public var isInvalid: Bool {
    !handleChars || !hyphenStartOrEnd || !totalLength
  }
}

/// Handle validation and composition, ported from `lib/strings/handles.ts`.
public enum HandleRules {
  /// `MAX_SERVICE_HANDLE_LENGTH`.
  public static let maxServiceHandleLength = 18
  /// The maximum name length `makeValidHandle` truncates to.
  public static let maxHandleLength = 20
  /// The maximum full handle length, from the PDS handle rules.
  public static let maxTotalLength = 253
  /// The minimum name length.
  public static let minNameLength = 3

  /// The go implementation's regex, as used by `validateServiceHandle`.
  static let validatePattern =
    "^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\."
      + ")+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"

  /// `createFullHandle`: joins a name and a domain, trimming a trailing dot
  /// from the name and a leading dot from the domain.
  public static func createFullHandle(name: String, domain: String) -> String {
    var trimmedName = name
    while trimmedName.hasSuffix(".") { trimmedName.removeLast() }
    var trimmedDomain = domain
    while trimmedDomain.hasPrefix(".") { trimmedDomain.removeFirst() }
    return "\(trimmedName).\(trimmedDomain)"
  }

  /// `makeValidHandle`: truncates to 20 characters, lowercases, drops leading
  /// non-alphanumerics, and removes everything but `a-z0-9-`.
  public static func makeValidHandle(_ input: String) -> String {
    var value = input.count > maxHandleLength ? String(input.prefix(maxHandleLength)) : input
    value = value.lowercased()
    while let first = value.first, !(first.isLetter || first.isNumber) {
      value.removeFirst()
    }
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
    return String(value.filter { allowed.contains($0) })
  }

  /// `isInvalidHandle`: the sentinel handle the appview returns for an
  /// unresolvable actor.
  public static func isInvalidHandle(_ handle: String) -> Bool {
    handle == "handle.invalid"
  }

  /// `validateServiceHandle`: every per-field check for a name under a domain.
  public static func validateServiceHandle(
    _ name: String, userDomain: String
  ) -> ServiceHandleValidation {
    let fullHandle = createFullHandle(name: name, domain: userDomain)
    let matchesPattern =
      fullHandle.range(of: validatePattern, options: .regularExpression) != nil
    return ServiceHandleValidation(
      handleChars: name.isEmpty ? true : (matchesPattern && !name.contains(".")),
      hyphenStartOrEnd: !name.hasPrefix("-") && !name.hasSuffix("-"),
      frontLengthNotTooShort: name.count >= minNameLength,
      frontLengthNotTooLong: name.count <= maxServiceHandleLength,
      totalLength: fullHandle.count <= maxTotalLength)
  }
}

/// The outcome of a handle-availability check.
///
/// The same shape the Onboarding package uses, redeclared because
/// `SettingsLogic` must not depend on another feature package.
public enum HandleAvailabilityResult: Sendable, Equatable {
  /// The handle can be claimed.
  case available
  /// The handle is taken, with the server's suggestions when it offered any.
  case unavailable(suggestions: [String])
}

/// Checks whether a handle can be claimed, the way
/// `checkHandleAvailability` does.
///
/// Two strategies: the Bluesky entryway has a dedicated temp endpoint that also
/// returns suggestions; a third-party PDS does not, so RN falls back to
/// resolving the handle against the public appview. A handle that fails to
/// resolve is by definition available.
public protocol HandleAvailabilityChecking: Sendable {
  /// Checks a full handle against the configured service.
  func checkHandleAvailability(handle: String, serviceDID: String) async throws
    -> HandleAvailabilityResult
}

/// The live availability checker.
public struct LiveHandleAvailabilityChecker: HandleAvailabilityChecking {
  /// A client for the entryway (`https://bsky.social`).
  private let entryway: XrpcClient
  /// A client for the public appview (`https://public.api.bsky.app`).
  private let appview: XrpcClient
  /// The birth date the entryway uses to shape suggestions.
  private let birthDate: String?
  /// The email the entryway uses to shape suggestions.
  private let email: String?

  public init(
    entryway: XrpcClient,
    appview: XrpcClient,
    birthDate: String? = nil,
    email: String? = nil
  ) {
    self.entryway = entryway
    self.appview = appview
    self.birthDate = birthDate
    self.email = email
  }

  public func checkHandleAvailability(
    handle: String, serviceDID: String
  ) async throws -> HandleAvailabilityResult {
    if serviceDID == SettingsConstants.blueskyServiceDID {
      return try await checkViaEntryway(handle)
    }
    return try await checkViaResolveHandle(handle)
  }

  private func checkViaEntryway(_ handle: String) async throws -> HandleAvailabilityResult {
    let output: Com.Atproto.TempCheckHandleAvailability_Output = try await entryway.get(
      "com.atproto.temp.checkHandleAvailability",
      params: [("handle", handle), ("birthDate", birthDate), ("email", email)])
    switch output.result {
    case .tempCheckHandleAvailabilityResultAvailable:
      return .available
    case .tempCheckHandleAvailabilityResultUnavailable(let unavailable):
      return .unavailable(suggestions: unavailable.suggestions.map(\.handle.rawValue))
    case ._other:
      // RN throws on an unrecognized result shape rather than guessing.
      throw SettingsError.unexpected(
        message: "Unexpected result of `checkHandleAvailability`")
    }
  }

  private func checkViaResolveHandle(_ handle: String) async throws -> HandleAvailabilityResult {
    do {
      let output: Com.Atproto.IdentityResolveHandle_Output = try await appview.get(
        "com.atproto.identity.resolveHandle", params: [("handle", handle)])
      if !output.did.rawValue.isEmpty {
        return .unavailable(suggestions: [])
      }
    } catch {
      // Resolution failing is the expected signal that nothing holds the
      // handle, so every failure here means "available".
      return .available
    }
    return .available
  }
}
