import Foundation
import Moderation
import Preferences
import SwiftAtproto
import Testing

@testable import ModerationUILogic

/// Port of the submit and row paths in
/// `src/components/dialogs/MutedWords.tsx`, driven against the real
/// `PreferencesEngine` over the package's fake preferences server, so the
/// assertions are on the exact `putPreferences` payloads.
@Suite("Muted words editor")
struct MutedWordsEditorTests {

  /// A fixed instant, so `expiresAt` is deterministic.
  private let now = ISO8601DateFormatter().date(from: "2026-03-01T12:00:00Z")!

  private func draft(
    _ value: String, surfaces: Set<MutedWordSurface> = [.content],
    excludeFollowing: Bool = false, duration: MutedWordDuration = .forever
  ) -> MutedWordDraft {
    MutedWordDraft(
      rawValue: value, surfaces: surfaces, excludeFollowing: excludeFollowing,
      duration: duration, now: now)
  }

  // MARK: - Payload construction

  @Test("the default payload targets tag then content")
  func defaultTargets() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto"))
    #expect(payload.targets == [.tag, .content])
  }

  @Test("tags-only drafts target tag only")
  func tagsOnlyTargets() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto", surfaces: [.tag]))
    #expect(payload.targets == [.tag])
    #expect(MutedWordsEditor.targets(for: [.tag]) == ["tag"])
  }

  @Test("the actor target defaults to all")
  func actorTargetDefaultsToAll() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto"))
    #expect(payload.actorTarget == .all)
  }

  @Test("exclude-following drafts set the actor target")
  func excludeFollowingTarget() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto", excludeFollowing: true))
    #expect(payload.actorTarget == .excludeFollowing)
    #expect(MutedWordsEditor.targets(for: [.content]) == ["tag", "content"])
  }

  @Test("a forever duration mints no expiry")
  func foreverNoExpiry() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto", duration: .forever))
    #expect(payload.expiresAt == nil)
  }

  @Test("a 24-hour duration expires one day out")
  func twentyFourHourExpiry() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto", duration: .hours24))
    #expect(MutedWordsEditor.parseISO(payload.expiresAt) == now.addingTimeInterval(86_400))
  }

  @Test("a 7-day duration expires seven days out")
  func sevenDayExpiry() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto", duration: .days7))
    #expect(MutedWordsEditor.parseISO(payload.expiresAt) == now.addingTimeInterval(7 * 86_400))
  }

  @Test("a 30-day duration expires thirty days out")
  func thirtyDayExpiry() throws {
    let payload = try MutedWordsEditor.payload(for: draft("crypto", duration: .days30))
    #expect(MutedWordsEditor.parseISO(payload.expiresAt) == now.addingTimeInterval(30 * 86_400))
  }

  @Test("the duration day counts match RN's radios")
  func durationDayCounts() {
    #expect(MutedWordDuration.forever.days == nil)
    #expect(MutedWordDuration.hours24.days == 1)
    #expect(MutedWordDuration.days7.days == 7)
    #expect(MutedWordDuration.days30.days == 30)
  }

  // MARK: - Validation

  @Test("an empty value is rejected")
  func emptyValueRejected() {
    #expect(throws: MutedWordsEditor.ValidationError.emptyValueOrNoSurface) {
      try MutedWordsEditor.payload(for: draft("   "))
    }
  }

  @Test("a value that sanitizes to empty is rejected")
  func zeroWidthValueRejected() {
    #expect(throws: MutedWordsEditor.ValidationError.emptyValueOrNoSurface) {
      try MutedWordsEditor.payload(for: draft("\u{200B}\u{200B}"))
    }
  }

  @Test("a draft with no selected surfaces still mutes in tags only")
  func noSurfaceFallsBackToTags() throws {
    // RN builds `surfaces` as `['tag', ...]`, so its `!surfaces.length` guard is
    // unreachable; a no-selection draft is still a valid tags-only mute.
    let payload = try MutedWordsEditor.payload(for: draft("crypto", surfaces: []))
    #expect(payload.targets == [.tag])
  }

  @Test("an empty draft cannot be submitted")
  func canSubmitEmpty() {
    #expect(!MutedWordsEditor.canSubmit(draft("")))
    #expect(MutedWordsEditor.canSubmit(draft("crypto")))
    // A no-selection draft is still submittable, matching the tags-only fallback.
    #expect(MutedWordsEditor.canSubmit(draft("crypto", surfaces: [])))
  }

  @Test("the empty-value message matches RN's copy")
  func emptyValueMessage() {
    #expect(MutedWordsEditor.emptyValueMessage == "Please enter a valid word, tag, or phrase to mute")
  }

  @Test("the raw value is sent, not the sanitized one")
  func rawValueSent() throws {
    // RN comment: "send raw value and rely on SDK as sanitization source of truth".
    let payload = try MutedWordsEditor.payload(for: draft("  crypto  "))
    #expect(payload.value == "  crypto  ")
  }

  // MARK: - CRUD against the real engine

  @Test("adding a muted word writes the expected items array")
  func addWritesItems() async throws {
    let server = ScriptedXRPC()
    let engine = server.preferencesEngine()
    let payload = try MutedWordsEditor.payload(for: draft("crypto"))

    try await engine.update(
      try PreferencesAction.addMutedWord(
        MutedWordInput(
          value: payload.value,
          targets: payload.targets.map(\.rawValue),
          actorTarget: payload.actorTarget?.rawValue,
          expiresAt: payload.expiresAt.flatMap { FormatString<Date>(rawValue: $0) })
      ).patch(tids: SequentialTidGenerator()))

    let json = server.preferencesJSON
    #expect(json.contains("app.bsky.actor.defs#mutedWordsPref"))
    #expect(json.contains(#""value":"crypto""#))
    #expect(json.contains(#""targets":["tag","content"]"#))
    #expect(json.contains(#""actorTarget":"all""#))
    // The engine mints an id on write.
    #expect(json.contains(#""id":"#))
  }

  @Test("adding a sanitizes the stored value")
  func addSanitizesStoredValue() async throws {
    let server = ScriptedXRPC()
    let engine = server.preferencesEngine()
    let payload = try MutedWordsEditor.payload(for: draft("#crypto"))

    try await engine.update(
      try PreferencesAction.addMutedWord(
        MutedWordInput(
          value: payload.value,
          targets: payload.targets.map(\.rawValue),
          actorTarget: payload.actorTarget?.rawValue)
      ).patch(tids: SequentialTidGenerator()))

    // The leading `#` is stripped by the engine's sanitizer.
    #expect(server.preferencesJSON.contains(#""value":"crypto""#))
  }

  @Test("adding an expiry-bearing word writes expiresAt")
  func addWritesExpiry() async throws {
    let server = ScriptedXRPC()
    let engine = server.preferencesEngine()
    let payload = try MutedWordsEditor.payload(for: draft("crypto", duration: .days7))

    try await engine.update(
      try PreferencesAction.addMutedWord(
        MutedWordInput(
          value: payload.value, targets: payload.targets.map(\.rawValue),
          actorTarget: payload.actorTarget?.rawValue,
          expiresAt: payload.expiresAt.flatMap { FormatString<Date>(rawValue: $0) })
      ).patch(tids: SequentialTidGenerator()))

    #expect(server.preferencesJSON.contains(#""expiresAt":"#))
  }

  @Test("adding a blank word performs no write")
  func addBlankSkipsWrite() async throws {
    let server = ScriptedXRPC()
    let engine = server.preferencesEngine()

    let result = try await engine.update(
      try PreferencesAction.addMutedWord(
        MutedWordInput(value: "   ", targets: ["tag"], actorTarget: "all")
      ).patch(tids: SequentialTidGenerator()))

    if case .skipped = result {} else {
      Issue.record("expected the patch to be skipped, got \(result)")
    }
    #expect(server.requests("app.bsky.actor.putPreferences").isEmpty)
  }

  @Test("removing a muted word drops it from the array")
  func removeDropsWord() async throws {
    let server = ScriptedXRPC()
    server.setPreferences(
      #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"id":"3a","value":"crypto","targets":["tag","content"],"actorTarget":"all"},{"id":"3b","value":"nft","targets":["tag"],"actorTarget":"all"}]}]"#
    )
    let engine = server.preferencesEngine()

    try await engine.update(
      try PreferencesAction.removeMutedWord(
        MutedWordsEditor.record(id: "3a", value: "crypto")
      ).patch(tids: SequentialTidGenerator()))

    let json = server.preferencesJSON
    #expect(!json.contains(#""value":"crypto""#))
    #expect(json.contains(#""value":"nft""#))
  }

  @Test("updating a muted word rewrites its expiry and keeps its id")
  func updateRewritesExpiry() async throws {
    let server = ScriptedXRPC()
    server.setPreferences(
      #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"id":"3a","value":"crypto","targets":["tag"],"actorTarget":"all","expiresAt":"2020-01-01T00:00:00.000Z"}]}]"#
    )
    let engine = server.preferencesEngine()

    let renewed = MutedWordsEditor.renewed(
      MutedWord(
        value: "crypto", targets: [.tag], actorTarget: .all,
        expiresAt: "2020-01-01T00:00:00.000Z"),
      days: 30, from: now)
    let record = MutedWordsEditor.record(
      id: "3a", value: "crypto", targets: ["tag"], actorTarget: "all",
      expiresAt: renewed.expiresAt)

    try await engine.update(
      try PreferencesAction.updateMutedWord(record).patch(tids: SequentialTidGenerator()))

    let json = server.preferencesJSON
    #expect(json.contains(#""id":"3a""#))
    #expect(!json.contains("2020-01-01"))
    #expect(json.contains("2026-03-31"))
  }

  @Test("renewing to forever clears the expiry")
  func renewForeverClearsExpiry() {
    let renewed = MutedWordsEditor.renewed(
      MutedWord(value: "crypto", targets: [.tag], expiresAt: "2020-01-01T00:00:00.000Z"),
      days: nil, from: now)
    #expect(renewed.expiresAt == nil)
  }

  @Test("legacy words without an id are migrated on write")
  func legacyMigration() async throws {
    let server = ScriptedXRPC()
    server.setPreferences(
      #"[{"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"value":"legacy","targets":["tag"]}]}]"#
    )
    let engine = server.preferencesEngine()

    try await engine.update(
      try PreferencesAction.addMutedWord(
        MutedWordInput(value: "crypto", targets: ["tag"], actorTarget: "all")
      ).patch(tids: SequentialTidGenerator()))

    let json = server.preferencesJSON
    // Both the legacy entry and the new one carry an id after the write.
    #expect(json.components(separatedBy: #""id":"#).count - 1 == 2)
  }

  // MARK: - Row derivation

  @Test("a content-targeting word reports appliesToContent")
  func rowAppliesToContent() {
    let rows = MutedWordsEditor.rows(
      [MutedWord(value: "crypto", targets: [.tag, .content])], now: now)
    #expect(rows.first?.appliesToContent == true)
  }

  @Test("a tags-only word does not report appliesToContent")
  func rowTagsOnly() {
    let rows = MutedWordsEditor.rows([MutedWord(value: "crypto", targets: [.tag])], now: now)
    #expect(rows.first?.appliesToContent == false)
  }

  @Test("rows are newest first")
  func rowsReversed() {
    let rows = MutedWordsEditor.rows(
      [
        MutedWord(value: "first", targets: [.tag]),
        MutedWord(value: "second", targets: [.tag]),
      ], now: now)
    #expect(rows.map(\.word.value) == ["second", "first"])
  }

  @Test("an expiry in the past marks the row expired")
  func rowExpired() {
    let rows = MutedWordsEditor.rows(
      [MutedWord(value: "old", targets: [.tag], expiresAt: "2020-01-01T00:00:00.000Z")],
      now: now)
    #expect(rows.first?.isExpired == true)
  }

  @Test("an expiry in the future leaves the row live")
  func rowNotExpired() {
    let rows = MutedWordsEditor.rows(
      [MutedWord(value: "new", targets: [.tag], expiresAt: "2030-01-01T00:00:00.000Z")],
      now: now)
    #expect(rows.first?.isExpired == false)
  }

  @Test("a word with no expiry is never expired")
  func rowNoExpiry() {
    let rows = MutedWordsEditor.rows([MutedWord(value: "forever", targets: [.tag])], now: now)
    #expect(rows.first?.isExpired == false)
    #expect(rows.first?.expiryDate == nil)
  }

  @Test("the row carries excludesFollowing")
  func rowExcludesFollowing() {
    let rows = MutedWordsEditor.rows(
      [MutedWord(value: "crypto", targets: [.tag], actorTarget: .excludeFollowing)], now: now)
    #expect(rows.first?.excludesFollowing == true)
  }

  @Test("rows pick up the stored id from the raw preference items")
  func rowIdFromItems() throws {
    let items: [PrefObject] = [
      try TestJSON.object(#"{"id":"3a","value":"crypto","targets":["tag"]}"#)
    ]
    let rows = MutedWordsEditor.rows(
      [MutedWord(value: "crypto", targets: [.tag])], items: items, now: now)
    #expect(rows.first?.id == "3a")
  }
}
