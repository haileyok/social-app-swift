import Foundation
import Lexicons
import SwiftAtproto
import Testing

@testable import SearchLogic

/// Builds minimal lexicon fixtures.
///
/// `record` on a starter-pack view is an `UnknownATPValue`, which has no
/// public `.object` case, so the fixture uses the `.any` case with a JSON value.
/// An empty JSON object, used as a starter-pack `record` fixture.
///
/// `UnknownATPValue.any` decodes its payload as a dictionary, so the fixture
/// must encode as `{}` rather than as a JSON string.
struct EmptyRecord: Codable, Hashable, Sendable {
  enum Keys: String, CodingKey { case unused }

  init() {}

  init(from decoder: any Decoder) throws {}

  func encode(to encoder: any Encoder) throws {
    _ = encoder.container(keyedBy: Keys.self)
  }
}

enum ProfileFixtures {
  static func profile(
    did: String,
    handle: String,
    displayName: String? = nil,
    following: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      did: try! FormatString<DID>(rawValue: did),
      displayName: displayName,
      handle: try! FormatString<Handle>(rawValue: handle),
      viewer: following.map {
        App.Bsky.ActorDefs_ViewerState(following: try! FormatString<ATURI>(rawValue: $0))
      }
    )
  }

  static func profileBasic(
    did: String, handle: String, displayName: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: try! FormatString<DID>(rawValue: did),
      displayName: displayName,
      handle: try! FormatString<Handle>(rawValue: handle)
    )
  }

  static func starterPack(uri: String) -> App.Bsky.GraphDefs_StarterPackView {
    App.Bsky.GraphDefs_StarterPackView(
      cid: try! FormatString<LexLink>(rawValue: "bafyreistarterpack"),
      creator: profileBasic(did: "did:plc:creator", handle: "creator.test"),
      indexedAt: try! FormatString<Date>(rawValue: "2024-01-01T00:00:00Z"),
      record: .any(EmptyRecord()),
      uri: try! FormatString<ATURI>(rawValue: uri)
    )
  }

  static func generatorView(uri: String, did: String, name: String)
    -> App.Bsky.FeedDefs_GeneratorView {
    App.Bsky.FeedDefs_GeneratorView(
      cid: try! FormatString<LexLink>(rawValue: "bafyreigenerator"),
      creator: profile(did: "did:plc:creator", handle: "creator.test"),
      did: try! FormatString<DID>(rawValue: did),
      displayName: name,
      indexedAt: try! FormatString<Date>(rawValue: "2024-01-01T00:00:00Z"),
      uri: try! FormatString<ATURI>(rawValue: uri)
    )
  }

  static func trend(link: String, topic: String, displayName: String, category: String? = nil)
    -> App.Bsky.UnspeccedDefs_TrendView {
    App.Bsky.UnspeccedDefs_TrendView(
      actors: [],
      category: category,
      displayName: displayName,
      link: link,
      postCount: 1,
      startedAt: try! FormatString<Date>(rawValue: "2024-01-01T00:00:00Z"),
      topic: topic
    )
  }

  static func trendingTopic(link: String, topic: String, displayName: String)
    -> App.Bsky.UnspeccedDefs_TrendingTopic {
    App.Bsky.UnspeccedDefs_TrendingTopic(displayName: displayName, link: link, topic: topic)
  }
}

/// Records every call and replays scripted responses.
///
/// The response queue is keyed by NSID, so a test can script one response per
/// endpoint and let the feature drive itself. Each recorded call keeps the
/// method, encoded params and headers, which is what the param-table tests
/// assert against.
actor FakeSearchClient: SearchXRPCCalling {
  struct Call: Sendable {
    let method: String
    let params: [(String, String?)]
    let headers: [String: String]
  }

  private var responses: [String: [Result<Data, any Error>]] = [:]
  private(set) var calls: [Call] = []

  func enqueue<Output: Encodable>(_ method: String, _ value: Output) throws {
    let data = try JSONEncoder().encode(value)
    responses[method, default: []].append(.success(data))
  }

  func enqueueFailure(_ method: String, _ error: any Error) {
    responses[method, default: []].append(.failure(error))
  }

  nonisolated func get<Output: Decodable & Sendable>(
    _ method: String,
    params: [(String, String?)],
    headers: [String: String]
  ) async throws -> Output {
    let data = try await recordAndPop(method: method, params: params, headers: headers)
    return try JSONDecoder().decode(Output.self, from: data)
  }

  private func recordAndPop(
    method: String, params: [(String, String?)], headers: [String: String]
  ) throws -> Data {
    calls.append(Call(method: method, params: params, headers: headers))
    guard var queue = responses[method], !queue.isEmpty else {
      throw FakeSearchClientError.noScriptedResponse(method)
    }
    let next = queue.removeFirst()
    responses[method] = queue
    return try next.get()
  }

  /// The params of the last call to `method`, as a dictionary for assertions.
  func lastParams(for method: String) -> [String: String] {
    guard let call = calls.last(where: { $0.method == method }) else { return [:] }
    var dict: [String: String] = [:]
    for (name, value) in call.params {
      if let value { dict[name] = value }
    }
    return dict
  }

  func calls(for method: String) -> [Call] {
    calls.filter { $0.method == method }
  }

  func recordedCount(for method: String) -> Int {
    calls.count { $0.method == method }
  }
}

enum FakeSearchClientError: Error, Equatable {
  case noScriptedResponse(String)
}
