import Foundation
import Lexicons
import SwiftAtproto
import Testing

@testable import ComposerLogic

/// Threadgate and postgate record construction.
///
/// Ported from `state/queries/threadgate/util.ts` and
/// `state/queries/postgate/util.ts`.
@Suite("ComposerGates")
struct ComposerGatesTests {

  // MARK: - Threadgate record -> UI settings

  @Test("a missing record means anybody can reply")
  func missingRecordIsEverybody() {
    #expect(ComposerGates.allowUISettings(from: nil) == [.everybody])
  }

  @Test("an undefined allow list means anybody can reply")
  func undefinedAllowIsEverybody() throws {
    let record = try ComposerGates.createThreadgateRecord(post: "at://x/y/z", allow: nil)
    #expect(ComposerGates.allowUISettings(from: record) == [.everybody])
  }

  @Test("an empty allow list means nobody can reply")
  func emptyAllowIsNobody() throws {
    let record = try ComposerGates.createThreadgateRecord(post: "at://x/y/z", allow: [])
    #expect(ComposerGates.allowUISettings(from: record) == [.nobody])
  }

  @Test("each rule maps to its UI setting")
  func rulesMapToSettings() throws {
    let record = try ComposerGates.createThreadgateRecord(
      post: "at://x/y/z",
      allow: [
        .feedThreadgateMentionRule(.init()),
        .feedThreadgateFollowingRule(.init()),
        .feedThreadgateFollowerRule(.init()),
        .feedThreadgateListRule(.init(list: FormatString<ATURI>(rawValue: "at://did:plc:x/app.bsky.graph.list/l"))),
      ])
    #expect(
      ComposerGates.allowUISettings(from: record) == [
        .mention, .following, .followers, .list(uri: "at://did:plc:x/app.bsky.graph.list/l"),
      ])
  }

  // MARK: - UI settings -> record

  @Test("everybody produces a nil allow list")
  func everybodyProducesNil() {
    #expect(ComposerGates.allowRecordValue(from: [.everybody]) == nil)
  }

  @Test("nobody produces an empty allow list")
  func nobodyProducesEmpty() {
    #expect(ComposerGates.allowRecordValue(from: [.nobody])?.isEmpty == true)
  }

  @Test("everybody wins over other settings")
  func everybodyWins() {
    #expect(ComposerGates.allowRecordValue(from: [.followers, .everybody]) == nil)
  }

  @Test("nobody wins over other settings")
  func nobodyWins() {
    #expect(ComposerGates.allowRecordValue(from: [.followers, .nobody])?.isEmpty == true)
  }

  @Test("a rule list round-trips through the record shape")
  func rulesRoundTrip() throws {
    let settings: [ThreadgateAllowUISetting] = [
      .mention, .following, .followers,
      .list(uri: "at://did:plc:x/app.bsky.graph.list/l"),
    ]
    let allow = ComposerGates.allowRecordValue(from: settings)
    let record = try ComposerGates.createThreadgateRecord(post: "at://x/y/z", allow: allow)
    #expect(ComposerGates.allowUISettings(from: record) == settings)
  }

  @Test("the record carries the $type and the post URI")
  func recordShape() throws {
    let record = try ComposerGates.createThreadgateRecord(
      post: "at://did:plc:x/app.bsky.feed.post/r",
      allow: [.feedThreadgateFollowerRule(.init())],
      createdAt: Fixtures.fixedDate)
    let json = Fixtures.json(record.typed)
    #expect(json["$type"] as? String == "app.bsky.feed.threadgate")
    #expect(json["post"] as? String == "at://did:plc:x/app.bsky.feed.post/r")
    #expect(json["createdAt"] as? String == "2026-01-01T00:00:00.000Z")
    let allow = json["allow"] as? [[String: String]]
    #expect(allow?.first?["$type"] == "app.bsky.feed.threadgate#followerRule")
  }

  @Test("an empty post URI is rejected")
  func emptyPostRejected() {
    #expect(throws: ComposerGateError.missingPostUri) {
      _ = try ComposerGates.createThreadgateRecord(post: "")
    }
  }

  @Test("a list rule writes the list URI")
  func listRuleShape() throws {
    let record = try ComposerGates.createThreadgateRecord(
      post: "at://x/y/z",
      allow: [.feedThreadgateListRule(.init(list: FormatString<ATURI>(rawValue: "at://did:plc:x/app.bsky.graph.list/l")))])
    let json = Fixtures.json(record.typed)
    let allow = json["allow"] as? [[String: String]]
    #expect(allow?.first?["$type"] == "app.bsky.feed.threadgate#listRule")
    #expect(allow?.first?["list"] == "at://did:plc:x/app.bsky.graph.list/l")
  }

  // MARK: - Merging

  @Test("merging unions hidden replies and deduplicates allow rules")
  func mergeUnions() throws {
    let prev = try ComposerGates.createThreadgateRecord(
      post: "at://x/y/z", allow: [.feedThreadgateFollowerRule(.init())],
      hiddenReplies: ["at://a/1"])
    let merged = try ComposerGates.mergeThreadgateRecords(
      prev: prev,
      allow: [.feedThreadgateFollowerRule(.init()), .feedThreadgateMentionRule(.init())],
      hiddenReplies: ["at://a/1", "at://a/2"])
    #expect(merged.allow?.count == 2)
    #expect(merged.hiddenReplies?.map(\.rawValue) == ["at://a/1", "at://a/2"])
  }

  @Test("merging keeps a nil allow nil rather than collapsing it to empty")
  func mergeKeepsNilAllow() throws {
    let prev = try ComposerGates.createThreadgateRecord(post: "at://x/y/z", allow: nil)
    let merged = try ComposerGates.mergeThreadgateRecords(prev: prev)
    // `nil` means "everybody" and must not become `[]` ("nobody").
    #expect(merged.allow == nil)
  }

  // MARK: - Postgate

  @Test("the disable rule writes app.bsky.feed.postgate#disableRule")
  func disableRuleShape() throws {
    let record = try ComposerGates.createPostgateRecord(
      post: "at://did:plc:x/app.bsky.feed.post/r",
      embeddingRules: [ComposerGates.disableRule])
    let json = Fixtures.json(record.typed)
    #expect(json["$type"] as? String == "app.bsky.feed.postgate")
    #expect(json["post"] as? String == "at://did:plc:x/app.bsky.feed.post/r")
    let rules = json["embeddingRules"] as? [[String: String]]
    #expect(rules?.first?["$type"] == "app.bsky.feed.postgate#disableRule")
  }

  @Test("detached embedding URIs are written")
  func detachedUris() throws {
    let record = try ComposerGates.createPostgateRecord(
      post: "at://x/y/z", detachedEmbeddingUris: ["at://did:plc:q/app.bsky.feed.post/9"])
    let json = Fixtures.json(record.typed)
    #expect(json["detachedEmbeddingUris"] as? [String] == ["at://did:plc:q/app.bsky.feed.post/9"])
  }

  @Test("a placeholder postgate tolerates an empty post URI")
  func placeholderPostgate() {
    let record = ComposerGates.placeholderPostgateRecord()
    #expect(record.post.rawValue.isEmpty)
  }

  @Test("merging postgates unions detached URIs and deduplicates rules")
  func mergePostgates() throws {
    let prev = try ComposerGates.createPostgateRecord(
      post: "at://x/y/z",
      embeddingRules: [ComposerGates.disableRule],
      detachedEmbeddingUris: ["at://a/1"])
    let merged = ComposerGates.mergePostgateRecords(
      prev: prev,
      embeddingRules: [ComposerGates.disableRule],
      detachedEmbeddingUris: ["at://a/1", "at://a/2"])
    #expect(merged.embeddingRules?.count == 1)
    #expect(merged.detachedEmbeddingUris?.map(\.rawValue) == ["at://a/1", "at://a/2"])
    #expect(merged.post.rawValue == "at://x/y/z")
  }
}
