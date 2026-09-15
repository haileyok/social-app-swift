import ATProtoClient
import Foundation
import Lexicons

/// The live ``StarterPackXrpc`` over an appview client and a PDS client.
///
/// Both clients are built by `ATProtoClient.SessionClients`: the appview client
/// already carries the `atproto-proxy: <did>#bsky_appview` header and the
/// acceptor labelers, and the PDS client targets the account's host. Nothing
/// here re-implements routing.
public struct LiveStarterPackXrpc: StarterPackXrpc {
  /// The appview client, for reads.
  public let appview: XrpcClient
  /// The PDS client, for repo writes.
  public let pds: XrpcClient
  /// Authorization token, forwarded per request.
  public let authorization: String?

  /// Creates the live surface.
  public init(appview: XrpcClient, pds: XrpcClient, authorization: String? = nil) {
    self.appview = appview
    self.pds = pds
    self.authorization = authorization
  }

  // MARK: - Reads

  public func getStarterPack(uri: String) async throws -> App.Bsky.GraphDefs_StarterPackView {
    let output: App.Bsky.GraphGetStarterPack_Output = try await appview.get(
      App.Bsky.GraphGetStarterPack.id, params: [("starterPack", uri)],
      authorization: authorization)
    return output.starterPack
  }

  public func getStarterPacks(
    uris: [String]
  ) async throws -> [App.Bsky.GraphDefs_StarterPackViewBasic] {
    let output: App.Bsky.GraphGetStarterPacks_Output = try await appview.get(
      App.Bsky.GraphGetStarterPacks.id, params: uris.map { ("uris", $0) },
      authorization: authorization)
    return output.starterPacks
  }

  public func getActorStarterPacks(
    actor: String, cursor: String?, limit: Int
  ) async throws -> StarterPackBasicPage {
    let output: App.Bsky.GraphGetActorStarterPacks_Output = try await appview.get(
      App.Bsky.GraphGetActorStarterPacks.id,
      params: [
        ("actor", actor), ("cursor", cursor), ("limit", String(limit)),
      ],
      authorization: authorization)
    return StarterPackBasicPage(cursor: output.cursor, starterPacks: output.starterPacks)
  }

  public func getStarterPacksWithMembership(
    actor: String, cursor: String?, limit: Int
  ) async throws -> StarterPackWithMembershipPage {
    let output: App.Bsky.GraphGetStarterPacksWithMembership_Output = try await appview.get(
      App.Bsky.GraphGetStarterPacksWithMembership.id,
      params: [
        ("actor", actor), ("cursor", cursor), ("limit", String(limit)),
      ],
      authorization: authorization)
    return StarterPackWithMembershipPage(
      cursor: output.cursor, packs: output.starterPacksWithMembership)
  }

  public func searchStarterPacks(
    query: String, cursor: String?, limit: Int
  ) async throws -> StarterPackViewPage {
    let output: App.Bsky.GraphSearchStarterPacksV2_Output = try await appview.get(
      App.Bsky.GraphSearchStarterPacksV2.id,
      params: [
        ("q", query), ("cursor", cursor), ("limit", String(limit)),
      ],
      authorization: authorization)
    return StarterPackViewPage(cursor: output.cursor, starterPacks: output.starterPacks)
  }

  public func getList(
    list: String, cursor: String?, limit: Int
  ) async throws -> StarterPackListMembersPage {
    let output: App.Bsky.GraphGetList_Output = try await appview.get(
      App.Bsky.GraphGetList.id,
      params: [
        ("list", list), ("cursor", cursor), ("limit", String(limit)),
      ],
      authorization: authorization)
    return StarterPackListMembersPage(cursor: output.cursor, items: output.items)
  }

  // MARK: - Writes

  public func applyWrites(repo: String, writes: [StarterPackWrite]) async throws {
    guard !writes.isEmpty else { return }
    let body = try JSONEncoder().encode([
      "repo": StarterPackJSON.string(repo),
      "writes": StarterPackJSON.array(writes),
    ])
    try await post("com.atproto.repo.applyWrites", body: body)
  }

  public func createRecord(
    repo: String, collection: String, rkey: String?, record: StarterPackJSON
  ) async throws -> StarterPackRecordRef {
    var payload: [String: StarterPackJSON] = [
      "repo": .string(repo),
      "collection": .string(collection),
      "record": record,
    ]
    if let rkey { payload["rkey"] = .string(rkey) }
    let body = try JSONEncoder().encode(payload)
    let response = try await post("com.atproto.repo.createRecord", body: body)
    return try Self.decodeRecordRef(response)
  }

  public func putRecord(
    repo: String, collection: String, rkey: String, record: StarterPackJSON
  ) async throws -> StarterPackRecordRef {
    let body = try JSONEncoder().encode([
      "repo": StarterPackJSON.string(repo),
      "collection": StarterPackJSON.string(collection),
      "rkey": StarterPackJSON.string(rkey),
      "record": record,
    ])
    let response = try await post("com.atproto.repo.putRecord", body: body)
    return try Self.decodeRecordRef(response)
  }

  public func deleteRecord(repo: String, collection: String, rkey: String) async throws {
    let body = try JSONEncoder().encode([
      "repo": StarterPackJSON.string(repo),
      "collection": StarterPackJSON.string(collection),
      "rkey": StarterPackJSON.string(rkey),
    ])
    _ = try await post("com.atproto.repo.deleteRecord", body: body)
  }

  // MARK: - Internals

  /// POSTs a JSON body to the PDS and returns the response bytes.
  private func post(_ method: String, body: Data) async throws -> Data {
    let response = try await pds.rawPost(
      method, body: body, contentType: "application/json",
      authorization: authorization)
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers, data: response.body)
    }
    return response.body
  }

  /// Reads the `{uri, cid}` pair a repo write returns.
  private static func decodeRecordRef(_ data: Data) throws -> StarterPackRecordRef {
    guard let payload = try? JSONDecoder().decode([String: StarterPackJSON].self, from: data) else {
      return StarterPackRecordRef(uri: "")
    }
    return StarterPackRecordRef(
      uri: payload["uri"]?.stringValue ?? "",
      cid: payload["cid"]?.stringValue ?? "")
  }
}
