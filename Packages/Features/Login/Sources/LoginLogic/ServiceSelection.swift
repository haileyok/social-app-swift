import ATProtoClient
import Domain
import Foundation

/// How the current form reached its service decision.
///
/// Port of the `HostingProviderState` union in `state/queries/pds-detection.ts`.
public enum HostingProviderState: Sendable, Equatable {
  /// An email or bare username: nothing to detect, the default service is used.
  case idle
  /// The identifier is an email.
  case email
  /// A plausible handle, but the debounce has not settled on it yet.
  case detecting
  /// The handle resolved to a PDS advertised by its DID document.
  case detected(pdsUrl: String)
  /// The user chose a server by hand; detection is bypassed.
  case overridden(pdsUrl: String)
  /// The identifier resolved, but to no usable PDS.
  case unresolved
  /// Resolution failed with a transient (network) error.
  case error
}

/// The service a sign-in attempt should target, resolved from the identifier
/// plus any manual override.
///
/// Ports `useHostingProvider` from `state/queries/pds-detection.ts`. The caller
/// owns the lookup of the DID document (see ``PDSEndpointLookup``); this type
/// owns the decision logic that turns an identifier and an optional lookup
/// result into a state and a service URL.
public struct ServiceSelection: Sendable, Equatable {
  /// The default service, i.e. Bluesky Social.
  public let defaultService: String
  /// A manually chosen service, when the user overrode detection.
  public let override: String?
  /// The identifier currently typed, verbatim.
  public let identifier: String
  /// Whether the debounce has settled on `identifier`.
  public let isDebounceSettled: Bool
  /// The lookup result for the settled identifier.
  public let lookup: PDSEndpointLookup

  public init(
    identifier: String,
    defaultService: String = LoginConstants.defaultService,
    override: String? = nil,
    isDebounceSettled: Bool = true,
    lookup: PDSEndpointLookup = .notAttempted
  ) {
    self.identifier = identifier
    self.defaultService = defaultService
    self.override = override
    self.isDebounceSettled = isDebounceSettled
    self.lookup = lookup
  }

  /// The detection state, given the current inputs.
  public var state: HostingProviderState {
    if let override {
      return .overridden(pdsUrl: override)
    }
    let normalized = LoginIdentifier.normalize(identifier)
    if LoginIdentifier.isEmail(normalized) {
      return .email
    }
    if !LoginIdentifier.isPlausibleHandle(normalized) {
      return .idle
    }
    /*
     * The identifier changed but the debounce has not caught up, so any lookup
     * result belongs to the previous value. Report `detecting` rather than a
     * stale `detected`.
     */
    if !isDebounceSettled {
      return .detecting
    }
    switch lookup {
    case .notAttempted:
      return .detecting
    case .pending:
      return .detecting
    case .failed(let isNetwork):
      return isNetwork ? .error : .unresolved
    case .resolved(_, let pdsUrl):
      guard let pdsUrl else { return .unresolved }
      return .detected(pdsUrl: pdsUrl)
    }
  }

  /// The service to log in against right now.
  public var service: String {
    switch state {
    case .overridden(let pdsUrl), .detected(let pdsUrl):
      return pdsUrl
    case .idle, .email, .detecting, .unresolved, .error:
      return defaultService
    }
  }

  /// The designation label the form shows for the current service.
  public var niceHost: String {
    DomainURLShim.niceHostingUrl(service)
  }

  /// Resolves the service for a *submitted* identifier.
  ///
  /// This is `resolveService` from `useHostingProvider`: a manual override wins
  /// outright, emails and bare usernames take the default service, and a
  /// plausible handle is looked up. The caller supplies the lookup so network
  /// policy stays outside this value type.
  ///
  /// - Parameter lookupHandle: resolves a handle to its DID and PDS URL.
  ///   Implementations must throw only for genuine network errors; an
  ///   unresolvable handle returns `nil`.
  /// - Throws: the lookup's error, so a flaky connection fails the attempt
  ///   instead of silently sending a password to the default service.
  public func resolveService(
    identifier currentIdentifier: String,
    lookupHandle: (String) async throws -> ResolvedPDSEndpoint?
  ) async throws -> ServiceResolution {
    if let override {
      return ServiceResolution(service: override, did: nil)
    }
    let normalized = LoginIdentifier.normalize(currentIdentifier)
    let isEmail = LoginIdentifier.isEmail(normalized)
    let isPlausible = LoginIdentifier.isPlausibleHandle(normalized)
    if isEmail || !isPlausible {
      return ServiceResolution(service: defaultService, did: nil)
    }
    let resolved = try await lookupHandle(normalized)
    return ServiceResolution(
      service: resolved?.pdsUrl ?? defaultService,
      did: resolved?.did)
  }
}

/// The result of resolving an identifier to a service.
public struct ServiceResolution: Sendable, Equatable {
  /// The base URL to log in against.
  public let service: String
  /// The identifier's DID, when it resolved. `nil` for an override, an email,
  /// or a bare username.
  public let did: String?

  public init(service: String, did: String?) {
    self.service = service
    self.did = did
  }
}

/// A resolved identity and its declared PDS endpoint.
public struct ResolvedPDSEndpoint: Sendable, Equatable {
  /// The resolved DID.
  public let did: String
  /// The `#atproto_pds` endpoint from the DID document, when it declares one.
  public let pdsUrl: String?

  public init(did: String, pdsUrl: String?) {
    self.did = did
    self.pdsUrl = pdsUrl
  }
}

/// The outcome of asking what PDS an identifier belongs to.
public enum PDSEndpointLookup: Sendable, Equatable {
  /// No lookup has been made.
  case notAttempted
  /// A lookup is in flight.
  case pending
  /// The DID resolved; the endpoint may still be absent.
  case resolved(did: String, pdsUrl: String?)
  /// The identifier could not be resolved. `isNetwork` separates a transient
  /// failure (which must fail the login) from a genuinely unknown handle
  /// (which falls back to the default service).
  case failed(isNetwork: Bool)
}

/// Formatting helpers used by the flow's view-facing accessors.
enum DomainURLShim {
  static func niceHostingUrl(_ url: String) -> String {
    Domain.URLHelpers.toNiceHostingUrl(url)
  }
}
