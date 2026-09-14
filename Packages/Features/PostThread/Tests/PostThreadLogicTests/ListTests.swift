import ATProtoClient
import Foundation
import Lexicons
import QueryStore
import Testing

@testable import PostThreadLogic

/// A transport that answers each request from a scripted page table and records
/// what was asked for, so a test can assert both pagination and the XRPC params.
///
/// The package deliberately does not reach into `TestSupport` (a placeholder),
/// so this is a package-local fake, in the same spirit as LoginLogic's
/// `ScriptedTransport`.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
  struct Received: Sendable {
    let method: String
    let url: String

    /// The query parameters, decoded from the url.
    var params: [String: String] {
      guard let components = URLComponents(string: url) else { return [:] }
      var out: [String: String] = [:]
      for item in components.queryItems ?? [] {
        out[item.name] = item.value ?? ""
      }
      return out
    }

    var methodName: String {
      url.split(separator: "/").last.map { String($0.split(separator: "?").first ?? "") } ?? ""
    }
  }

  private let lock = NSLock()
  private var _received: [Received] = []
  /// Pages keyed by the cursor they answer (`""` for the first page).
  private var pages: [String: [String: Any]]

  init(pages: [String: [String: Any]]) {
    self.pages = pages
  }

  var received: [Received] {
    withLock { _received }
  }

  /// A synchronous critical section.
  ///
  /// `NSLock.lock()` is annotated `noasync`, so it cannot be called directly
  /// from an async context; funnelling every use through this helper keeps
  /// `send` async and the locking correct (the same pattern LoginLogic uses).
  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    let request = Received(method: method, url: url)
    let cursor = URLComponents(string: url)?
      .queryItems?.first { $0.name == "cursor" }?.value ?? ""
    let page = withLock { () -> [String: Any]? in
      _received.append(request)
      return pages[cursor]
    }

    guard let page else {
      return HTTPResponse(
        status: 400, headers: [:],
        body: Data(#"{"error":"InvalidRequest","message":"no page"}"#.utf8))
    }
    let data = try JSONSerialization.data(withJSONObject: page)
    return HTTPResponse(
      status: 200, headers: ["content-type": "application/json"], body: data)
  }
}

/// A profile view JSON blob.
func profileJSON(_ did: String) -> [String: Any] {
  [
    "did": did,
    "handle": did.replacingOccurrences(of: "did:plc:", with: "") + ".test",
  ]
}

func postJSON(_ uri: String) -> [String: Any] {
  [
    "uri": uri,
    "cid": "bafy\(uri.hashValue)",
    "author": profileJSON("did:plc:author"),
    "indexedAt": "2026-01-01T00:00:00.000Z",
    "record": ["$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-01-01T00:00:00.000Z"],
  ]
}

/// The three derived lists: pagination, dedupe, keys and wire params.
///
/// Ports `state/queries/post-liked-by.ts`, `post-reposted-by.ts` and
/// `post-quotes.ts`, whose shared contract is a 30-item page with a cursor and
/// `getNextPageParam: lastPage => lastPage.cursor`.
@Suite("Post lists")
struct ListTests {
  static let uri = "at://did:plc:author/app.bsky.feed.post/abc"

  static func client(_ transport: HTTPTransport) -> XrpcClient {
    XrpcClient(
      baseURL: "https://public.api.bsky.app", proxyService: nil, labelers: nil,
      extraHeaders: [:], transport: transport)
  }

  // MARK: - Liked by

  @Test("likes paginate and flatten across pages")
  func likedByPagination() async throws {
    let transport = ScriptedTransport(pages: [
      "": [
        "uri": Self.uri,
        "likes": [
          ["actor": profileJSON("did:plc:a"), "createdAt": "2026-01-01T00:00:00.000Z", "indexedAt": "2026-01-01T00:00:00.000Z"],
          ["actor": profileJSON("did:plc:b"), "createdAt": "2026-01-01T00:00:00.000Z", "indexedAt": "2026-01-01T00:00:00.000Z"],
        ],
        "cursor": "page2",
      ],
      "page2": [
        "uri": Self.uri,
        "likes": [
          ["actor": profileJSON("did:plc:c"), "createdAt": "2026-01-01T00:00:00.000Z", "indexedAt": "2026-01-01T00:00:00.000Z"]
        ],
      ],
    ])

    let store = QueryStore()
    let query = LikedByQuery(
      store: store, client: Self.client(transport),
      args: .init(uri: Self.uri))

    let first = try await query.query.loadFirstPage()
    #expect(first.items.map(\.id) == ["did:plc:a", "did:plc:b"])
    #expect(await query.query.hasNextPage())

    // `loadMore` returns the page it fetched; the accumulated list is read back
    // through `data()`, which is where `getNextPageParam` flattening lives.
    let page = try await query.query.loadMore()
    #expect(page.items.map(\.id) == ["did:plc:c"])

    let all = await query.query.data()
    #expect(all.items.map(\.id) == ["did:plc:a", "did:plc:b", "did:plc:c"])
    #expect(all.pages.count == 2)
    #expect(await query.query.hasNextPage() == false)
  }

  @Test("likes dedupe repeat actors across pages")
  func likedByDedupe() async throws {
    let transport = ScriptedTransport(pages: [
      "": [
        "uri": Self.uri,
        "likes": [
          ["actor": profileJSON("did:plc:a"), "createdAt": "2026-01-01T00:00:00.000Z", "indexedAt": "2026-01-01T00:00:00.000Z"]
        ],
        "cursor": "page2",
      ],
      "page2": [
        "uri": Self.uri,
        "likes": [
          // "a" repeats; only the new actor should survive the merge.
          ["actor": profileJSON("did:plc:a"), "createdAt": "2026-01-02T00:00:00.000Z", "indexedAt": "2026-01-02T00:00:00.000Z"],
          ["actor": profileJSON("did:plc:b"), "createdAt": "2026-01-02T00:00:00.000Z", "indexedAt": "2026-01-02T00:00:00.000Z"],
        ],
      ],
    ])

    let store = QueryStore()
    let query = LikedByQuery(
      store: store, client: Self.client(transport), args: .init(uri: Self.uri))

    _ = try await query.query.loadFirstPage()
    _ = try await query.query.loadMore()

    // The duplicate actor in page 2 was dropped on merge.
    let all = await query.query.data()
    #expect(all.items.map(\.id) == ["did:plc:a", "did:plc:b"])
    #expect(all.pages.count == 2)
    #expect(all.pages[1].items.map(\.id) == ["did:plc:b"])
  }

  @Test("likes send the uri, the 30-item page size and the cursor")
  func likedByParams() async throws {
    let transport = ScriptedTransport(pages: [
      "": ["uri": Self.uri, "likes": [], "cursor": "page2"],
      "page2": ["uri": Self.uri, "likes": []],
    ])
    let store = QueryStore()
    let query = LikedByQuery(
      store: store, client: Self.client(transport), args: .init(uri: Self.uri))

    _ = try await query.query.loadFirstPage()
    _ = try await query.query.loadMore()

    let requests = transport.received
    #expect(requests.count == 2)
    #expect(requests[0].methodName == "app.bsky.feed.getLikes")
    #expect(requests[0].params["uri"] == Self.uri)
    #expect(requests[0].params["limit"] == "30")
    #expect(requests[0].params["cursor"] == nil || requests[0].params["cursor"] == "")
    #expect(requests[1].params["cursor"] == "page2")
  }

  // MARK: - Reposted by

  @Test("reposts paginate and dedupe by did")
  func repostedByPagination() async throws {
    let transport = ScriptedTransport(pages: [
      "": [
        "uri": Self.uri,
        "repostedBy": [profileJSON("did:plc:a")],
        "cursor": "page2",
      ],
      "page2": [
        "uri": Self.uri,
        "repostedBy": [profileJSON("did:plc:a"), profileJSON("did:plc:b")],
      ],
    ])
    let store = QueryStore()
    let query = RepostedByQuery(
      store: store, client: Self.client(transport), args: .init(uri: Self.uri))

    _ = try await query.query.loadFirstPage()
    _ = try await query.query.loadMore()
    let all = await query.query.data()
    #expect(all.items.map(\.did.rawValue) == ["did:plc:a", "did:plc:b"])
  }

  @Test("reposts use the reposted-by key root and the right method")
  func repostedByParams() async throws {
    let transport = ScriptedTransport(pages: [
      "": ["uri": Self.uri, "repostedBy": []]
    ])
    let store = QueryStore()
    let query = RepostedByQuery(
      store: store, client: Self.client(transport), args: .init(uri: Self.uri))
    _ = try await query.query.loadFirstPage()

    #expect(transport.received[0].methodName == "app.bsky.feed.getRepostedBy")
    #expect(transport.received[0].params["limit"] == "30")
    #expect(query.query.key.root == "reposted-by")
  }

  // MARK: - Quotes

  @Test("quotes paginate and dedupe by post uri")
  func quotesPagination() async throws {
    let transport = ScriptedTransport(pages: [
      "": [
        "uri": Self.uri,
        "posts": [postJSON("at://q1")],
        "cursor": "page2",
      ],
      "page2": [
        "uri": Self.uri,
        "posts": [postJSON("at://q1"), postJSON("at://q2")],
      ],
    ])
    let store = QueryStore()
    let query = QuotesQuery(
      store: store, client: Self.client(transport), args: .init(uri: Self.uri))

    _ = try await query.query.loadFirstPage()
    _ = try await query.query.loadMore()
    let all = await query.query.data()
    #expect(all.items.map(\.id) == ["at://q1", "at://q2"])
  }

  @Test("quotes use the post-quotes key root")
  func quotesKeyRoot() {
    let key = PostThreadList.quotesKey(.init(uri: Self.uri))
    #expect(key.root == "post-quotes")
  }

  // MARK: - Keys

  @Test("list keys carry the account scope")
  func listKeysScoped() {
    let scoped = PostThreadList.likedByKey(
      .init(uri: Self.uri, accountDid: "did:plc:me"))
    #expect(scoped.scope == "did:plc:me")

    let unscoped = PostThreadList.repostedByKey(.init(uri: Self.uri))
    #expect(unscoped.scope == nil)
  }

  @Test("two different uris produce different keys")
  func distinctKeys() {
    let a = PostThreadList.likedByKey(.init(uri: "at://a"))
    let b = PostThreadList.likedByKey(.init(uri: "at://b"))
    #expect(a != b)
  }

  @Test("the page size matches RN's 30")
  func pageSize() {
    #expect(PostThreadList.pageSize == 30)
  }

  // MARK: - Thread query

  @Test("the thread key is rooted like RN's and includes the params")
  func threadKey() {
    let params = PostThreadParams(uri: Self.uri)
    let key = PostThreadQueryKey.thread(params)
    #expect(key.root == "post-thread")
    #expect(key.argsDebugDescription.contains(Self.uri))
  }

  @Test("the thread fetcher sends uri, depth and parentHeight")
  func threadFetchParams() async throws {
    let transport = ScriptedTransport(pages: [
      "": [
        "thread": [
          "$type": "app.bsky.feed.defs#threadViewPost",
          "post": postJSON(Self.uri),
        ]
      ]
    ])
    let fetcher = PostThreadFetcher(client: Self.client(transport))
    let params = PostThreadParams(uri: Self.uri, depth: 10, parentHeight: 25)
    _ = try await fetcher(params)

    let request = transport.received[0]
    #expect(request.methodName == "app.bsky.feed.getPostThread")
    #expect(request.params["uri"] == Self.uri)
    #expect(request.params["depth"] == "10")
    #expect(request.params["parentHeight"] == "25")
  }

  @Test("the default params match RN's tree query")
  func defaultParams() {
    // RN's removed tree query always sent `depth: REPLY_TREE_DEPTH` (10) and no
    // parent height.
    #expect(PostThreadParams.replyTreeDepth == 10)
    let params = PostThreadParams(uri: Self.uri)
    #expect(params.depth == 10)
    #expect(params.parentHeight == nil)
  }

  @Test("the fetcher decodes a response into a thread output")
  func threadDecode() async throws {
    let transport = ScriptedTransport(pages: [
      "": [
        "thread": [
          "$type": "app.bsky.feed.defs#threadViewPost",
          "post": postJSON(Self.uri),
        ]
      ]
    ])
    let fetcher = PostThreadFetcher(client: Self.client(transport))
    let output = try await fetcher(PostThreadParams(uri: Self.uri))
    let tree = ThreadTreeBuilder.build(output: output)
    #expect(tree.uri == Self.uri)
  }
}
