import Foundation
import Persistence

/// Conversion between the live `SessionData` and the persisted account shape.
///
/// Port of `src/state/session/session-data.ts`.
public enum SessionAccountMapping {
  /// The Bluesky-hosted service, used to decide `isSelfHosted`.
  public static let bskyService = "https://bsky.social"

  /// Builds the persisted account snapshot from live session data.
  ///
  /// `storedPdsUrl` is a previously persisted PDS endpoint, used when the
  /// session has no did document. The PDS URL never falls back to the login
  /// service: a self-hosted account's login service is not necessarily its
  /// data host, and pinning to the wrong one would misroute requests.
  public static func account(
    from session: SessionData?,
    service: String,
    storedPdsUrl: String? = nil
  ) -> PersistedAccount? {
    guard let session else { return nil }
    let normalizedService = normalizeURL(service)
    let pdsUrl = extractPdsEndpoint(session.didDoc) ?? storedPdsUrl
    return PersistedAccount(
      service: normalizedService,
      did: session.did,
      handle: session.handle,
      email: session.email,
      emailConfirmed: session.emailConfirmed ?? false,
      emailAuthFactor: session.emailAuthFactor ?? false,
      refreshJwt: session.refreshJwt,
      accessJwt: session.accessJwt,
      signupQueued: JWT.isSignupQueued(session.accessJwt),
      active: session.active,
      status: nil,
      pdsUrl: pdsUrl.map(normalizeURL),
      isSelfHosted: !normalizedService.hasPrefix(bskyService))
  }

  /// Builds `SessionData` for constructing a `PasswordSession` from a stored
  /// account.
  ///
  /// Empty tokens (rather than nil) match the RN behavior; `PasswordSession`
  /// treats them as expired and takes the refresh path.
  public static func sessionData(from account: PersistedAccount) -> SessionData {
    SessionData(
      service: account.service,
      did: account.did,
      handle: account.handle,
      accessJwt: account.accessJwt ?? "",
      refreshJwt: account.refreshJwt ?? "",
      email: account.email,
      emailConfirmed: account.emailConfirmed,
      emailAuthFactor: account.emailAuthFactor,
      active: account.active ?? true,
      didDoc: nil)
  }

  /// Whether the account's access token is missing or expired.
  public static func isExpired(_ account: PersistedAccount, now: Date = Date()) -> Bool {
    guard let accessJwt = account.accessJwt, !accessJwt.isEmpty else { return true }
    return JWT.isExpired(accessJwt, now: now)
  }

  /// Whether the account's access token was issued for a queued signup.
  public static func isSignupQueued(_ account: PersistedAccount) -> Bool {
    guard let accessJwt = account.accessJwt else { return false }
    return JWT.isSignupQueued(accessJwt)
  }

  /// Normalizes a service URL the way the TS `new URL().toString()` does: a
  /// site with no path gains a trailing slash, so comparison and persistence
  /// are stable across writes.
  public static func normalizeURL(_ raw: String) -> String {
    guard !raw.isEmpty, var components = URLComponents(string: raw) else {
      return raw
    }
    if components.path.isEmpty {
      components.path = "/"
    }
    return components.string ?? raw
  }
}
