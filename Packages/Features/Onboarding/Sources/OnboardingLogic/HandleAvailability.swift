import ATProtoClient
import Foundation
import Lexicons

/// The answer to a handle-availability check.
public enum HandleAvailability: Sendable, Equatable {
  /// The handle can be claimed.
  case available
  /// The handle is taken. Carries the server's suggestions, when it offered
  /// any.
  case unavailable(suggestions: [String])

  /// Whether the handle can be claimed.
  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }
}

/// Checks whether a handle can be claimed.
///
/// Port of `checkHandleAvailability` in `state/queries/handle-availability.ts`.
/// Two paths, because the entryway and a third-party PDS answer differently:
///
/// - When the target service **is** the Bluesky entryway, the entryway has a
///   dedicated `com.atproto.temp.checkHandleAvailability` that also returns
///   suggestions. This is the path the RN signup handle step uses.
/// - When the target service is some other PDS, that endpoint does not exist,
///   so RN falls back to a public-appview `com.atproto.identity.resolveHandle`:
///   a handle that resolves is taken, one that does not is available.
///
/// Both paths are reproduced. Note the fallback cannot produce suggestions, so
/// ``HandleAvailability/unavailable(suggestions:)`` carries an empty list
/// there - which is also what the RN UI shows.
public protocol HandleAvailabilityService: Sendable {
  /// Checks a handle against the given service.
  func checkHandleAvailability(handle: String) async throws -> HandleAvailability
}

/// Which strategy a ``LiveHandleAvailabilityService`` uses.
public enum HandleAvailabilityStrategy: Sendable, Equatable {
  /// `com.atproto.temp.checkHandleAvailability` against the entryway.
  case entryway
  /// `com.atproto.identity.resolveHandle` against the public appview.
  case resolveHandle
}

/// The live implementation.
///
/// The client is supplied by the caller because the two strategies target
/// different hosts and neither is the user's own PDS: RN uses a one-off
/// service client for the entryway and a public-appview client for the
/// fallback. Both are unauthenticated reads.
public struct LiveHandleAvailabilityService: HandleAvailabilityService {
  private let strategy: HandleAvailabilityStrategy
  private let client: XrpcClient
  /// The birth date and email the entryway uses to shape suggestions.
  private let birthDate: String?
  private let email: String?

  /// Creates the service.
  public init(
    strategy: HandleAvailabilityStrategy,
    client: XrpcClient,
    birthDate: String? = nil,
    email: String? = nil
  ) {
    self.strategy = strategy
    self.client = client
    self.birthDate = birthDate
    self.email = email
  }

  /// The strategy to use for a target service.
  ///
  /// The entryway is recognized by its DID. Everything else takes the
  /// resolve-handle fallback.
  public static func strategy(forServiceDID did: String) -> HandleAvailabilityStrategy {
    did == OnboardingConstants.blueskyServiceDID ? .entryway : .resolveHandle
  }

  public func checkHandleAvailability(handle: String) async throws -> HandleAvailability {
    switch strategy {
    case .entryway:
      return try await checkViaEntryway(handle)
    case .resolveHandle:
      return try await checkViaResolveHandle(handle)
    }
  }

  private func checkViaEntryway(_ handle: String) async throws -> HandleAvailability {
    let output: Com.Atproto.TempCheckHandleAvailability_Output = try await client.get(
      "com.atproto.temp.checkHandleAvailability",
      params: [
        ("handle", handle), ("birthDate", birthDate), ("email", email),
      ])
    switch output.result {
    case .tempCheckHandleAvailabilityResultAvailable:
      return .available
    case .tempCheckHandleAvailabilityResultUnavailable(let unavailable):
      return .unavailable(suggestions: unavailable.suggestions.map(\.handle.rawValue))
    case ._other:
      // RN throws on an unrecognized result shape rather than guessing.
      throw OnboardingError.unexpected(
        message: "Unexpected result of `checkHandleAvailability`", underlying: nil)
    }
  }

  private func checkViaResolveHandle(_ handle: String) async throws -> HandleAvailability {
    do {
      let output: Com.Atproto.IdentityResolveHandle_Output = try await client.get(
        "com.atproto.identity.resolveHandle", params: [("handle", handle)])
      if !output.did.rawValue.isEmpty {
        return .unavailable(suggestions: [])
      }
    } catch {
      // RN swallows every failure here and reports the handle as available:
      // resolution failing is the expected signal that nothing holds it.
      return .available
    }
    return .available
  }
}

extension OnboardingConstants {
  /// `BSKY_SERVICE_DID` from `lib/constants.ts`.
  public static let blueskyServiceDID = "did:web:bsky.social"
  /// `BSKY_SERVICE` from `lib/constants.ts`.
  public static let blueskyService = "https://bsky.social"
  /// `PUBLIC_BSKY_SERVICE` from `lib/constants.ts`.
  public static let publicBlueskyService = "https://public.api.bsky.app"
}
