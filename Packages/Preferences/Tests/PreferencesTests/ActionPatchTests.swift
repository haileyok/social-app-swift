import Foundation
import Testing

import Lexicons
import SwiftAtproto

@testable import Preferences

/// Each test submits one action against an empty (or seeded) preference store
/// and asserts the exact `putPreferences` body the engine produced. The
/// expected strings are the canonical (sorted-key, no-whitespace) JSON the fake
/// service records.
@Suite struct ActionPatchTests {

  // MARK: - Adult content

  @Test func setAdultContentEnabledAppendsWhenAbsent() async throws {
    let service = FakePreferencesService()
    try await service.engine().setAdultContentEnabled(true)
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]"#)
  }

  @Test func setAdultContentEnabledUpdatesInPlace() async throws {
    let service = FakePreferencesService(
      rawJSON: #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":false}]"#)
    try await service.engine().setAdultContentEnabled(true)
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]"#)
  }

  // MARK: - Content labels

  @Test func setContentLabelPrefReplacesKeyLabelerPair() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#contentLabelPref","label":"porn","visibility":"hide"},{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]"#
    )
    try await service.engine().setContentLabelPref(key: "porn", value: "warn")
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true},{"$type":"app.bsky.actor.defs#contentLabelPref","label":"porn","visibility":"warn"},{"$type":"app.bsky.actor.defs#contentLabelPref","label":"nsfw","visibility":"warn"}]"#
    )
  }

  @Test func setContentLabelPrefDoubleWritesLegacyAliases() async throws {
    let service = FakePreferencesService()
    try await service.engine().setContentLabelPref(key: "graphic-media", value: "hide")
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#contentLabelPref","label":"graphic-media","visibility":"hide"},{"$type":"app.bsky.actor.defs#contentLabelPref","label":"gore","visibility":"hide"}]"#
    )
  }

  @Test func setContentLabelPrefScalarLabelHasNoAlias() async throws {
    let service = FakePreferencesService()
    try await service.engine().setContentLabelPref(key: "nudity", value: "ignore")
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#contentLabelPref","label":"nudity","visibility":"ignore"}]"#
    )
  }

  @Test func setContentLabelPrefLabelerScopedSkipsAlias() async throws {
    let service = FakePreferencesService()
    try await service.engine().setContentLabelPref(
      key: "porn", value: "hide", labelerDid: "did:plc:labeler")
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#contentLabelPref","label":"porn","labelerDid":"did:plc:labeler","visibility":"hide"}]"#
    )
  }

  @Test func setContentLabelPrefRejectsInvalidDid() async throws {
    let service = FakePreferencesService()
    await #expect(throws: PreferencesError.self) {
      try await service.engine().setContentLabelPref(
        key: "porn", value: "hide", labelerDid: "not-a-did")
    }
    #expect(service.putCount == 0)
  }

  // MARK: - Labelers

  @Test func addLabelerAppends() async throws {
    let service = FakePreferencesService()
    try await service.engine().addLabeler("did:plc:abc")
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:abc"}]}]"#)
  }

  @Test func addLabelerSkipsDuplicate() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:abc"}]}]"#)
    try await service.engine().addLabeler("did:plc:abc")
    #expect(service.putCount == 0)
  }

  @Test func removeLabelerFilters() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:abc"},{"did":"did:plc:xyz"}]}]"#
    )
    try await service.engine().removeLabeler("did:plc:abc")
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#labelersPref","labelers":[{"did":"did:plc:xyz"}]}]"#)
  }

  @Test func removeLabelerSkipsWhenPrefAbsent() async throws {
    let service = FakePreferencesService()
    try await service.engine().removeLabeler("did:plc:abc")
    #expect(service.putCount == 0)
  }

  // MARK: - Hidden posts

  @Test func hidePostAppends() async throws {
    let service = FakePreferencesService()
    try await service.engine().hidePost("at://did:plc:a/app.bsky.feed.post/1")
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#hiddenPostsPref","items":["at://did:plc:a/app.bsky.feed.post/1"]}]"#
    )
  }

  @Test func hidePostSkipsWhenAlreadyHidden() async throws {
    let service = FakePreferencesService(
      rawJSON: #"[{"$type":"app.bsky.actor.defs#hiddenPostsPref","items":["at://x/1"]}]"#)
    try await service.engine().hidePost("at://x/1")
    #expect(service.putCount == 0)
  }

  @Test func unhidePostFilters() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#hiddenPostsPref","items":["at://x/1","at://x/2"]}]"#)
    try await service.engine().unhidePost("at://x/1")
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#hiddenPostsPref","items":["at://x/2"]}]"#)
  }

  @Test func unhidePostSkipsWhenPrefAbsent() async throws {
    let service = FakePreferencesService()
    try await service.engine().unhidePost("at://x/1")
    #expect(service.putCount == 0)
  }

  // MARK: - Views

  @Test func setFeedViewPrefsCreatesHome() async throws {
    let service = FakePreferencesService()
    try await service.engine().setFeedViewPrefs(
      feed: "home", patch: FeedViewPrefPatch(hideReplies: true))
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#feedViewPref","feed":"home","hideReplies":true}]"#)
  }

  @Test func setFeedViewPrefsMergesExisting() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#feedViewPref","feed":"home","hideReplies":false,"hideReposts":true}]"#
    )
    try await service.engine().setFeedViewPrefs(
      feed: "home", patch: FeedViewPrefPatch(hideReplies: true))
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#feedViewPref","feed":"home","hideReplies":true,"hideReposts":true}]"#
    )
  }

  @Test func setThreadViewPrefsMergesLabField() async throws {
    let service = FakePreferencesService(
      rawJSON: #"[{"$type":"app.bsky.actor.defs#threadViewPref","sort":"hotness"}]"#)
    try await service.engine().setThreadViewPrefs(
      ThreadViewPrefPatch(lab_treeViewEnabled: true))
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#threadViewPref","lab_treeViewEnabled":true,"sort":"hotness"}]"#
    )
  }

  // MARK: - Profile / interests

  @Test func setPersonalDetailsWritesBirthDate() async throws {
    let service = FakePreferencesService()
    try await service.engine().setPersonalDetails(try TestJSON.date("2024-03-01T00:00:00.000Z").typed)
    #expect(service.preferencesJSON.contains("2024-03-01"))
    #expect(service.preferencesJSON.contains(PrefType.personalDetailsPref))
  }

  @Test func setPersonalDetailsNullClearsBirthDate() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#personalDetailsPref","birthDate":"2024-03-01T00:00:00.000Z"}]"#
    )
    try await service.engine().setPersonalDetails(nil)
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#personalDetailsPref"}]"#)
  }

  @Test func setInterestsPrefReplacesTags() async throws {
    let service = FakePreferencesService(
      rawJSON: #"[{"$type":"app.bsky.actor.defs#interestsPref","tags":["old"]}]"#)
    try await service.engine().setInterestsPref(tags: ["art", "music"])
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#interestsPref","tags":["art","music"]}]"#)
  }

  // MARK: - App state

  @Test func queueNudgesDeduplicates() async throws {
    let service = FakePreferencesService(
      rawJSON: #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref","queuedNudges":["a"]}]"#)
    try await service.engine().queueNudges(["a", "b"])
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref","queuedNudges":["a","b"]}]"#)
  }

  @Test func dismissNudgesSkipsWhenPrefAbsent() async throws {
    let service = FakePreferencesService()
    try await service.engine().dismissNudges(["a"])
    #expect(service.putCount == 0)
  }

  @Test func setIsBetaUserPreservesOtherAppState() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref","isBetaUser":false,"queuedNudges":["a"]}]"#
    )
    try await service.engine().setIsBetaUser(true)
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref","isBetaUser":true,"queuedNudges":["a"]}]"#
    )
  }

  @Test func setActiveProgressGuideWritesAndClears() async throws {
    let service = FakePreferencesService()
    try await service.engine().setActiveProgressGuide("com.example.guide")
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref","activeProgressGuide":{"guide":"com.example.guide"}}]"#
    )
    try await service.engine().setActiveProgressGuide(nil)
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref"}]"#)
  }

  @Test func upsertNuxInsertsThenUpdates() async throws {
    let service = FakePreferencesService()
    let nux = try TestJSON.object(#"{"id":"n1","completed":false}"#)
    try await service.engine().upsertNux(nux)
    #expect(service.preferencesJSON.contains(#""id":"n1""#))
    #expect(service.preferencesJSON.contains(#""completed":false"#))

    let updated = try TestJSON.object(#"{"id":"n1","completed":true}"#)
    try await service.engine().upsertNux(updated)
    #expect(service.preferencesJSON.contains(#""completed":true"#))
    #expect(service.preferencesJSON.components(separatedBy: #""id":"n1""#).count == 2)
  }

  @Test func upsertNuxRejectsUnknownProperty() async throws {
    let service = FakePreferencesService()
    let nux = try TestJSON.object(#"{"id":"n1","completed":false,"extra":1}"#)
    await #expect(throws: PreferencesError.self) {
      try await service.engine().upsertNux(nux)
    }
    #expect(service.putCount == 0)
  }

  @Test func removeNuxsFiltersById() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#bskyAppStatePref","nuxs":[{"id":"n1","completed":true},{"id":"n2","completed":false}]}]"#
    )
    try await service.engine().removeNuxs(["n1"])
    #expect(service.preferencesJSON.contains(#""id":"n2""#))
    #expect(!service.preferencesJSON.contains(#""id":"n1""#))
  }

  // MARK: - Other prefs

  @Test func setVerificationPrefsMerges() async throws {
    let service = FakePreferencesService()
    try await service.engine().setVerificationPrefs(VerificationPrefsPatch(hideBadges: true))
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#verificationPrefs","hideBadges":true}]"#)
  }

  @Test func setPostInteractionSettingsReplacesExplicitly() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#postInteractionSettingsPref","postgateEmbeddingRules":[{"$type":"app.bsky.feed.postgate#disableRule"}],"threadgateAllowRules":[{"$type":"app.bsky.feed.threadgate#followerRule"}]}]"#
    )
    // nil threadgate means "everyone": the key is dropped, not preserved.
    try await service.engine().setPostInteractionSettings(
      PostInteractionSettings(threadgateAllowRules: nil, postgateEmbeddingRules: nil))
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#postInteractionSettingsPref"}]"#)
  }

  @Test func updateLiveEventPreferencesTogglesAndTracksIds() async throws {
    let service = FakePreferencesService()
    try await service.engine().updateLiveEventPreferences(.hideFeed(id: "f1"))
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#liveEventPreferences","hiddenFeedIds":["f1"],"hideAllFeeds":false}]"#
    )
    try await service.engine().updateLiveEventPreferences(.unhideFeed(id: "f1"))
    try await service.engine().updateLiveEventPreferences(.toggleHideAllFeeds)
    #expect(
      service.preferencesJSON
        == #"[{"$type":"app.bsky.actor.defs#liveEventPreferences","hiddenFeedIds":[],"hideAllFeeds":true}]"#
    )
  }
}
