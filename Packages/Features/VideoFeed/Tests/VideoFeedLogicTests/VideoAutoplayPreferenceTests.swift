import Foundation
import Persistence
import Testing

@testable import VideoFeedLogic

/// The persisted autoplay preference.
///
/// Ports `useAutoplayDisabled` / `useSetAutoplayDisabled` in
/// `src/state/preferences/autoplay.tsx` and the `disableAutoplay` schema default
/// in `src/state/persisted/schema.ts`.
@Suite("Video autoplay preference")
struct VideoAutoplayPreferenceTests {
  /// A store rooted in a fresh temporary directory.
  func makeStores() throws -> (Storage<AccountSchemaMarker>, () -> Void) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("videofeed-autoplay-\(UUID().uuidString)")
    let stores = ScopedStores(directory: directory)
    return (stores.account, { try? FileManager.default.removeItem(at: directory) })
  }

  @Test("an unset preference falls back to the reduced-motion default")
  func unsetUsesDefault() async throws {
    let (account, cleanup) = try makeStores()
    defer { cleanup() }

    // RN's schema default is the platform reduced-motion setting.
    let off = await VideoAutoplayPreference.autoplayDisabled(
      account: account, did: "did:plc:me", reducedMotionEnabled: false)
    #expect(!off)

    let on = await VideoAutoplayPreference.autoplayDisabled(
      account: account, did: "did:plc:me", reducedMotionEnabled: true)
    #expect(on)
  }

  @Test("a stored preference overrides the default")
  func storedWins() async throws {
    let (account, cleanup) = try makeStores()
    defer { cleanup() }

    try await VideoAutoplayPreference.setAutoplayDisabled(
      true, account: account, did: "did:plc:me")
    let stored = await VideoAutoplayPreference.autoplayDisabled(
      account: account, did: "did:plc:me", reducedMotionEnabled: false)
    // The stored value wins even though the reduced-motion default says otherwise.
    #expect(stored)
  }

  @Test("the preference is scoped per account")
  func accountScoped() async throws {
    let (account, cleanup) = try makeStores()
    defer { cleanup() }

    try await VideoAutoplayPreference.setAutoplayDisabled(
      true, account: account, did: "did:plc:one")
    let other = await VideoAutoplayPreference.autoplayDisabled(
      account: account, did: "did:plc:two")
    // A second account has no stored value, so it gets the default.
    #expect(!other)
  }

  @Test("a stored preference can be cleared back to unset")
  func clearedPreference() async throws {
    let (account, cleanup) = try makeStores()
    defer { cleanup() }

    try await VideoAutoplayPreference.setAutoplayDisabled(
      true, account: account, did: "did:plc:me")
    try await account.remove(["did:plc:me"], VideoAutoplayPreference.accountKey)
    let after = await VideoAutoplayPreference.autoplayDisabled(
      account: account, did: "did:plc:me", reducedMotionEnabled: false)
    #expect(!after)
  }

  @Test("the settings bridge folds the preference into the feed's settings")
  func settingsBridge() async throws {
    let (account, cleanup) = try makeStores()
    defer { cleanup() }

    try await VideoAutoplayPreference.setAutoplayDisabled(
      true, account: account, did: "did:plc:me")
    let settings = await VideoAutoplayPreference.settings(
      account: account, did: "did:plc:me", muted: false, isWithinMessage: false)
    #expect(settings.autoplayDisabled)
    #expect(!settings.muted)

    // And that settings value drives the decision the pager uses.
    #expect(videoAutoplayDecision(settings: settings, moderation: nil) == .playOnDemand)
  }

  @Test("the schema key matches the persisted account schema")
  func schemaKey() {
    // The Swift port stores the flag under `autoplayDisabled`; RN calls it
    // `disableAutoplay`. Pinning the name keeps a rename from silently orphaning
    // a user's stored preference.
    #expect(VideoAutoplayPreference.accountKey == "autoplayDisabled")
    #expect(AccountSchema.allKeys.contains(VideoAutoplayPreference.accountKey))
  }
}
