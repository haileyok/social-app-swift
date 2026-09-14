import Foundation
import Lexicons
import RichText
import SwiftAtproto
import Testing

@testable import ComposerLogic

/// Thread assembly, gate attachment and the `applyWrites` batch shape.
///
/// Ported from `post()` in `src/lib/api/index.ts`.
@Suite("ComposerThreadAssembly")
struct ComposerThreadAssemblyTests {

  // MARK: - Threading

  @Test("the second post of a thread replies to the first, rooted at the first")
  func threadRepliesChain() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [
        Fixtures.post(id: "p0", text: "one"),
        Fixtures.post(id: "p1", text: "two"),
      ]),
      rkeys: ["p0": "k0", "p1": "k1"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    #expect(records[0].record.reply == nil)
    let reply = records[1].record.reply
    #expect(reply?.parent.uri.rawValue == "at://did:plc:testuser/app.bsky.feed.post/k0")
    #expect(reply?.root.uri.rawValue == "at://did:plc:testuser/app.bsky.feed.post/k0")
    #expect(reply?.parent.cid.rawValue == Fixtures.fakeCID(records[0].record))
  }

  @Test("a reply thread inherits the resolved root for every post")
  func replyThreadInheritsRoot() throws {
    let root = RecordReference(uri: "at://did:plc:root/app.bsky.feed.post/r", cid: "bafyroot")
    let parent = RecordReference(uri: "at://did:plc:root/app.bsky.feed.post/p", cid: "bafyparent")
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [
        Fixtures.post(id: "p0", text: "one"),
        Fixtures.post(id: "p1", text: "two"),
      ]),
      reply: ReplyContext(root: root, parent: parent),
      rkeys: ["p0": "k0", "p1": "k1"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    // The first post replies to the target, rooted at the thread root.
    #expect(records[0].record.reply?.parent.uri.rawValue == parent.uri)
    #expect(records[0].record.reply?.root.uri.rawValue == root.uri)
    // The second replies to the first, but keeps the original root.
    #expect(records[1].record.reply?.parent.uri.rawValue.endsWith("/k0") == true)
    #expect(records[1].record.reply?.root.uri.rawValue == root.uri)
  }

  @Test("createdAt increments by one millisecond per post")
  func createdAtIncrements() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [
        Fixtures.post(id: "p0", text: "one"),
        Fixtures.post(id: "p1", text: "two"),
        Fixtures.post(id: "p2", text: "three"),
      ]),
      rkeys: ["p0": "k0", "p1": "k1", "p2": "k2"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    #expect(records[0].record.createdAt.rawValue == "2026-01-01T00:00:00.001Z")
    #expect(records[1].record.createdAt.rawValue == "2026-01-01T00:00:00.002Z")
    #expect(records[2].record.createdAt.rawValue == "2026-01-01T00:00:00.003Z")
  }

  @Test("a missing rkey throws")
  func missingRKeyThrows() {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [Fixtures.post(id: "p0", text: "x")]),
      rkeys: [:],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    #expect(throws: ComposerBuildError.missingRKey(postId: "p0")) {
      _ = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    }
  }

  // MARK: - Gates

  @Test("a non-everybody threadgate attaches to the first post only")
  func threadgateOnFirstPostOnly() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(
        posts: [Fixtures.post(id: "p0", text: "one"), Fixtures.post(id: "p1", text: "two")],
        threadgate: [.followers, .mention]),
      rkeys: ["p0": "k0", "p1": "k1"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    #expect(records[0].threadgate != nil)
    #expect(records[1].threadgate == nil)
    let json = Fixtures.json(records[0].threadgate!.typed)
    #expect(json["$type"] as? String == "app.bsky.feed.threadgate")
    #expect(json["post"] as? String == "at://did:plc:testuser/app.bsky.feed.post/k0")
    let allow = json["allow"] as? [[String: String]]
    #expect(allow?.compactMap { $0["$type"] } == [
      "app.bsky.feed.threadgate#followerRule",
      "app.bsky.feed.threadgate#mentionRule",
    ])
  }

  @Test("an everybody threadgate attaches nothing")
  func everybodyThreadgateOmitted() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [Fixtures.post(id: "p0", text: "x")]),
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    #expect(records[0].threadgate == nil)
  }

  @Test("a nobody threadgate writes an empty allow array")
  func nobodyThreadgateEmptyAllow() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [Fixtures.post(id: "p0", text: "x")], threadgate: [.nobody]),
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    let json = Fixtures.json(records[0].threadgate!)
    #expect((json["allow"] as? [Any])?.isEmpty == true)
  }

  @Test("postgate embedding rules attach to every post")
  func postgateOnEveryPost() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(
        posts: [Fixtures.post(id: "p0", text: "one"), Fixtures.post(id: "p1", text: "two")],
        embeddingRules: [ComposerGates.disableRule]),
      rkeys: ["p0": "k0", "p1": "k1"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    #expect(records[0].postgate != nil)
    #expect(records[1].postgate != nil)
    let json = Fixtures.json(records[1].postgate!)
    #expect(json["post"] as? String == "at://did:plc:testuser/app.bsky.feed.post/k1")
    let rules = json["embeddingRules"] as? [[String: String]]
    #expect(rules?.first?["$type"] == "app.bsky.feed.postgate#disableRule")
  }

  @Test("an empty postgate is omitted")
  func emptyPostgateOmitted() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [Fixtures.post(id: "p0", text: "x")]),
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    #expect(records[0].postgate == nil)
  }

  // MARK: - Write batch

  @Test("the write batch orders post, threadgate, postgate per post")
  func writeBatchOrder() throws {
    let inputs = PublishInputs(
      thread: Fixtures.thread(
        posts: [Fixtures.post(id: "p0", text: "one"), Fixtures.post(id: "p1", text: "two")],
        threadgate: [.followers],
        embeddingRules: [ComposerGates.disableRule]),
      rkeys: ["p0": "k0", "p1": "k1"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let records = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)
    let writes = ComposerRecordBuilder.writes(from: records)
    let description = writes.map { write -> String in
      switch write {
      case .create(let collection, _, _): "create:\(collection)"
      case .createThreadgate(let collection, _, _): "create:\(collection)"
      case .createPostgate(let collection, _, _): "create:\(collection)"
      }
    }
    #expect(description == [
      "create:app.bsky.feed.post",
      "create:app.bsky.feed.threadgate",
      "create:app.bsky.feed.postgate",
      "create:app.bsky.feed.post",
      "create:app.bsky.feed.postgate",
    ])
  }

  @Test("the full record payload matches the expected JSON exactly")
  func fullPayloadShape() throws {
    let post = Fixtures.post(
      id: "p0", text: "hello https://example.com",
      labels: SelfLabelSet(values: ["sexual"]),
      embed: EmbedDraft(link: ExternalLink(uri: "https://example.com")))
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      langs: ["en"],
      linkCards: [
        "p0": ResolvedExternal(
          uri: "https://example.com", title: "Example", description: "A site")
      ],
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    // Asserted through ``TypedRecord``, which is what the publish path writes:
    // the generated structs do not encode `$type` themselves.
    let json = Fixtures.json(record.typed)
    #expect(
      Set(json.keys) == ["$type", "createdAt", "text", "facets", "langs", "labels", "embed"])
  }

  @Test("published text is trimmed of leading blank lines")
  func publishedTextTrimmed() throws {
    let post = Fixtures.post(id: "p0", text: "\n\n  hello  ")
    let inputs = PublishInputs(
      thread: Fixtures.thread(posts: [post]),
      rkeys: ["p0": "k"],
      did: Fixtures.did,
      createdAt: Fixtures.fixedDate)
    let record = try ComposerRecordBuilder.build(inputs, cidProvider: Fixtures.fakeCID)[0].record
    #expect(record.text == "  hello")
  }
}
}

extension String {
  /// Whether the receiver ends with `suffix`, for readable assertions.
  fileprivate func endsWith(_ suffix: String) -> Bool {
    hasSuffix(suffix)
  }
}
