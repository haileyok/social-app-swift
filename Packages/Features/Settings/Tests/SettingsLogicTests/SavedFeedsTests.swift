import Foundation
import Testing

import ATProtoClient
import Preferences

@testable import SettingsLogic

/// The saved-feeds editor, ported from `screens/SavedFeeds.tsx`.
@Suite struct SavedFeedsEditorTests {

  /// The editor partitions pinned-first on construction.
  @Test func pinnedFirstPartition() {
    let editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "a", pinned: false),
      makeSavedFeed(id: "b", pinned: true),
      makeSavedFeed(id: "c", pinned: false),
      makeSavedFeed(id: "d", pinned: true),
    ])
    #expect(editor.items.map(\.id) == ["b", "d", "a", "c"])
    #expect(editor.pinned.map(\.id) == ["b", "d"])
    #expect(editor.unpinned.map(\.id) == ["a", "c"])
  }

  /// The partition is stable within each block.
  @Test func partitionPreservesRelativeOrder() {
    let editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "p1", pinned: true),
      makeSavedFeed(id: "p2", pinned: true),
      makeSavedFeed(id: "u1", pinned: false),
      makeSavedFeed(id: "u2", pinned: false),
    ])
    #expect(editor.items.map(\.id) == ["p1", "p2", "u1", "u2"])
  }

  /// Pinning an unpinned item moves it into the pinned block, at the end of it.
  @Test func togglePinnedMovesIntoBlock() {
    var editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "a", pinned: true),
      makeSavedFeed(id: "b", pinned: false),
    ])
    editor.togglePinned(id: "b")
    #expect(editor.items.map(\.id) == ["a", "b"])
    #expect(editor.pinned.map(\.id) == ["a", "b"])

    editor.togglePinned(id: "a")
    #expect(editor.items.map(\.id) == ["b", "a"])
    #expect(editor.pinned.map(\.id) == ["b"])
    #expect(editor.unpinned.map(\.id) == ["a"])
  }

  /// Toggling an unknown id is a no-op.
  @Test func togglePinnedUnknownId() {
    var editor = SavedFeedsEditor(items: [makeSavedFeed(id: "a", pinned: true)])
    editor.togglePinned(id: "nope")
    #expect(editor.items.map(\.id) == ["a"])
  }

  /// Only unpinned items are removable, matching the RN screen.
  @Test func removeOnlyUnpinned() {
    var editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "pinned", pinned: true),
      makeSavedFeed(id: "free", pinned: false),
    ])
    let removedFree = editor.remove(id: "free")
    #expect(removedFree)
    #expect(editor.items.map(\.id) == ["pinned"])

    // A pinned item cannot be removed through this path.
    let removedPinned = editor.remove(id: "pinned")
    #expect(!removedPinned)
    #expect(editor.items.map(\.id) == ["pinned"])
  }

  /// Moving a pinned item up swaps it with its predecessor.
  @Test func movePinnedUp() {
    var editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "a", pinned: true),
      makeSavedFeed(id: "b", pinned: true),
      makeSavedFeed(id: "c", pinned: true),
    ])
    let moved = editor.movePinnedUp(at: 2)
    #expect(moved)
    #expect(editor.pinned.map(\.id) == ["a", "c", "b"])
    // The first item cannot move up.
    let blocked = editor.movePinnedUp(at: 0)
    #expect(!blocked)
    #expect(editor.pinned.map(\.id) == ["a", "c", "b"])
  }

  /// Moving a pinned item down swaps it with its successor.
  @Test func movePinnedDown() {
    var editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "a", pinned: true),
      makeSavedFeed(id: "b", pinned: true),
      makeSavedFeed(id: "c", pinned: true),
    ])
    let moved = editor.movePinnedDown(at: 0)
    #expect(moved)
    #expect(editor.pinned.map(\.id) == ["b", "a", "c"])
    // The last item cannot move down.
    let blocked = editor.movePinnedDown(at: 2)
    #expect(!blocked)
  }

  /// An out-of-range move is a no-op rather than a crash.
  @Test func moveOutOfRange() {
    var editor = SavedFeedsEditor(items: [makeSavedFeed(id: "a", pinned: true)])
    let up = editor.movePinnedUp(at: 5)
    let down = editor.movePinnedDown(at: 5)
    #expect(!up)
    #expect(!down)
    #expect(editor.pinned.map(\.id) == ["a"])
  }

  /// A drag reorder replaces the pinned block and leaves the unpinned tail.
  @Test func reorderPinned() {
    var editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "a", pinned: true),
      makeSavedFeed(id: "b", pinned: true),
      makeSavedFeed(id: "c", pinned: false),
    ])
    let reordered = [editor.pinned[1], editor.pinned[0]]
    let changed = editor.reorderPinned(reordered)
    #expect(changed)
    #expect(editor.items.map(\.id) == ["b", "a", "c"])
  }

  /// A reorder that drops or adds an id is rejected, so a buggy drop cannot
  /// silently delete a feed.
  @Test func reorderPinnedRejectsWrongSet() {
    var editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "a", pinned: true),
      makeSavedFeed(id: "b", pinned: true),
    ])
    let dropped = editor.reorderPinned([editor.pinned[0]])
    let added = editor.reorderPinned(editor.pinned + [makeSavedFeed(id: "x", pinned: true)])
    #expect(!dropped)
    #expect(!added)
    #expect(editor.items.map(\.id) == ["a", "b"])
  }

  /// The dirty flag tracks edits against what was loaded.
  @Test func dirtyTracking() {
    var editor = SavedFeedsEditor(items: [
      makeSavedFeed(id: "a", pinned: true),
      makeSavedFeed(id: "b", pinned: false),
    ])
    #expect(!editor.hasUnsavedChanges)

    editor.togglePinned(id: "b")
    #expect(editor.hasUnsavedChanges)

    editor.discardChanges()
    #expect(!editor.hasUnsavedChanges)
    #expect(editor.items.map(\.id) == ["a", "b"])
  }

  /// Appending new items re-partitions, so a pinned addition lands in the
  /// pinned block.
  @Test func appendRepartitions() {
    var editor = SavedFeedsEditor(items: [makeSavedFeed(id: "a", pinned: false)])
    editor.append([makeSavedFeed(id: "b", pinned: true)])
    #expect(editor.items.map(\.id) == ["b", "a"])
  }

  /// The recommended set is the discover feed plus the following timeline, both
  /// pinned, in that order.
  @Test func recommendedItems() {
    var counter = 0
    let items = SavedFeedsEditor.recommendedItems(makeID: {
      counter += 1
      return "id-\(counter)"
    })
    #expect(items.count == 2)
    #expect(items[0].type == "feed")
    #expect(items[0].value == SettingsConstants.discoverFeedURI)
    #expect(items[0].isPinned)
    #expect(items[1].type == "timeline")
    #expect(items[1].value == "following")
    #expect(items[1].isPinned)
    #expect(items[0].id != items[1].id)
  }

  /// An empty list reports empty, which drives the empty state.
  @Test func emptyState() {
    let editor = SavedFeedsEditor(items: [])
    #expect(editor.isEmpty)
    #expect(editor.pinned.isEmpty)
    #expect(editor.unpinned.isEmpty)
  }

  /// An item decodes from and encodes back to the preference record shape.
  @Test func prefObjectRoundTrip() {
    let item = SavedFeedItem(
      id: "3abc", type: "feed",
      value: "at://did:plc:x/app.bsky.feed.generator/whats-hot", isPinned: true)
    let decoded = SavedFeedItem(pref: item.prefObject)
    #expect(decoded == item)
  }

  /// A record missing a required member does not decode.
  @Test func prefObjectMissingField() {
    #expect(SavedFeedItem(pref: PrefObject(fields: ["id": .string("x")])) == nil)
  }

  /// The type inference for a new item's value.
  @Test func typeInference() {
    #expect(SavedFeedItem.type(forValue: "following") == "timeline")
    #expect(
      SavedFeedItem.type(forValue: "at://did:plc:x/app.bsky.feed.generator/name") == "feed")
    #expect(SavedFeedItem.type(forValue: "at://did:plc:x/app.bsky.graph.list/name") == "list")
    #expect(SavedFeedItem.type(forValue: "not-a-uri") == nil)
  }
}

/// The store's saved-feeds operations, over a real `PreferencesEngine`.
@Suite struct SavedFeedsStoreTests {

  /// The store's editor reflects the loaded preferences.
  @Test func loadsFromPreferences() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"1","type":"timeline","value":"following","pinned":true},
          {"id":"2","type":"feed",
           "value":"at://did:plc:x/app.bsky.feed.generator/a","pinned":false}
        ]}]
        """)
    defer { harness.cleanUp() }

    await harness.store.loadPreferences()

    #expect(harness.store.savedFeeds.items.map(\.id) == ["1", "2"])
    #expect(harness.store.savedFeeds.pinned.map(\.id) == ["1"])
    #expect(!harness.store.savedFeeds.hasUnsavedChanges)
  }

  /// Edits are local: nothing is written until the save.
  @Test func editsAreLocalUntilSave() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"1","type":"timeline","value":"following","pinned":true},
          {"id":"2","type":"feed",
           "value":"at://did:plc:x/app.bsky.feed.generator/a","pinned":false}
        ]}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()
    let putsBefore = harness.prefsService.putCount

    harness.store.editSavedFeeds { $0.togglePinned(id: "2") }

    #expect(harness.store.savedFeeds.pinned.map(\.id) == ["1", "2"])
    #expect(harness.store.savedFeeds.hasUnsavedChanges)
    // No write happened.
    #expect(harness.prefsService.putCount == putsBefore)
  }

  /// Saving writes the arranged order in one `overwriteSavedFeeds` call, and
  /// the resulting stored order matches what the screen showed.
  @Test func saveWritesArrangedOrder() async throws {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"1","type":"timeline","value":"following","pinned":true},
          {"id":"2","type":"feed",
           "value":"at://did:plc:x/app.bsky.feed.generator/a","pinned":true},
          {"id":"3","type":"feed",
           "value":"at://did:plc:x/app.bsky.feed.generator/b","pinned":false}
        ]}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()
    let putsBefore = harness.prefsService.putCount

    // Move the second pinned feed above the first.
    harness.store.editSavedFeeds { $0.movePinnedUp(at: 1) }
    #expect(harness.store.savedFeeds.pinned.map(\.id) == ["2", "1"])

    try await harness.store.saveSavedFeeds()

    // Exactly one write, and it carried the new order.
    #expect(harness.prefsService.putCount == putsBefore + 1)
    #expect(TestJSON.savedFeedValues(harness.prefsService) == ["following", "", ""]
      || TestJSON.savedFeedValues(harness.prefsService).count == 3)
    #expect(TestJSON.savedFeedItems(harness.prefsService).compactMap { $0["id"] as? String }
      == ["2", "1", "3"])
    // After the write, the editor is clean again.
    #expect(!harness.store.savedFeeds.hasUnsavedChanges)
  }

  /// The engine re-partitions pinned-first on the way through, so the stored
  /// array always has the pinned block first even if the editor did not.
  @Test func engineOrdersPinnedFirst() async throws {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"1","type":"timeline","value":"following","pinned":true},
          {"id":"2","type":"feed",
           "value":"at://did:plc:x/app.bsky.feed.generator/a","pinned":false}
        ]}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    // Pin the second feed; the editor moves it into the pinned block.
    harness.store.editSavedFeeds { $0.togglePinned(id: "2") }
    try await harness.store.saveSavedFeeds()

    #expect(TestJSON.savedFeedItems(harness.prefsService).compactMap { $0["id"] as? String }
      == ["1", "2"])
    #expect(TestJSON.savedFeedPinned(harness.prefsService) == [true, true])
  }

  /// A removal is written through on save.
  @Test func saveRemoval() async throws {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"1","type":"timeline","value":"following","pinned":true},
          {"id":"2","type":"feed",
           "value":"at://did:plc:x/app.bsky.feed.generator/a","pinned":false}
        ]}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    harness.store.editSavedFeeds { $0.remove(id: "2") }
    try await harness.store.saveSavedFeeds()

    #expect(TestJSON.savedFeedItems(harness.prefsService).compactMap { $0["id"] as? String }
      == ["1"])
  }

  /// Discarding restores the loaded list.
  @Test func discardEdits() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"1","type":"timeline","value":"following","pinned":true}
        ]}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    harness.store.addRecommendedSavedFeeds()
    #expect(harness.store.savedFeeds.items.count == 3)

    harness.store.discardSavedFeedsEdits()
    #expect(harness.store.savedFeeds.items.map(\.id) == ["1"])
    #expect(!harness.store.savedFeeds.hasUnsavedChanges)
  }

  /// Seeding the recommended feeds adds both, pinned.
  ///
  /// Note the baseline: hydrating an empty preference array runs the engine's
  /// saved-feeds migration, which seeds the Following timeline as a pinned
  /// entry (`Hydrate.swift`). That is the RN behavior too, so the assertion
  /// starts from it.
  @Test func addRecommended() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()

    // The migration's seed.
    #expect(harness.store.savedFeeds.pinned.map(\.value) == ["following"])

    harness.store.addRecommendedSavedFeeds()

    #expect(harness.store.savedFeeds.pinned.count == 3)
    #expect(
      harness.store.savedFeeds.items.map(\.value)
        .contains(SettingsConstants.discoverFeedURI))
  }

  /// A save failure surfaces the generic contact error.
  @Test func saveFailureIsMapped() async {
    let harness = await StoreHarness(
      preferencesJSON: """
        [{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"1","type":"timeline","value":"following","pinned":true}
        ]}]
        """)
    defer { harness.cleanUp() }
    await harness.store.loadPreferences()
    harness.prefsService.failNext(
      with: XrpcError(rawCode: nil, message: "offline", status: -1))

    harness.store.editSavedFeeds { $0.togglePinned(id: "1") }
    var thrown: SettingsError?
    do {
      try await harness.store.saveSavedFeeds()
    } catch let error as SettingsError {
      thrown = error
    } catch {
      Issue.record("unexpected error type: \(error)")
    }

    #expect(thrown?.message == PreferencesWriteErrors.contactFailed)
    #expect(thrown?.raw == "offline")
  }
}
