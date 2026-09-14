import ATProtoClient
import Domain
import Foundation
import Lexicons

/// A described PDS, in the shape the sign-in screen needs.
public struct ServiceDescription: Sendable, Equatable {
  /// Domain suffixes usable in handles on this server.
  public let availableUserDomains: [String]
  /// The server's DID.
  public let did: String

  public init(availableUserDomains: [String], did: String) {
    self.availableUserDomains = availableUserDomains
    self.did = did
  }
}

/// Why a preflight `describeServer` check failed.
public enum ServiceResolutionError: Error, Sendable, Equatable {
  /// The address could not be parsed into a service URL at all.
  case invalidURL
  /// The host answered, but not like an atproto PDS.
  case notAPDS(underlying: XRPCErrorShape?)
  /// The host could not be reached.
  case unreachable(underlying: XRPCErrorShape?)
  /// The host answered with an unexpected failure.
  case failed(underlying: XRPCErrorShape?)

  /// The user-facing copy for this failure.
  public var message: String {
    switch self {
    case .invalidURL:
      LoginStrings.invalidServiceUrl
    case .notAPDS, .unreachable, .failed:
      LoginStrings.unableToContactService
    }
  }

  /// The underlying lex error, when there was one.
  public var underlying: XRPCErrorShape? {
    switch self {
    case .invalidURL: nil
    case .notAPDS(let underlying), .unreachable(let underlying), .failed(let underlying):
      underlying
    }
  }
}

/// The outcome of resolving a service address.
public struct ResolvedService: Sendable, Equatable {
  /// The normalized base URL to log in against.
  public let service: String
  /// The server's description, when the preflight check succeeded.
  public let description: ServiceDescription?

  public init(service: String, description: ServiceDescription?) {
    self.service = service
    self.description = description
  }

  /// The handle domains the server advertises, for identifier completion.
  public var availableUserDomains: [String] {
    description?.availableUserDomains ?? []
  }
}

/// Preflight service checks: describeServer, plus address validation.
///
/// Port of `useServiceQuery` in `src/state/queries/service.ts` and the
/// `describeServer` preflight `LoginForm.tsx` performs before it will send a
/// password anywhere. Requests are unauthenticated and go to the host the user
/// typed, so there is no session or proxy involved.
public enum ServiceResolver {

  /// Describes a service address, mapping transport failures onto
  /// ``ServiceResolutionError``.
  ///
  /// The RN version queries react-query for this and surfaces
  /// "Unable to contact your service" on any error; the distinction between a
  /// dead host and a live host that is not a PDS is added here because the
  /// flow needs to tell the user which one they hit.
  public static func describe(
    service: String,
    transport: HTTPTransport,
    timeout: TimeInterval? = nil
  ) async throws -> ServiceDescription {
    guard let normalized = ServiceURL.normalize(service) else {
      throw ServiceResolutionError.invalidURL
    }
    let client = XrpcClient(
      baseURL: ServiceURL.requestBase(normalized), labelers: nil, transport: transport)
    do {
      let output: Com.Atproto.ServerDescribeServer_Output = try await client.get(
        "com.atproto.server.describeServer")
      return ServiceDescription(
        availableUserDomains: output.availableUserDomains,
        did: output.did.rawValue)
    } catch let error as XrpcError {
      let shape = XRPCErrorShapes.shape(fromXrpc: error)
      if error.status == 404 || error.status == 501 || error.status == 400 {
        throw ServiceResolutionError.notAPDS(underlying: shape)
      }
      if error.status < 0 {
        throw ServiceResolutionError.unreachable(underlying: shape)
      }
      throw ServiceResolutionError.failed(underlying: shape)
    } catch let error as URLError {
      let shape = XRPCErrorShape(
        name: "URLError", error: nil, message: error.localizedDescription)
      throw ServiceResolutionError.unreachable(underlying: shape)
    } catch {
      throw ServiceResolutionError.failed(
        underlying: XRPCErrorShapes.shape(from: error))
    }
  }

  /// Resolves a typed or entered address into a service, optionally running
  /// the preflight describe.
  ///
  /// Preflight is skipped when `requireDescription` is false, which is the
  /// state the form sits in while the user is still typing.
  public static func resolve(
    service: String,
    transport: HTTPTransport,
    requireDescription: Bool = true
  ) async throws -> ResolvedService {
    guard let normalized = ServiceURL.normalize(service) else {
      throw ServiceResolutionError.invalidURL
    }
    guard requireDescription else {
      return ResolvedService(service: normalized, description: nil)
    }
    let description = try await describe(
      service: normalized, transport: transport)
    return ResolvedService(service: normalized, description: description)
  }

}
