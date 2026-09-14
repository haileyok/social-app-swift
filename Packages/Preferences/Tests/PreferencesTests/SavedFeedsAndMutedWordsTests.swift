import Foundation
import Testing

import SwiftAtproto

@testable import Preferences

/// Muted-word action semantics: id minting, legacy-id backfill, matching by
/// id (preferred) or value, and value sanitization.
@Suite struct MutedWordTests {

  @Test func addMutedWordSanitizesAndMintsId() async throws {
    let service = FakePreferencesService()
    try await service.engine().addMutedWord(
      MutedWordInput(value: "  #spam  ", targets: ["content"]))
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"actorTarget":"all","id":"3000000000000","targets":["content"],"value":"spam"}]}]"#
    )
  }

  @Test func addMutedWordDropsEmptyValue() async throws {
    let service = FakePreferencesService()
    try await service.engine().addMutedWord(MutedWordInput(value: "   "))
    #expect(service.putCount == 0)
  }

  @Test func addMutedWordBackfillsLegacyIds() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"value":"legacy","targets":["content"],"actorTarget":"all"}]}]"#
    )
    try await service.engine().addMutedWord(MutedWordInput(value: "new", targets: ["content"]))
    // The legacy item gains an id; the new item keeps the next one.
    #expect(service.preferencesJSON.contains(#""id":"3000000000000""#))
    #expect(service.preferencesJSON.contains(#""value":"legacy""#))
    #expect(service.preferencesJSON.contains(#""value":"new""#))
  }

  @Test func updateMutedWordMatchesById() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"id":"a","value":"one","targets":["content"],"actorTarget":"all"},{"id":"b","value":"two","targets":["content"],"actorTarget":"all"}]}]"#
    )
    let updated = try TestJSON.object(#"{"id":"a","value":"one-updated","targets":["tag"]}"#)
    try await service.engine().updateMutedWord(updated)
    #expect(service.preferencesJSON.contains(#""value":"one-updated""#))
    #expect(service.preferencesJSON.contains(#""value":"two""#))
    #expect(service.preferencesJSON.contains(#""targets":["tag"]"#))
  }

  @Test func updateMutedWordFallsBackToValueMatchForLegacy() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"value":"legacy","targets":["content"],"actorTarget":"all"}]}]"#
    )
    let updated = try TestJSON.object(#"{"value":"legacy","targets":["tag"]}"#)
    try await service.engine().updateMutedWord(updated)
    #expect(service.preferencesJSON.contains(#""targets":["tag"]"#))
  }

  @Test func removeMutedWordMatchesFirstByIdOrValue() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"id":"a","value":"one","targets":["content"],"actorTarget":"all"},{"id":"b","value":"two","targets":["content"],"actorTarget":"all"}]}]"#
    )
    try await service.engine().removeMutedWord(try TestJSON.object(#"{"id":"a"}"#))
    #expect(!service.preferencesJSON.contains(#""id":"a""#))
    #expect(service.preferencesJSON.contains(#""id":"b""#))
  }

  @Test func removeMutedWordWithoutPrefWritesUnchanged() async throws {
    // The SDK's removeMutedWord returns `prefs` (not `false`) when there is no
    // mutedWordsPref, so the cycle still writes the unchanged array.
    let service = FakePreferencesService()
    try await service.engine().removeMutedWord(try TestJSON.object(#"{"id":"a"}"#))
    #expect(service.putCount == 1)
    #expect(service.preferencesJSON == "[]")
  }

  @Test func addMutedWordsAppliesInOrder() async throws {
    let service = FakePreferencesService()
    try await service.engine().addMutedWords([
      MutedWordInput(value: "one", targets: ["content"]),
      MutedWordInput(value: "two", targets: ["content"]),
    ])
    // Two sequential cycles; both words survive.
    #expect(service.preferencesJSON.contains(#""value":"one""#))
    #expect(service.preferencesJSON.contains(#""value":"two""#))
    #expect(service.putCount == 2)
  }

  @Test func sanitizeStripsHashAndControlChars() {
    #expect(MutedWords.sanitize("  #word ") == "word")
    #expect(MutedWords.sanitize("#\u{FE0F}kept") == "#\u{FE0F}kept")
    #expect(MutedWords.sanitize("a\u{200B}b") == "ab")
  }
}

/// Saved-feeds v2 semantics: id minting, pinned-first ordering, the v1
/// double-write, and legacy `savedFeedsPref` actions.
@Suite struct SavedFeedsTests {

  @Test func addSavedFeedsMintsIdsAndOrdersPinnedFirst() async throws {
    let service = FakePreferencesService()
    try await service.engine().addSavedFeeds([
      SavedFeedInput(
        type: "feed", value: "at://did:plc:a/app.bsky.feed.generator/x", pinned: false),
      SavedFeedInput(
        type: "feed", value: "at://did:plc:a/app.bsky.feed.generator/y", pinned: true),
    ])
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[{"id":"3000000000001","pinned":true,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/y"},{"id":"3000000000000","pinned":false,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"}]}]"#
    )
  }

  @Test func removeSavedFeedsFiltersById() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[{"id":"a","pinned":true,"type":"feed","value":"at://x/a"},{"id":"b","pinned":false,"type":"feed","value":"at://x/b"}]}]"#
    )
    try await service.engine().removeSavedFeeds(["a"])
    #expect(!service.preferencesJSON.contains(#""id":"a""#))
    #expect(service.preferencesJSON.contains(#""id":"b""#))
  }

  @Test func updateSavedFeedsOnlyChangesPinned() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[{"id":"a","pinned":false,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"}]}]"#
    )
    try await service.engine().updateSavedFeeds([
      try TestJSON.object(
        #"{"id":"a","pinned":true,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"}"#
      )
    ])
    #expect(service.preferencesJSON.contains(#""pinned":true"#))
    #expect(service.preferencesJSON.contains(#""id":"a""#))
  }

  @Test func overwriteSavedFeedsDedupesKeepingLastPosition() async throws {
    let service = FakePreferencesService()
    try await service.engine().overwriteSavedFeeds([
      try TestJSON.object(
        #"{"id":"a","pinned":false,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"}"#
      ),
      try TestJSON.object(
        #"{"id":"b","pinned":false,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/y"}"#
      ),
      try TestJSON.object(
        #"{"id":"a","pinned":true,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"}"#
      ),
    ])
    // "a" appears once, at the last position; pinned-first ordering follows.
    #expect(service.preferencesJSON == #"""
    [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[{"id":"a","pinned":true,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/x"},{"id":"b","pinned":false,"type":"feed","value":"at://did:plc:a/app.bsky.feed.generator/y"}]}]
    """#)
  }

  @Test func savedFeedValidationRejectsWrongCollection() async throws {
    let service = FakePreferencesService()
    await #expect(throws: PreferencesError.self) {
      try await service.engine().addSavedFeeds([
        SavedFeedInput(type: "feed", value: "at://did:plc:a/app.bsky.graph.list/x", pinned: true)
      ])
    }
    #expect(service.putCount == 0)
  }

  @Test func savedFeedValidationRejectsMissingId() async throws {
    let service = FakePreferencesService()
    await #expect(throws: PreferencesError.self) {
      try await service.engine().overwriteSavedFeeds([
        try TestJSON.object(#"{"pinned":true,"type":"timeline","value":"following"}"#)
      ])
    }
    #expect(service.putCount == 0)
  }

  // MARK: - v1 double-write

  @Test func v2WriteDoubleWritesExistingV1Pref() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[]},{"$type":"app.bsky.actor.defs#savedFeedsPref","pinned":["at://did:plc:a/app.bsky.feed.generator/old"],"saved":["at://did:plc:a/app.bsky.feed.generator/old"]}]"#
    )
    try await service.engine().addSavedFeeds([
      SavedFeedInput(
        type: "feed", value: "at://did:plc:a/app.bsky.feed.generator/new", pinned: true)
    ])
    // v1 gains the new URI in both pinned and saved; v2 has the item.
    #expect(service.preferencesJSON.contains(#""$type":"app.bsky.actor.defs#savedFeedsPref""#))
    #expect(service.preferencesJSON.contains("at://did:plc:a/app.bsky.feed.generator/new"))
    #expect(service.preferencesJSON.contains("at://did:plc:a/app.bsky.feed.generator/old"))
    #expect(
      service.preferencesJSON.contains(#""$type":"app.bsky.actor.defs#savedFeedsPrefV2""#))
  }

  @Test func v2WriteIgnoresTimelineInV1CompatArrays() async throws {
    let service = FakePreferencesService(
      rawJSON:
        #"[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[]},{"$type":"app.bsky.actor.defs#savedFeedsPref","pinned":[],"saved":[]}]"#
    )
    try await service.engine().overwriteSavedFeeds([
      try TestJSON.object(#"{"id":"a","pinned":true,"type":"timeline","value":"following"}"#)
    ])
    // The timeline entry is not v1-compatible, so v1 arrays stay empty.
    #expect(
      service.preferencesJSON.contains(
        #""$type":"app.bsky.actor.defs#savedFeedsPref","pinned":[],"saved":[]"#))
  }

  // MARK: - Legacy actions

  @Test func addPinnedFeedCreatesV1Pref() async throws {
    let service = FakePreferencesService()
    try await service.engine().addPinnedFeed("at://did:plc:a/app.bsky.feed.generator/x")
    #expect(
      service.preferencesJSON == #"[{"$type":"app.bsky.actor.defs#savedFeedsPref","pinned":["at://did:plc:a/app.bsky.feed.generator/x"],"saved":["at://did:plc:a/app.bsky.feed.generator/x"]}]"#
    )
  }

  @Test func removePinnedFeedSkipsWhenPrefAbsent() async throws {
    let service = FakePreferencesService()
    try await service.engine().removePinnedFeed("at://x/a")
    #expect(service.putCount == 0)
  }
}
