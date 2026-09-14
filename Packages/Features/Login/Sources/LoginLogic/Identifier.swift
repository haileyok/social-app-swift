import Domain
import Foundation

/// Constants the sign-in flow shares with the RN app.
public enum LoginConstants {
  /// `DEFAULT_SERVICE` / `BSKY_SERVICE` from `src/lib/constants.ts`.
  public static let defaultService = "https://bsky.social"
}

/// Identifier and service-URL handling, ported from the RN sign-in screens.
///
/// Two normalization rules live here because they must agree: the identifier
/// one from `pds-detection.ts` (which decides whether an identifier is an
/// email, a handle, or a DID) and the service-address one from
/// `ServerInput.tsx` (which decides what a typed PDS address means).
public enum LoginIdentifier {

  /// `normalizeIdentifier` from `pds-detection.ts`: trim, lowercase, strip a
  /// single leading `@`.
  ///
  /// Handles are routinely typed as `@alice.example.com`; without stripping
  /// the `@` the identifier looks like an email and hosting-provider
  /// detection is disabled. A real email has no leading `@`, so it still
  /// contains one after normalization and classifies correctly.
  public static func normalize(_ identifier: String) -> String {
    var value = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.hasPrefix("@") {
      value.removeFirst()
    }
    return value
  }

  /// Whether a normalized identifier is an email address.
  public static func isEmail(_ identifier: String) -> Bool {
    normalize(identifier).contains("@")
  }

  /// Whether an identifier could name a hosting provider.
  ///
  /// `isPlausibleHandle` in `pds-detection.ts`: non-empty, not an email, and
  /// either containing a `.` or being a DID. Bare usernames cannot resolve a
  /// PDS on their own, so they skip detection entirely.
  public static func isPlausibleHandle(_ identifier: String) -> Bool {
    let normalized = normalize(identifier)
    guard !normalized.isEmpty, !normalized.contains("@") else { return false }
    return normalized.contains(".") || normalized.hasPrefix("did:")
  }

  /// The identifier actually sent to `createSession`.
  ///
  /// A bare username on a server that advertises handle domains gets the first
  /// advertised domain appended (`createFullHandle` in `LoginForm.tsx`). An
  /// identifier that already ends with one of the advertised domains is left
  /// alone, and an identifier that is already an email or a DID never reaches
  /// this branch.
  public static func fullIdentifier(
    identifier: String, serviceProviderDomains: [String]
  ) -> String {
    let normalized = normalize(identifier)
    guard let domain = serviceProviderDomains.first, !domain.isEmpty,
      !normalized.contains("@"), !normalized.hasPrefix("did:"),
      !serviceProviderDomains.contains(where: { normalized.hasSuffix($0) })
    else {
      return normalized
    }
    let name = normalized.replacingOccurrences(
      of: #"\.+$"#, with: "", options: .regularExpression)
    let host = domain.replacingOccurrences(
      of: #"^\.+"#, with: "", options: .regularExpression)
    return "\(name).\(host)"
  }
}

/// The outcome of validating a typed service address.
public enum ServiceURLValidation: Sendable, Equatable {
  /// The address is usable; the associated value is its normalized form.
  case valid(String)
  /// Nothing was typed.
  case empty
  /// The address cannot be turned into a usable base URL.
  case invalid
}

/// Port of the address handling in `components/dialogs/ServerInput.tsx`.
public enum ServiceURL {

  /// Normalizes a typed PDS address into a base URL.
  ///
  /// `ServerInput.tsx` trims and lowercases, then adds a scheme: loopback
  /// addresses get `http://`, everything else `https://`. The trailing slash
  /// comes from the `new URL().toString()` behaviour that
  /// `SessionAccountMapping.normalizeURL` already implements on the session
  /// side, so the value stored here matches the value persisted there.
  ///
  /// Returns `nil` when no usable host can be derived.
  public static func normalize(_ raw: String) -> String? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty else { return nil }

    if !value.hasPrefix("http://") && !value.hasPrefix("https://") {
      value =
        (value == "localhost" || value.hasPrefix("localhost:"))
        ? "http://\(value)" : "https://\(value)"
    }

    guard let components = URLComponents(string: value),
      let host = components.host, !host.isEmpty
    else { return nil }

    // A bare `https://` parses with an empty host, handled above. Anything
    // with a scheme-specific action (mailto:, did:) is not a service address.
    guard components.scheme == "http" || components.scheme == "https" else { return nil }

    return SessionAccountMappingShim.normalizedTrailingSlash(value)
  }

  /// Classifies a typed address for the form's validation state.
  public static func validate(_ raw: String) -> ServiceURLValidation {
    if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .empty
    }
    guard let normalized = normalize(raw) else { return .invalid }
    return .valid(normalized)
  }

  /// Whether an address points at a Bluesky-operated PDS.
  ///
  /// Ported from `URLHelpers.isBlueskyHostedUrl`; used to decide whether a
  /// sign-in needs the "not operated by Bluesky" confirmation.
  public static func isBlueskyHosted(_ raw: String) -> Bool {
    URLHelpers.isBlueskyHostedUrl(normalize(raw) ?? raw)
  }

  /// The base URL to compose XRPC request paths onto.
  ///
  /// ``normalize(_:)`` keeps the trailing slash because that is what
  /// `new URL().toString()` produces and what the account store persists, but
  /// ``XrpcClient`` joins `baseURL + "/xrpc/" + method`, so a base with a
  /// trailing slash would request `//xrpc/...`. Requests therefore go through
  /// this form, which matches the un-slashed value the RN sign-in screen hands
  /// to `PasswordSession.login`.
  public static func requestBase(_ raw: String) -> String {
    guard let normalized = normalize(raw),
      var components = URLComponents(string: normalized)
    else { return raw }
    while components.path.hasSuffix("/") {
      components.path.removeLast()
    }
    return components.string ?? normalized
  }
}

/// Indirection so the trailing-slash rule has exactly one implementation.
///
/// `SessionAccountMapping.normalizeURL` is internal to ATProtoClient, so the
/// same rule is restated for the pre-session form. It is the `new URL()`
/// behaviour: a URL with no path gains `/`.
enum SessionAccountMappingShim {
  static func normalizedTrailingSlash(_ raw: String) -> String {
    guard var components = URLComponents(string: raw) else { return raw }
    if components.path.isEmpty {
      components.path = "/"
    }
    return components.string ?? raw
  }
}
