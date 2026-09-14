import Foundation
import Testing

@testable import Persistence

private func makeTempDirectory() -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("persisted-store-\(UUID().uuidString)")
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Suite struct PersistedStoreTests {
  @Test func hydrateWithNoFileYieldsDefaults() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = PersistedStore(directory: directory)
    let schema = await store.hydrate()

    #expect(schema == PersistedSchema.defaults())
    #expect(await store.lastDecodeIssues.isEmpty)
  }

  @Test func writeThenHydrateRoundTrips() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = PersistedStore(directory: directory)
    try await first.write { schema in
      schema.colorMode = .light
      schema.session.accounts = [
        PersistedAccount(
          service: "https://bsky.social/", did: "did:plc:alice",
          handle: "alice.example", refreshJwt: "r", accessJwt: "a")
      ]
      schema.session.currentAccount = PersistedCurrentAccount(did: "did:plc:alice")
    }

    let second = PersistedStore(directory: directory)
    let hydrated = await second.hydrate()

    #expect(hydrated.colorMode == .light)
    #expect(hydrated.session.accounts.count == 1)
    #expect(hydrated.session.accounts.first?.handle == "alice.example")
    #expect(hydrated.session.currentAccount?.did == "did:plc:alice")
  }

  /// The end-to-end form of the deviation: a corrupted field on disk must not
  /// wipe the account list on the next boot.
  @Test func hydrateSalvagesAccountsWhenOneFieldIsCorrupt() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let seed = PersistedStore(directory: directory)
    try await seed.write { schema in
      schema.session.accounts = [
        PersistedAccount(
          service: "https://bsky.social/", did: "did:plc:alice",
          handle: "alice.example", refreshJwt: "r", accessJwt: "a"),
        PersistedAccount(
          service: "https://bsky.social/", did: "did:plc:bob",
          handle: "bob.example", refreshJwt: "r", accessJwt: "b"),
      ]
      schema.session.currentAccount = PersistedCurrentAccount(did: "did:plc:alice")
    }

    // Corrupt one unrelated field on disk by hand.
    let fileURL = directory.appendingPathComponent("BSKY_STORAGE.json")
    var members = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
    members["disableHaptics"] = "definitely-not-a-bool"
    try JSONSerialization.data(withJSONObject: members).write(to: fileURL)

    let store = PersistedStore(directory: directory)
    let hydrated = await store.hydrate()

    #expect(hydrated.session.accounts.count == 2)
    #expect(hydrated.session.currentAccount?.did == "did:plc:alice")
    #expect(await store.lastDecodeIssues.contains { $0.field == "disableHaptics" })
  }

  @Test func unparseableFileFallsBackToDefaultsWithoutThrowing() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("BSKY_STORAGE.json")
    try Data("this is not json".utf8).write(to: fileURL)

    let store = PersistedStore(directory: directory)
    let schema = await store.hydrate()

    #expect(schema == PersistedSchema.defaults())
  }

  @Test func clearStorageRemovesFileAndResetsState() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = PersistedStore(directory: directory)
    try await store.write { $0.colorMode = .dark }
    try await store.clearStorage()

    #expect(await store.current() == PersistedSchema.defaults())
    let fresh = PersistedStore(directory: directory)
    #expect(await fresh.hydrate() == PersistedSchema.defaults())
  }

  @Test func languagePrefsAreNormalizedOnWrite() async throws {
    let store = PersistedStore(directory: makeTempDirectory())
    try await store.write { schema in
      schema.languagePrefs.primaryLanguage = "en-US"
      schema.languagePrefs.contentLanguages = ["en-US", "ja-JP", "en-US"]
      schema.languagePrefs.postLanguage = "EN-us, ja"
    }

    let schema = await store.current()
    #expect(schema.languagePrefs.primaryLanguage == "en")
    #expect(schema.languagePrefs.contentLanguages == ["en", "ja"])
    #expect(schema.languagePrefs.postLanguage == "en,ja")
  }

  @Test func migrationRunsOnVersionMismatch() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // Seed a version-1 document.
    let v1 = PersistedStore(directory: directory, schemaVersion: 1)
    try await v1.write { $0.colorMode = .dark }

    // A version-2 store renames colorMode -> themeMode via its migration.
    let v2 = PersistedStore(
      directory: directory, schemaVersion: 2,
      migration: { _, members in
        var next = members
        next["darkTheme"] = next.removeValue(forKey: "colorMode")
        return next
      })
    let schema = await v2.hydrate()

    #expect(schema.darkTheme == .dark)
    // colorMode is gone, so it falls back to the default.
    #expect(schema.colorMode == .system)
  }
}

@Suite struct MigratorTests {
  @Test func migrateFromCurrentVersionIsIdentity() {
    let members: [String: JSONValue] = ["colorMode": .string("dark")]
    let result = PersistedMigrator.migrate(fromVersion: 1, members: members)
    #expect(result == members)
  }

  @Test func futureVersionIsLeftUntouched() {
    let members: [String: JSONValue] = ["colorMode": .string("dark")]
    let result = PersistedMigrator.migrate(fromVersion: 99, members: members)
    #expect(result == members)
  }

  @Test func unversionedDocumentIsTreatedAsOldest() {
    let members: [String: JSONValue] = ["colorMode": .string("dark")]
    let result = PersistedMigrator.migrate(fromVersion: 0, members: members)
    #expect(result == members)
  }
}
