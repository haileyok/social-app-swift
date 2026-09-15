import Foundation
import Lexicons
import Testing

@testable import StarterPacksLogic

/// Asserts the exact JSON the record builders produce.
///
/// Every expectation is a canonical (sorted-key) JSON string, so a field that is
/// added, dropped, renamed, or re-ordered fails the test. The point is to pin the
/// wire payloads RN sends, not to round-trip a type.
@Suite("StarterPackRecords")
struct StarterPackRecordsTests {
  @Test("the list record carries purpose, name and createdAt and omits absent members")
  func listRecordShape() {
    let record = StarterPackRecords.listRecord(
      name: "Bluesky for Art History",
      description: nil,
      descriptionFacets: nil,
      createdAt: "2026-08-31T00:00:00.000Z")

    #expect(
      Fixtures.canonical(record)
        == #"{"$type":"app.bsky.graph.list","createdAt":"2026-08-31T00:00:00.000Z","name":"Bluesky for Art History","purpose":"app.bsky.graph.defs#referencelist"}"#
    )
  }

  @Test("the list record includes a description and facets when present")
  func listRecordWithDescription() {
    let record = StarterPackRecords.listRecord(
      name: "Pack",
      description: "A description",
      descriptionFacets: [.object(["index": .object(["byteStart": .int(0)])])],
      createdAt: "2026-08-31T00:00:00.000Z")

    #expect(
      Fixtures.canonical(record)
        == #"{"$type":"app.bsky.graph.list","createdAt":"2026-08-31T00:00:00.000Z","description":"A description","descriptionFacets":[{"index":{"byteStart":0}}],"name":"Pack","purpose":"app.bsky.graph.defs#referencelist"}"#
    )
  }

  @Test("an empty description is omitted, not written as an empty string")
  func listRecordEmptyDescription() {
    let record = StarterPackRecords.listRecord(
      name: "Pack", description: "", descriptionFacets: nil,
      createdAt: "2026-08-31T00:00:00.000Z")
    #expect(Fixtures.canonical(record).contains(#""description""#) == false)
  }

  @Test("the created pack record references the list and maps feeds to uri refs")
  func createRecordShape() {
    let record = StarterPackRecords.createRecord(
      StarterPackRecords.StarterPackCreateRecordInput(
        name: "Bluesky for Art History",
        description: nil,
        listURI: "at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e",
        feedURIs: ["at://did:plc:feeds/app.bsky.feed.generator/whats-hot"],
        createdAt: "2026-08-31T00:00:00.000Z"))

    #expect(
      Fixtures.canonical(record)
        == #"{"$type":"app.bsky.graph.starterpack","createdAt":"2026-08-31T00:00:00.000Z","feeds":[{"uri":"at://did:plc:feeds/app.bsky.feed.generator/whats-hot"}],"list":"at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e","name":"Bluesky for Art History"}"#
    )
  }

  @Test("the created pack record omits feeds entirely when none were chosen")
  func createRecordWithoutFeeds() {
    let record = StarterPackRecords.createRecord(
      StarterPackRecords.StarterPackCreateRecordInput(
        name: "Pack",
        description: nil,
        listURI: "at://did:plc:author/app.bsky.graph.list/1",
        feedURIs: [],
        createdAt: "2026-08-31T00:00:00.000Z"))
    #expect(Fixtures.canonical(record).contains(#""feeds""#) == false)
  }

  @Test("the edited record carries createdAt through and adds updatedAt")
  func editRecordShape() {
    let record = StarterPackRecords.editRecord(
      StarterPackRecords.StarterPackEditRecordInput(
        name: "Renamed",
        description: nil,
        listURI: "at://did:plc:author/app.bsky.graph.list/1",
        feeds: [.object(["uri": .string("at://did:plc:feeds/app.bsky.feed.generator/a")])],
        createdAt: "2024-09-22T03:52:03.686Z",
        updatedAt: "2026-08-31T00:00:00.000Z"))

    #expect(
      Fixtures.canonical(record)
        == #"{"$type":"app.bsky.graph.starterpack","createdAt":"2024-09-22T03:52:03.686Z","feeds":[{"uri":"at://did:plc:feeds/app.bsky.feed.generator/a"}],"list":"at://did:plc:author/app.bsky.graph.list/1","name":"Renamed","updatedAt":"2026-08-31T00:00:00.000Z"}"#
    )
  }

  @Test("the edited record writes whole generator views, matching RN's quirk")
  func editRecordWritesViews() {
    let view = Fixtures.json([
      "$type": .string("app.bsky.feed.defs#generatorView"),
      "uri": .string("at://did:plc:feeds/app.bsky.feed.generator/a"),
      "displayName": .string("Cool"),
    ])
    let record = StarterPackRecords.editRecord(
      StarterPackRecords.StarterPackEditRecordInput(
        name: "Pack", description: nil, listURI: nil, feeds: [view],
        createdAt: "2024-09-22T03:52:03.686Z", updatedAt: "2026-08-31T00:00:00.000Z"))
    let expected =
      #"{"$type":"app.bsky.graph.starterpack","createdAt":"2024-09-22T03:52:03.686Z","feeds":[{"$type":"app.bsky.feed.defs#generatorView","displayName":"Cool","uri":"at://did:plc:feeds/app.bsky.feed.generator/a"}],"name":"Pack","updatedAt":"2026-08-31T00:00:00.000Z"}"#
    #expect(Fixtures.canonical(record) == expected)
  }

  @Test("the edited record omits list when the pack has none")
  func editRecordWithoutList() {
    let record = StarterPackRecords.editRecord(
      StarterPackRecords.StarterPackEditRecordInput(
        name: "Pack", description: nil, listURI: nil, feeds: [],
        createdAt: "2024-09-22T03:52:03.686Z", updatedAt: "2026-08-31T00:00:00.000Z"))
    #expect(Fixtures.canonical(record).contains(#""list""#) == false)
  }

  @Test("a list-item create write allows the server to mint the rkey")
  func listItemWriteWithoutRkey() {
    let write = StarterPackRecords.listItemWrite(
      subject: Fixtures.memberDID,
      listURI: "at://did:plc:author/app.bsky.graph.list/1",
      createdAt: "2026-08-31T00:00:00.000Z")

    #expect(
      Fixtures.canonical(write)
        == #"{"$type":"com.atproto.repo.applyWrites#create","collection":"app.bsky.graph.listitem","value":{"$type":"app.bsky.graph.listitem","createdAt":"2026-08-31T00:00:00.000Z","list":"at://did:plc:author/app.bsky.graph.list/1","subject":"did:plc:member"}}"#
    )
  }

  @Test("a list-item create write carries an explicit rkey when given one")
  func listItemWriteWithRkey() {
    let write = StarterPackRecords.listItemWrite(
      subject: Fixtures.memberDID,
      listURI: "at://did:plc:author/app.bsky.graph.list/1",
      rkey: "3abc",
      createdAt: "2026-08-31T00:00:00.000Z")

    #expect(
      Fixtures.canonical(write)
        == #"{"$type":"com.atproto.repo.applyWrites#create","collection":"app.bsky.graph.listitem","rkey":"3abc","value":{"$type":"app.bsky.graph.listitem","createdAt":"2026-08-31T00:00:00.000Z","list":"at://did:plc:author/app.bsky.graph.list/1","subject":"did:plc:member"}}"#
    )
  }

  @Test("a list-item delete write is addressed by rkey and carries no value")
  func listItemDeleteWrite() {
    let write = StarterPackRecords.listItemDeleteWrite(rkey: "3abc")
    #expect(
      Fixtures.canonical(write)
        == #"{"$type":"com.atproto.repo.applyWrites#delete","collection":"app.bsky.graph.listitem","rkey":"3abc"}"#
    )
  }

  @Test("chunking splits at 50 and preserves order")
  func chunking() {
    let writes = (0..<120).map { StarterPackJSON.object(["n": .int($0)]) }
    let chunks = StarterPackRecords.chunk(writes)
    #expect(chunks.count == 3)
    #expect(chunks.map(\.count) == [50, 50, 20])
    // Order is preserved across the splits.
    #expect(chunks.flatMap { $0 } == writes)
  }

  @Test("chunking an empty list yields no batches")
  func chunkingEmpty() {
    #expect(StarterPackRecords.chunk([]).isEmpty)
  }

  @Test("chunking exactly 50 yields one batch, 51 yields two")
  func chunkingBoundary() {
    let writes = (0..<51).map { StarterPackJSON.object(["n": .int($0)]) }
    #expect(StarterPackRecords.chunk(Array(writes.prefix(50))).count == 1)
    #expect(StarterPackRecords.chunk(writes).map(\.count) == [50, 1])
  }
}
