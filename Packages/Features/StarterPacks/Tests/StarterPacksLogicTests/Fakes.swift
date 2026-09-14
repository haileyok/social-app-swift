import ATProtoClient
import Foundation
import Lexicons
import SwiftAtproto

@testable import StarterPacksLogic

/// A scripted ``StarterPackXrpc`` that records every call and returns queued
/// pages.
///
/// The package deliberately does not reach into `TestSupport` (a placeholder), so
/// this is a package-local fake, following the `RecordingFeedXrpc` pattern in the
/// HomeFeed package.
final class FakeStarterPackXrpc: StarterPackXrpc, @unchecked Sendable {
  /// One recorded call, with the exact parameters it carried.
  enum Call: Sendable, Equatable {
    case getStarterPack(uri: String)
    case getStarterPacks(uris: [String])
    case getActorStarterPacks(actor: String, cursor: String?, limit: Int)
    case getStarterPacksWithMembership(actor: String, cursor: String?, limit: Int)
    case searchStarterPacks(query: String, cursor: String?, limit: Int)
    case getList(list: String, cursor: String?, limit: Int)
    case applyWrites(repo: String, writes: [StarterPackJSON])
    case createRecord(repo: String, collection: String, rkey: String?, record: StarterPackJSON)
    case putRecord(repo: String, collection: String, rkey: String, record: StarterPackJSON)
    case deleteRecord(repo: String, collection: String, rkey: String)
  }

  private let lock = NSLock()
  private var _calls: [Call] = []

  private var packViews: [String: App.Bsky.GraphDefs_StarterPackView] = [:]
  private var basicViews: [App.Bsky.GraphDefs_StarterPackViewBasic] = []
  private var actorPages: [StarterPackBasicPage] = []
  private var membershipPages: [StarterPackWithMembershipPage] = []
  private var searchPages: [StarterPackViewPage] = []
  private var listPages: [StarterPackListMembersPage] = []
  private var throwOn: Set<String> = []
  /// The error thrown by a failing accessor.
  var thrownError: any Error = XrpcError(rawCode: nil, message: "boom", status: 500)
  /// The URI `createRecord` returns, keyed by collection. Defaults to a
  /// generated URI when unset.
  private var createdURIs: [String: String] = [:]
  /// How many `createRecord` calls have happened, for URI generation.
  private var createCount = 0
  /// When set, `applyWrites` throws once the recorded writes exceed this count.
  private var failApplyWritesAfter: Int?

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// Every call recorded so far, in order.
  var calls: [Call] { withLock { _calls } }

  /// The calls of one kind, for focused assertions.
  func calls(matching predicate: (Call) -> Bool) -> [Call] {
    calls.filter(predicate)
  }

  /// Fails the named accessor when it is next called.
  func fail(_ accessor: String) {
    withLock { throwOn.insert(accessor) }
  }

  private func shouldThrow(_ accessor: String) -> Bool {
    withLock { throwOn.contains(accessor) }
  }

  // MARK: - Configuration

  /// Sets the view `getStarterPack` returns for `uri`.
  func setPackView(_ view: App.Bsky.GraphDefs_StarterPackView, for uri: String) {
    withLock { packViews[uri] = view }
  }

  /// Sets the views `getStarterPacks` and `getActorStarterPacks` return.
  func setBasicViews(_ views: [App.Bsky.GraphDefs_StarterPackViewBasic]) {
    withLock { basicViews = views }
  }

  /// Queues actor-starter-pack pages, consumed in order.
  func setActorPages(_ pages: [StarterPackBasicPage]) {
    withLock { actorPages = pages }
  }

  /// Queues membership pages, consumed in order.
  func setMembershipPages(_ pages: [StarterPackWithMembershipPage]) {
    withLock { membershipPages = pages }
  }

  /// Queues search pages, consumed in order.
  func setSearchPages(_ pages: [StarterPackViewPage]) {
    withLock { searchPages = pages }
  }

  /// Queues list-member pages, consumed in order.
  func setListPages(_ pages: [StarterPackListMembersPage]) {
    withLock { listPages = pages }
  }

  /// Makes `createRecord` return `uri` for records in `collection`.
  func setCreatedURI(_ uri: String, for collection: String) {
    withLock {
      createdURIs[collection] = uri
      createCount += 1
    }
  }

  /// Makes `applyWrites` throw after `count` calls.
  func failApplyWrites(after count: Int) {
    withLock { failApplyWritesAfter = count }
  }

  // MARK: - StarterPackXrpc

  func getStarterPack(uri: String) async throws -> App.Bsky.GraphDefs_StarterPackView {
    note(.getStarterPack(uri: uri))
    if shouldThrow("getStarterPack") { throw thrownError }
    guard let view = withLock({ packViews[uri] }) else {
      throw XrpcError(rawCode: "NotFound", message: "no pack", status: 404)
    }
    return view
  }

  func getStarterPacks(uris: [String]) async throws -> [App.Bsky.GraphDefs_StarterPackViewBasic] {
    note(.getStarterPacks(uris: uris))
    if shouldThrow("getStarterPacks") { throw thrownError }
    return withLock { basicViews.filter { uris.contains($0.uri.rawValue) } }
  }

  func getActorStarterPacks(
    actor: String, cursor: String?, limit: Int
  ) async throws -> StarterPackBasicPage {
    note(.getActorStarterPacks(actor: actor, cursor: cursor, limit: limit))
    if shouldThrow("getActorStarterPacks") { throw thrownError }
    return withLock { actorPages.isEmpty ? StarterPackBasicPage() : actorPages.removeFirst() }
  }

  func getStarterPacksWithMembership(
    actor: String, cursor: String?, limit: Int
  ) async throws -> StarterPackWithMembershipPage {
    note(.getStarterPacksWithMembership(actor: actor, cursor: cursor, limit: limit))
    if shouldThrow("membership") { throw thrownError }
    return withLock {
      membershipPages.isEmpty ? StarterPackWithMembershipPage() : membershipPages.removeFirst()
    }
  }

  func searchStarterPacks(
    query: String, cursor: String?, limit: Int
  ) async throws -> StarterPackViewPage {
    note(.searchStarterPacks(query: query, cursor: cursor, limit: limit))
    if shouldThrow("search") { throw thrownError }
    return withLock { searchPages.isEmpty ? StarterPackViewPage() : searchPages.removeFirst() }
  }

  func getList(
    list: String, cursor: String?, limit: Int
  ) async throws -> StarterPackListMembersPage {
    note(.getList(list: list, cursor: cursor, limit: limit))
    if shouldThrow("getList") { throw thrownError }
    return withLock { listPages.isEmpty ? StarterPackListMembersPage() : listPages.removeFirst() }
  }

  func applyWrites(repo: String, writes: [StarterPackWrite]) async throws {
    note(.applyWrites(repo: repo, writes: writes))
    if shouldThrow("applyWrites") { throw thrownError }
    if let limit = withLock({ failApplyWritesAfter }) {
      let written = calls(matching: { call in
        if case .applyWrites = call { return true } else { return false }
      })
      if written.count > limit { throw thrownError }
    }
  }

  func createRecord(
    repo: String, collection: String, rkey: String?, record: StarterPackJSON
  ) async throws -> StarterPackRecordRef {
    note(.createRecord(repo: repo, collection: collection, rkey: rkey, record: record))
    if shouldThrow("createRecord") { throw thrownError }
    if let uri = withLock({ createdURIs[collection] }) {
      return StarterPackRecordRef(uri: uri, cid: "createdcid")
    }
    let n = withLock { () -> Int in
      createCount += 1
      return createCount
    }
    return StarterPackRecordRef(
      uri: "at://\(repo)/\(collection)/created\(n)", cid: "createdcid\(n)")
  }

  func putRecord(
    repo: String, collection: String, rkey: String, record: StarterPackJSON
  ) async throws -> StarterPackRecordRef {
    note(.putRecord(repo: repo, collection: collection, rkey: rkey, record: record))
    if shouldThrow("putRecord") { throw thrownError }
    return StarterPackRecordRef(
      uri: "at://\(repo)/\(collection)/\(rkey)", cid: "putcid")
  }

  func deleteRecord(repo: String, collection: String, rkey: String) async throws {
    note(.deleteRecord(repo: repo, collection: collection, rkey: rkey))
    if shouldThrow("deleteRecord") { throw thrownError }
  }

  private func note(_ call: Call) {
    withLock { _calls.append(call) }
  }
}

extension NSLock {
  /// A synchronous critical section, because `NSLock.lock()` is `noasync`.
  func withLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
