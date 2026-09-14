import Foundation
import Testing

@testable import Persistence

/// Temp-directory helper shared by the store suites.
private func makeTempDirectory() -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("persistence-store-\(UUID().uuidString)")
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Suite struct StorageTests {
  @Test func deviceScopeSetGetRemove() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let device = Storage<DeviceSchemaMarker>(id: "bsky_device", directory: directory)
    try await device.set(DeviceSchema.fontScale, value: "1")
    #expect(await device.get(DeviceSchema.fontScale, as: String.self) == "1")

    try await device.remove(DeviceSchema.fontScale)
    #expect(await device.get(DeviceSchema.fontScale, as: String.self) == nil)
  }

  @Test func accountScopeIsolatesByDid() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let account = Storage<AccountSchemaMarker>(id: "bsky_account", directory: directory)
    try await account.set(["did:plc:alice"], AccountSchema.savedFeeds, value: ["feed-a"])
    try await account.set(["did:plc:bob"], AccountSchema.savedFeeds, value: ["feed-b"])

    #expect(
      await account.get(["did:plc:alice"], AccountSchema.savedFeeds, as: [String].self)
        == ["feed-a"])
    #expect(
      await account.get(["did:plc:bob"], AccountSchema.savedFeeds, as: [String].self)
        == ["feed-b"])

    try await account.removeMany(["did:plc:alice"], keys: [AccountSchema.savedFeeds])
    #expect(
      await account.get(["did:plc:alice"], AccountSchema.savedFeeds, as: [String].self) == nil)
    // Bob's value is untouched.
    #expect(
      await account.get(["did:plc:bob"], AccountSchema.savedFeeds, as: [String].self)
        == ["feed-b"])
  }

  @Test func storageSurvivesReopen() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = Storage<AccountSchemaMarker>(id: "bsky_account", directory: directory)
    try await first.set(["did:plc:alice"], AccountSchema.autoplayDisabled, value: true)

    let second = Storage<AccountSchemaMarker>(id: "bsky_account", directory: directory)
    #expect(
      await second.get(["did:plc:alice"], AccountSchema.autoplayDisabled, as: Bool.self)
        == true)
  }

  @Test func corruptValueReadsAsNilRatherThanThrowing() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let device = Storage<DeviceSchemaMarker>(id: "bsky_device", directory: directory)
    try await device.set(DeviceSchema.fontScale, value: "invalid-string")

    // Declared as Bool, stored as String: the read falls back to nil.
    #expect(await device.get(DeviceSchema.fontScale, as: Bool.self) == nil)
  }

  @Test func removeAllClearsKeysButKeepsStoreUsable() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let device = Storage<DeviceSchemaMarker>(id: "bsky_device", directory: directory)
    try await device.set(DeviceSchema.deviceId, value: "abc")
    try await device.set(DeviceSchema.trendingBetaEnabled, value: true)
    #expect(await device.keys().count == 2)

    try await device.removeAll()
    #expect(await device.keys().isEmpty)

    try await device.set(DeviceSchema.deviceId, value: "def")
    #expect(await device.get(DeviceSchema.deviceId, as: String.self) == "def")
  }

  @Test func migrationRunsOnceOnVersionMismatch() async throws {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // Seed a version-1 store with a legacy key.
    let legacy = Storage<DeviceSchemaMarker>(
      id: "bsky_device", scope: [], schemaVersion: 1, directory: directory)
    try await legacy.set("legacyKey", value: "legacyValue")

    // A version-2 store migrates by renaming the key.
    let migrated = Storage<DeviceSchemaMarker>(
      id: "bsky_device", scope: [], schemaVersion: 2, directory: directory,
      migration: { _, members in
        var next = members
        next["deviceId"] = next.removeValue(forKey: "legacyKey")
        return next
      })
    #expect(await migrated.get("deviceId", as: String.self) == "legacyValue")
    #expect(await migrated.get("legacyKey", as: String.self) == nil)
  }
}
