import ATProtoClient
import Foundation
import LoginLogic

/**
 Resolves a handle to its DID and PDS endpoint, the way the RN sign-in screen
 does (`lookupHandle` in its service resolution).

 Two hops: `com.atproto.identity.resolveHandle` against the public appview,
 then the account's DID document (`plc.directory` for `did:plc`,
 `/.well-known/did.json` for `did:web`) to read the `#atproto_pds` endpoint.

 Contract required by ``LoginFlow``'s `lookupHandle`: throws only for genuine
 network failures (a flaky connection must fail the attempt rather than send a
 password to the wrong service); an unresolvable handle returns `nil` so the
 flow falls back to the default service.
 */
enum HandleResolver {

  /** Resolves `handle`, or nil when the handle does not resolve. */
  static func resolve(
    _ handle: String, transport: HTTPTransport
  ) async throws -> ResolvedPDSEndpoint? {
    // 1. Handle -> DID through the public appview.
    let did: String
    do {
      let response = try await transport.send(
        method: "GET",
        url: "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle?handle=\(urlEncoded(handle))",
        headers: [:], body: nil)
      guard response.status == 200,
        let json = try? JSONDecoder().decode(ResolveHandleBody.self, from: response.body),
        !json.did.isEmpty
      else { return nil }
      did = json.did
    } catch {
      throw error
    }

    // 2. DID -> DID document -> #atproto_pds endpoint.
    let docURL: String
    if did.hasPrefix("did:plc:") {
      docURL = "https://plc.directory/\(did)"
    } else if did.hasPrefix("did:web:") {
      let host = String(did.dropFirst("did:web:".count))
      docURL = "https://\(host)/.well-known/did.json"
    } else {
      // Unknown method: the DID resolved but this client cannot read it.
      return ResolvedPDSEndpoint(did: did, pdsUrl: nil)
    }

    let response = try await transport.send(
      method: "GET", url: docURL, headers: [:], body: nil)
    guard response.status == 200,
      let doc = try? JSONDecoder().decode(DIDDocument.self, from: response.body)
    else {
      // The DID exists but its document is unreadable; log in against the
      // default service rather than blocking the attempt.
      return ResolvedPDSEndpoint(did: did, pdsUrl: nil)
    }
    let pds = doc.service.first { $0.id == "#atproto_pds" }?.serviceEndpoint
    return ResolvedPDSEndpoint(did: did, pdsUrl: pds)
  }

  private static func urlEncoded(_ raw: String) -> String {
    raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
  }

  private struct ResolveHandleBody: Decodable {
    let did: String
  }

  private struct DIDDocument: Decodable {
    let service: [Service]

    struct Service: Decodable {
      let id: String
      let serviceEndpoint: String
    }
  }
}
