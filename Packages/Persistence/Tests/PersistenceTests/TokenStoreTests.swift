import Foundation
import Testing

@testable import Persistence

/// Creates a unique temp directory for a test and removes it afterwards.
struct TempDirectory: ~Copyable {
  let url: URL

  init() {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("persistence-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

@Suite struct TokenStoreTests {
  @Test func fileStoreRoundTripsTokens() async throws {
    let temp = TempDirectory()
    let store = FileTokenStore(rootDirectory: temp.url)

    try await store.store("access-1", kind: .access, for: "did:plc:alice")
    try await store.store("refresh-1", kind: .refresh, for: "did:plc:alice")

    #expect(try await store.token(kind: .access, for: "did:plc:alice") == "access-1")
    #expect(try await store.token(kind: .refresh, for: "did:plc:alice") == "refresh-1")
    #expect(try await store.token(kind: .access, for: "did:plc:bob") == nil)
  }

  @Test func fileStoreOverwritesExistingToken() async throws {
    let temp = TempDirectory()
    let store = FileTokenStore(rootDirectory: temp.url)

    try await store.store("old", kind: .access, for: "did:plc:alice")
    try await store.store("new", kind: .access, for: "did:plc:alice")

    #expect(try await store.token(kind: .access, for: "did:plc:alice") == "new")
  }

  @Test func fileStoreRemoveIsIdempotent() async throws {
    let temp = TempDirectory()
    let store = FileTokenStore(rootDirectory: temp.url)

    // Removing a token that was never written must not throw.
    try await store.remove(kind: .access, for: "did:plc:ghost")
    try await store.removeAll(for: "did:plc:ghost")

    try await store.store("a", kind: .access, for: "did:plc:alice")
    try await store.remove(kind: .access, for: "did:plc:alice")
    #expect(try await store.token(kind: .access, for: "did:plc:alice") == nil)
  }

  @Test func fileStoreListsDidsAndClearsAll() async throws {
    let temp = TempDirectory()
    let store = FileTokenStore(rootDirectory: temp.url)

    try await store.store("a", kind: .access, for: "did:plc:alice")
    try await store.store("b", kind: .access, for: "did:plc:bob")

    #expect(try await store.dids() == ["did:plc:alice", "did:plc:bob"])

    try await store.removeAll()
    #expect(try await store.dids().isEmpty)
  }

  @Test func fileStoreSurvivesReopen() async throws {
    let temp = TempDirectory()
    let first = FileTokenStore(rootDirectory: temp.url)
    try await first.store("persisted", kind: .refresh, for: "did:plc:alice")

    // A fresh instance over the same directory must see the token.
    let second = FileTokenStore(rootDirectory: temp.url)
    #expect(try await second.token(kind: .refresh, for: "did:plc:alice") == "persisted")
    #expect(try await second.dids() == ["did:plc:alice"])
  }

  @Test func inMemoryStoreMatchesFileStoreBehavior() async throws {
    let store = InMemoryTokenStore()
    try await store.store("access", kind: .access, for: "did:plc:alice")
    try await store.store("refresh", kind: .refresh, for: "did:plc:alice")
    try await store.store("other", kind: .access, for: "did:plc:bob")

    #expect(try await store.token(kind: .access, for: "did:plc:alice") == "access")
    #expect(try await store.dids() == ["did:plc:alice", "did:plc:bob"])

    try await store.remove(kind: .access, for: "did:plc:alice")
    #expect(try await store.token(kind: .access, for: "did:plc:alice") == nil)
    // Removing one kind must not drop the other.
    #expect(try await store.token(kind: .refresh, for: "did:plc:alice") == "refresh")

    try await store.removeAll(for: "did:plc:alice")
    #expect(try await store.dids() == ["did:plc:bob"])

    try await store.removeAll()
    #expect(try await store.dids().isEmpty)
  }
}
