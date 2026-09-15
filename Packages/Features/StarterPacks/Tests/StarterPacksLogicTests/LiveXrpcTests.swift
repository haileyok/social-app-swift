import ATProtoClient
import Foundation
import Lexicons
import SwiftAtproto
import Testing

@testable import StarterPacksLogic

/// Records every request a live ``StarterPackXrpc`` makes.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
  struct Received: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?
  }

  private let lock = NSLock()
  private var _received: [Received] = []
  private var responseBody: Data

  init(responseBody: Data = Data("{}".utf8)) {
    self.responseBody = responseBody
  }

  var received: [Received] { lock.withLock { _received } }

  /// The body of the last request, decoded as JSON.
  var lastJSON: [String: StarterPackJSON]? {
    guard let body = received.last?.body else { return nil }
    return try? JSONDecoder().decode([String: StarterPackJSON].self, from: body)
  }

  /// The query of the last request, as a dictionary.
  var lastQuery: [String: String] {
    guard let url = received.last?.url, let components = URLComponents(string: url) else {
      return [:]
    }
    var out: [String: String] = [:]
    for item in components.queryItems ?? [] { out[item.name] = item.value }
    return out
  }

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    lock.withLock {
      _received.append(Received(method: method, url: url, headers: headers, body: body))
    }
    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: responseBody)
  }
}

/// Asserts the live surface emits the params, bodies and methods RN emits.
@Suite("LiveStarterPackXrpc")
struct LiveStarterPackXrpcTests {
  private let appviewURL = "https://api.bsky.app"
  private let pdsURL = "https://pds.example.com"

  private func makeXrpc(transport: RecordingTransport) -> LiveStarterPackXrpc {
    LiveStarterPackXrpc(
      appview: XrpcClient(
        baseURL: appviewURL, proxyService: "did:web:api.bsky.app#bsky_appview",
        transport: transport),
      pds: XrpcClient(baseURL: pdsURL, transport: transport),
      authorization: "Bearer token")
  }

  private let emptyPack = Data(
    #"{"starterPack":{"cid":"cid","creator":{"did":"did:plc:a","handle":"a.test"},"indexedAt":"2026-08-31T00:00:00.000Z","record":{"$type":"app.bsky.graph.starterpack","createdAt":"2026-08-31T00:00:00.000Z","list":"at://did:plc:a/app.bsky.graph.list/1","name":"Pack"},"uri":"at://did:plc:a/app.bsky.graph.starterpack/1"}}"#
      .utf8)

  @Test("getStarterPack reads the appview with the pack param and proxy header")
  func getStarterPack() async throws {
    let transport = RecordingTransport(responseBody: emptyPack)
    let xrpc = makeXrpc(transport: transport)
    let view = try await xrpc.getStarterPack(uri: "at://did:plc:a/app.bsky.graph.starterpack/1")

    #expect(view.uri.rawValue == "at://did:plc:a/app.bsky.graph.starterpack/1")
    #expect(transport.received.count == 1)
    #expect(transport.received[0].method == "GET")
    #expect(transport.received[0].url.contains("app.bsky.graph.getStarterPack"))
    #expect(transport.received[0].url.contains("starterPack=at"))
    #expect(transport.received[0].headers["atproto-proxy"] == "did:web:api.bsky.app#bsky_appview")
  }

  @Test("getStarterPacks sends one uris parameter per pack")
  func getStarterPacks() async throws {
    let transport = RecordingTransport(responseBody: Data(#"{"starterPacks":[]}"#.utf8))
    let xrpc = makeXrpc(transport: transport)
    _ = try await xrpc.getStarterPacks(uris: ["at://did:plc:a/x/1", "at://did:plc:a/x/2"])

    #expect(transport.received[0].url.contains("app.bsky.graph.getStarterPacks"))
    let components = URLComponents(string: transport.received[0].url)
    let uris = (components?.queryItems ?? []).filter { $0.name == "uris" }
    #expect(uris.count == 2)
  }

  @Test("getActorStarterPacks sends actor, cursor and limit")
  func getActorStarterPacks() async throws {
    let transport = RecordingTransport(responseBody: Data(#"{"starterPacks":[]}"#.utf8))
    let xrpc = makeXrpc(transport: transport)
    _ = try await xrpc.getActorStarterPacks(actor: "did:plc:a", cursor: "c1", limit: 10)

    #expect(transport.received[0].url.contains("app.bsky.graph.getActorStarterPacks"))
    #expect(transport.lastQuery["actor"] == "did:plc:a")
    #expect(transport.lastQuery["cursor"] == "c1")
    #expect(transport.lastQuery["limit"] == "10")
  }

  @Test("a nil cursor is omitted from the query")
  func getActorStarterPacksNoCursor() async throws {
    let transport = RecordingTransport(responseBody: Data(#"{"starterPacks":[]}"#.utf8))
    let xrpc = makeXrpc(transport: transport)
    _ = try await xrpc.getActorStarterPacks(actor: "did:plc:a", cursor: nil, limit: 10)
    #expect(transport.lastQuery["cursor"] == nil)
  }

  @Test("getStarterPacksWithMembership sends actor, cursor and limit")
  func getStarterPacksWithMembership() async throws {
    let transport = RecordingTransport(responseBody: Data(#"{"starterPacksWithMembership":[]}"#.utf8))
    let xrpc = makeXrpc(transport: transport)
    _ = try await xrpc.getStarterPacksWithMembership(actor: "did:plc:a", cursor: nil, limit: 10)

    #expect(transport.received[0].url.contains("app.bsky.graph.getStarterPacksWithMembership"))
    #expect(transport.lastQuery["actor"] == "did:plc:a")
    #expect(transport.lastQuery["limit"] == "10")
  }

  @Test("searchStarterPacks uses searchStarterPacksV2 with q")
  func searchStarterPacks() async throws {
    let transport = RecordingTransport(responseBody: Data(#"{"starterPacks":[]}"#.utf8))
    let xrpc = makeXrpc(transport: transport)
    _ = try await xrpc.searchStarterPacks(query: "art", cursor: nil, limit: 25)

    #expect(transport.received[0].url.contains("app.bsky.graph.searchStarterPacksV2"))
    #expect(transport.lastQuery["q"] == "art")
    #expect(transport.lastQuery["limit"] == "25")
  }

  @Test("getList sends list, cursor and limit")
  func getList() async throws {
    let transport = RecordingTransport(
      responseBody: Data(
        #"{"items":[],"list":{"cid":"cid","creator":{"did":"did:plc:a","handle":"a.test"},"indexedAt":"2026-08-31T00:00:00.000Z","name":"L","purpose":"app.bsky.graph.defs#referencelist","uri":"at://did:plc:a/app.bsky.graph.list/1"}}"#
          .utf8))
    let xrpc = makeXrpc(transport: transport)
    _ = try await xrpc.getList(list: "at://did:plc:a/app.bsky.graph.list/1", cursor: "c", limit: 50)

    #expect(transport.received[0].url.contains("app.bsky.graph.getList"))
    #expect(transport.lastQuery["list"] == "at://did:plc:a/app.bsky.graph.list/1")
    #expect(transport.lastQuery["cursor"] == "c")
    #expect(transport.lastQuery["limit"] == "50")
  }

  // MARK: - Writes

  @Test("applyWrites posts a repo and a writes array to the PDS")
  func applyWrites() async throws {
    let transport = RecordingTransport(responseBody: Data("{}".utf8))
    let xrpc = makeXrpc(transport: transport)
    let write = StarterPackRecords.listItemDeleteWrite(rkey: "r1")
    try await xrpc.applyWrites(repo: "did:plc:a", writes: [write])

    #expect(transport.received[0].method == "POST")
    #expect(transport.received[0].url.contains("com.atproto.repo.applyWrites"))
    // Writes go to the PDS, not the appview: no proxy header.
    #expect(transport.received[0].url.hasPrefix(pdsURL))
    #expect(transport.received[0].headers["atproto-proxy"] == nil)
    #expect(transport.lastJSON?["repo"]?.stringValue == "did:plc:a")
    #expect(
      transport.lastJSON?["writes"]?.arrayValue?.first.map(Fixtures.canonical)
        == Fixtures.canonical(write))
  }

  @Test("applyWrites with no writes makes no request")
  func applyWritesEmpty() async throws {
    let transport = RecordingTransport()
    let xrpc = makeXrpc(transport: transport)
    try await xrpc.applyWrites(repo: "did:plc:a", writes: [])
    #expect(transport.received.isEmpty)
  }

  @Test("createRecord posts repo, collection and record, and omits an absent rkey")
  func createRecord() async throws {
    let transport = RecordingTransport(
      responseBody: Data(#"{"cid":"cid1","uri":"at://did:plc:a/app.bsky.graph.list/1"}"#.utf8))
    let xrpc = makeXrpc(transport: transport)
    let record = StarterPackRecords.listRecord(
      name: "Pack", description: nil, descriptionFacets: nil, createdAt: "2026-08-31T00:00:00.000Z")
    let ref = try await xrpc.createRecord(
      repo: "did:plc:a", collection: "app.bsky.graph.list", rkey: nil, record: record)

    #expect(ref.uri == "at://did:plc:a/app.bsky.graph.list/1")
    #expect(ref.cid == "cid1")
    #expect(transport.lastJSON?["collection"]?.stringValue == "app.bsky.graph.list")
    #expect(transport.lastJSON?["rkey"] == nil)
    #expect(
      transport.lastJSON?["record"].map(Fixtures.canonical) == Fixtures.canonical(record))
  }

  @Test("createRecord includes an explicit rkey when given one")
  func createRecordWithRkey() async throws {
    let transport = RecordingTransport(responseBody: Data("{}".utf8))
    let xrpc = makeXrpc(transport: transport)
    _ = try await xrpc.createRecord(
      repo: "did:plc:a", collection: "app.bsky.graph.list", rkey: "3abc",
      record: .object([:]))
    #expect(transport.lastJSON?["rkey"]?.stringValue == "3abc")
  }

  @Test("putRecord posts the rkey and the record")
  func putRecord() async throws {
    let transport = RecordingTransport(
      responseBody: Data(#"{"cid":"cid2","uri":"at://did:plc:a/app.bsky.graph.starterpack/3abc"}"#.utf8))
    let xrpc = makeXrpc(transport: transport)
    let record = StarterPackRecords.editRecord(
      StarterPackRecords.StarterPackEditRecordInput(
        name: "Pack", description: nil, listURI: nil, feeds: [],
        createdAt: "2024-01-01T00:00:00.000Z", updatedAt: "2026-08-31T00:00:00.000Z"))
    let ref = try await xrpc.putRecord(
      repo: "did:plc:a", collection: "app.bsky.graph.starterpack", rkey: "3abc", record: record)

    #expect(ref.uri == "at://did:plc:a/app.bsky.graph.starterpack/3abc")
    #expect(transport.lastJSON?["rkey"]?.stringValue == "3abc")
    #expect(transport.lastJSON?["record"].map(Fixtures.canonical) == Fixtures.canonical(record))
  }

  @Test("deleteRecord posts repo, collection and rkey")
  func deleteRecord() async throws {
    let transport = RecordingTransport(responseBody: Data("{}".utf8))
    let xrpc = makeXrpc(transport: transport)
    try await xrpc.deleteRecord(
      repo: "did:plc:a", collection: "app.bsky.graph.list", rkey: "r1")

    #expect(transport.received[0].url.contains("com.atproto.repo.deleteRecord"))
    #expect(transport.lastJSON?["collection"]?.stringValue == "app.bsky.graph.list")
    #expect(transport.lastJSON?["rkey"]?.stringValue == "r1")
  }

  @Test("a non-2xx write response throws a mapped XRPC error")
  func writeFailure() async throws {
    final class FailingTransport: HTTPTransport, @unchecked Sendable {
      func send(
        method: String, url: String, headers: [String: String], body: Data?
      ) async throws -> HTTPResponse {
        HTTPResponse(
          status: 400,
          headers: ["Content-Type": "application/json"],
          body: Data(#"{"error":"InvalidRequest","message":"bad"}"#.utf8))
      }
    }
    let xrpc = LiveStarterPackXrpc(
      appview: XrpcClient(baseURL: appviewURL, transport: FailingTransport()),
      pds: XrpcClient(baseURL: pdsURL, transport: FailingTransport()))
    await #expect(throws: (any Error).self) {
      try await xrpc.applyWrites(
        repo: "did:plc:a", writes: [StarterPackRecords.listItemDeleteWrite(rkey: "r")])
    }
  }
}
