import Foundation
import Testing

import Lexicons
import SwiftAtproto

@testable import Preferences

/// Read-modify-write serialization: concurrent submissions must not interleave
/// their reads and writes.
@Suite struct SerializationTests {

  /// Two concurrent writes both land, and each read observes the previous
  /// write's result (no lost update).
  @Test func concurrentWritesDoNotLoseUpdates() async throws {
    let service = FakePreferencesService()
    let engine = service.engine()

    async let first: Void = engine.setIsBetaUser(true)
    async let second: Void = engine.queueNudges(["a"])
    _ = try await (first, second)

    // Both mutations are represented in the final array.
    #expect(service.preferencesJSON.contains(#""isBetaUser":true"#))
    #expect(service.preferencesJSON.contains(#""queuedNudges":["a"]"#))
    #expect(service.putCount == 2)
  }

  /// A write submitted while another write's read is suspended queues behind
  /// it: the second write's read sees the first write's result.
  @Test func writeQueuesBehindInFlightCycle() async throws {
    let service = FakePreferencesService()
    let engine = service.engine()

    service.suspendNextRead()
    async let first: Void = engine.setAdultContentEnabled(true)
    // Give the first cycle time to reach its suspended read.
    try await Task.sleep(for: .milliseconds(20))
    #expect(service.isReadSuspended)

    async let second: Void = engine.setInterestsPref(tags: ["art"])
    try await Task.sleep(for: .milliseconds(20))
    // The second cycle cannot have read yet; the first read is still open.
    #expect(service.getCount == 1)

    service.releaseRead()
    _ = try await (first, second)

    // Reads never overlapped: exactly one read was in flight at a time, and
    // both writes are present.
    #expect(service.getCount == 2)
    #expect(service.putCount == 2)
    #expect(service.preferencesJSON.contains(#""enabled":true"#))
    #expect(service.preferencesJSON.contains(#""tags":["art"]"#))
  }

  /// A skipped cycle (patch returned nil) performs the read but no write, and
  /// does not block a later write.
  @Test func skippedCycleDoesNotWrite() async throws {
    let service = FakePreferencesService()
    let engine = service.engine()

    async let skipped: Void = engine.addLabeler("did:plc:abc")
    async let applied: Void = engine.addLabeler("did:plc:abc")
    _ = try await (skipped, applied)

    // First adds, second sees it and skips: exactly one write.
    #expect(service.putCount == 1)
  }
}

/// Saved-feeds v1 -> v2 migration on first read.
@Suite struct MigrationTests {

  @Test func migratesV1PinnedAndSavedIntoV2() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPref","pinned":["at://did:plc:a/app.bsky.feed.generator/x"],"saved":["at://did:plc:a/app.bsky.feed.generator/x","at://did:plc:a/app.bsky.graph.list/l"]}]"#
    )
    let engine = service.engine(tids: SequentialTidGenerator())
    let prefs = try await engine.getPreferences()

    // Timeline first (pinned), then the pinned feed, then the saved-only list.
    #expect(prefs.savedFeeds.map { $0["type"]?.stringValue } == ["timeline", "feed", "list"])
    #expect(prefs.savedFeeds.map { $0["pinned"]?.boolValue } == [true, true, false])
    // The migration was written back.
    #expect(service.putCount == 1)
    #expect(service.preferencesJSON.contains(PreferenceStrings.savedFeedsPrefV2))
  }

  @Test func migrationPreservesPinnedOrder() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPref","pinned":["at://did:plc:a/app.bsky.feed.generator/y","at://did:plc:a/app.bsky.feed.generator/x"],"saved":["at://did:plc:a/app.bsky.feed.generator/y","at://did:plc:a/app.bsky.feed.generator/x"]}]"#
    )
    let prefs = try await service.engine().getPreferences()
    #expect(
      prefs.savedFeeds.compactMap { $0["value"]?.stringValue } == [
        "following",
        "at://did:plc:a/app.bsky.feed.generator/y",
        "at://did:plc:a/app.bsky.feed.generator/x",
      ])
  }

  @Test func migratesToDefaultTimelineWhenNoSavedFeedsPref() async throws {
    let service = FakePreferencesService(rawJSON: #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]"#)
    let prefs = try await service.engine().getPreferences()
    #expect(prefs.savedFeeds.count == 1)
    #expect(prefs.savedFeeds[0]["type"]?.stringValue == "timeline")
    #expect(prefs.savedFeeds[0]["value"]?.stringValue == "following")
    #expect(service.putCount == 1)
  }

  @Test func existingV2SkipsMigration() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[{"id":"a","pinned":true,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"}]}]"#
    )
    let prefs = try await service.engine().getPreferences()
    #expect(prefs.savedFeeds.count == 1)
    #expect(service.putCount == 0)
  }

  @Test func migrationDoesNotRecurOnSecondRead() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPref","pinned":["at://did:plc:a/app.bsky.feed.generator/x"],"saved":["at://did:plc:a/app.bsky.feed.generator/x"]}]"#
    )
    let engine = service.engine()
    _ = try await engine.getPreferences()
    let writesAfterFirst = service.putCount
    _ = try await engine.getPreferences()
    #expect(writesAfterFirst == 1)
    #expect(service.putCount == 1)
  }
}

/// Hydration: the structured view assembled from the raw array.
@Suite struct HydrationTests {

  @Test func seedsDefaultLabelsThenAppliesStoredRemap() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#contentLabelPref","label":"nsfw","visibility":"show"}]"#
    )
    let prefs = try await service.engine().getPreferences()
    // "nsfw" remaps to "porn"; "show" normalizes to "ignore"; the original
    // legacy key is also written.
    #expect(prefs.moderationPrefs.labels["porn"] == "ignore")
    #expect(prefs.moderationPrefs.labels["nsfw"] == "ignore")
    // Untouched defaults survive.
    #expect(prefs.moderationPrefs.labels["graphic-media"] == "warn")
    #expect(prefs.moderationPrefs.labels["nudity"] == "ignore")
  }

  @Test func mergesAppLabelerWithUserLabelers() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:user"}]},{"$type":"app.bsky.actor.defs#contentLabelPref","label":"porn","labelerDid":"did:plc:user","visibility":"hide"}]"#
    )
    let prefs = try await service.engine().getPreferences()
    let dids = prefs.moderationPrefs.labelers.map(\.did)
    #expect(dids.contains(BlueskyModerationLabeler.did))
    #expect(dids.contains("did:plc:user"))
    let user = prefs.moderationPrefs.labelers.first { $0.did == "did:plc:user" }
    #expect(user?.labels["porn"] == "hide")
  }

  @Test func defaultsHomeFeedViewWhenAbsent() async throws {
    let service = FakePreferencesService()
    let prefs = try await service.engine().getPreferences()
    let home = try #require(prefs.feedViewPrefs["home"])
    #expect(home.hideReplies == false)
    #expect(home.hideRepliesByUnfollowed == true)
  }

  @Test func mutedWordsDefaultActorTargetToAll() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"id":"a","value":"x","targets":["content"]}]}]"#
    )
    let prefs = try await service.engine().getPreferences()
    #expect(prefs.moderationPrefs.mutedWords.first?["actorTarget"]?.stringValue == "all")
  }

  @Test func defaultsVerificationAndLiveEventPrefs() async throws {
    let service = FakePreferencesService()
    let prefs = try await service.engine().getPreferences()
    #expect(prefs.verificationPrefs["hideBadges"]?.boolValue == false)
    #expect(prefs.liveEventPreferences.hideAllFeeds == false)
    #expect(prefs.liveEventPreferences.hiddenFeedIds.isEmpty)
    #expect(prefs.threadViewPrefs.sort == "hotness")
  }
}

/// Open-union tolerance: preference records the generated types do not model
/// survive a read-modify-write unchanged.
@Suite struct OpenUnionTests {

  @Test func unknownPrefTypeSurvivesAnUnrelatedWrite() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"com.example.futurePref","payload":{"nested":[1,"two",true]},"count":3},{"$type":"app.bsky.actor.defs#adultContentPref","enabled":false}]"#
    )
    try await service.engine().setAdultContentEnabled(true)
    #expect(service.preferencesJSON.contains(#""$type":"com.example.futurePref""#))
    #expect(service.preferencesJSON.contains(#""count":3"#))
    #expect(service.preferencesJSON.contains(#""nested":[1,"two",true]"#))
    #expect(service.preferencesJSON.contains(#""enabled":true"#))
  }

  @Test func unknownMembersInsideKnownPrefSurvive() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref","isBetaUser":false,"futureField":"keep-me"}]"#
    )
    try await service.engine().setIsBetaUser(true)
    #expect(service.preferencesJSON.contains(#""futureField":"keep-me""#))
    #expect(service.preferencesJSON.contains(#""isBetaUser":true"#))
  }

  @Test func unknownSavedFeedTypeSurvivesAV2Write() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[{"id":"k","pinned":false,"type":"unknown","value":"opaque"},{"id":"a","pinned":true,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"}]}]"#
    )
    try await service.engine().removeSavedFeeds([])
    #expect(service.preferencesJSON.contains(#""type":"unknown""#))
  }

  @Test func unknownLabelVisibilityPassesThrough() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#contentLabelPref","label":"some-label","visibility":"future-value"}]"#
    )
    let prefs = try await service.engine().getPreferences()
    #expect(prefs.moderationPrefs.labels["some-label"] == "future-value")
  }

  @Test func unknownPrefWithNoTypeSurvives() async throws {
    // A record with no $type decodes as the union's `_other` case; it must
    // round-trip on write (the SDK preserves it as an opaque record too).
    let service = FakePreferencesService(
      rawJSON: #"[{"weird":true},{"$type":"app.bsky.actor.defs#adultContentPref","enabled":false}]"#
    )
    try await service.engine().setAdultContentEnabled(true)
    #expect(service.preferencesJSON.contains(#""weird":true"#))
  }
}

/// Record position semantics: most actions rewrite a record where it sits
/// (`prefs.map`), while a few remove and re-append it (`filter().concat()`).
@Suite struct RecordOrderTests {

  @Test func setIsBetaUserKeepsAppStatePosition() async throws {
    // The app-state pref sits in the middle; setIsBetaUser maps it in place.
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true},{"$type":"app.bsky.actor.defs#bskyAppStatePref","isBetaUser":false},{"$type":"app.bsky.actor.defs#interestsPref","tags":[]}]"#
    )
    try await service.engine().setIsBetaUser(true)
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true},{"$type":"app.bsky.actor.defs#bskyAppStatePref","isBetaUser":true},{"$type":"app.bsky.actor.defs#interestsPref","tags":[]}]"#
    )
  }

  @Test func setContentLabelPrefMovesRecordToEnd() async throws {
    // setContentLabelPref filters the old pref out and appends the new one.
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#contentLabelPref","label":"nudity","visibility":"warn"},{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]"#
    )
    try await service.engine().setContentLabelPref(key: "nudity", value: "hide")
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true},{"$type":"app.bsky.actor.defs#contentLabelPref","label":"nudity","visibility":"hide"}]"#
    )
  }
}

/// The public API surface: every SDK action has a typed method, and the
/// composite conveniences fan out into one cycle each.
@Suite struct APIUsabilityTests {

  @Test func everyTypedMethodReachesTheServer() async throws {
    let service = FakePreferencesService()
    let engine = service.engine()

    try await engine.setAdultContentEnabled(true)
    try await engine.setContentLabelPref(key: "nudity", value: "ignore")
    try await engine.addLabeler("did:plc:abc")
    try await engine.removeLabeler("did:plc:abc")
    try await engine.hidePost("at://x/1")
    try await engine.unhidePost("at://x/1")
    try await engine.addSavedFeeds([
      SavedFeedInput(
        type: "feed", value: "at://did:plc:a/app.bsky.feed.generator/x", pinned: true)
    ])
    try await engine.updateSavedFeeds([])
    try await engine.overwriteSavedFeeds([])
    try await engine.addPinnedFeed("at://did:plc:a/app.bsky.feed.generator/x")
    try await engine.removePinnedFeed("at://did:plc:a/app.bsky.feed.generator/x")
    try await engine.setFeedViewPrefs(feed: "home", patch: FeedViewPrefPatch())
    try await engine.setThreadViewPrefs(ThreadViewPrefPatch())
    try await engine.setPersonalDetails(nil)
    try await engine.setInterestsPref(tags: ["art"])
    try await engine.addMutedWord(MutedWordInput(value: "spam", targets: ["content"]))
    try await engine.updateMutedWord(try TestJSON.object(#"{"id":"nope"}"#))
    try await engine.removeMutedWord(try TestJSON.object(#"{"id":"nope"}"#))
    try await engine.queueNudges(["n1"])
    try await engine.dismissNudges(["n1"])
    try await engine.setIsBetaUser(true)
    try await engine.setActiveProgressGuide("com.example.guide")
    try await engine.upsertNux(try TestJSON.object(#"{"id":"n1","completed":true}"#))
    try await engine.removeNuxs(["n1"])
    try await engine.setVerificationPrefs(VerificationPrefsPatch(hideBadges: true))
    try await engine.setPostInteractionSettings(PostInteractionSettings())
    try await engine.updateLiveEventPreferences(.toggleHideAllFeeds)

    // Every call performed a serialized cycle.
    #expect(service.getCount == service.putCount)
    #expect(service.getCount > 0)
  }

  @Test func fetchAndPutRawArray() async throws {
    let service = FakePreferencesService(
      rawJSON: #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]"#)
    let engine = service.engine()

    let fetched = try await engine.fetchPreferences()
    #expect(fetched.elements.count == 1)

    // putPreferences overwrites wholesale (the clear-preferences path).
    try await engine.putPreferences(PreferencesArray())
    #expect(service.preferencesJSON == "[]")
    #expect(service.putCount == 1)
  }

  @Test func applyReturnsResultingArray() async throws {
    let service = FakePreferencesService()
    let engine = service.engine()

    let result = try await engine.apply { prefs in
      var record = PrefObject.make(PrefType.interestsPref)
      record.set("tags", ["art"])
      return prefs.appending(record)
    }
    #expect(result.count == 1)
    #expect(service.preferencesJSON.contains(#""tags":["art"]"#))

    // A skipped patch leaves the stored array untouched.
    let skipped = try await engine.apply { _ in nil }
    #expect(skipped.count == 1)
    #expect(service.putCount == 1)
  }

  @Test func generatedUnionRoundTripsThroughTheRawArray() throws {
    // The typed `PreferencesArray` init/encoded bridge to the generated
    // lexicon union for callers who hold generated values.
    let json =
      #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]"#
    let elements = try JSONDecoder().decode(
      [App.Bsky.ActorDefs_Preferences_Elem].self, from: Data(json.utf8))
    let array = try PreferencesArray(elements)
    #expect(array.elements.count == 1)
    #expect(try array.encoded().count == 1)
  }

  @Test func unknownPreferencesSurviveTheWholeSurface() async throws {
    let service = FakePreferencesService(
      rawJSON: #"[{"$type":"com.example.futurePref","opaque":{"deep":[1,2]}}]"#)
    let engine = service.engine()
    try await engine.setIsBetaUser(true)
    try await engine.setInterestsPref(tags: ["art"])
    try await engine.setAdultContentEnabled(true)
    #expect(service.preferencesJSON.contains(#""$type":"com.example.futurePref""#))
    #expect(service.preferencesJSON.contains(#""deep":[1,2]"#))
  }
}

/// `$type` constants referenced from tests.
enum PreferenceStrings {
  static let savedFeedsPrefV2 = "app.bsky.actor.defs#savedFeedsPrefV2"
}
