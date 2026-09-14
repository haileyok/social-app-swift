import Foundation
import Lexicons
import Testing

@testable import StarterPacksLogic

/// Asserts the create/edit/delete write plans as data.
///
/// The plans are compared step by step against canonical JSON, so the sequence,
/// the payloads, the rkeys and the chunking are all pinned.
@Suite("StarterPackPlanner")
struct StarterPackPlannerTests {
  private let createdAt = "2026-08-31T00:00:00.000Z"
  private let updatedAt = "2026-08-31T01:00:00.000Z"

  private func createInput(
    members: [String] = ["did:plc:a", "did:plc:b"],
    feeds: [String] = [],
    description: String? = nil
  ) -> StarterPackPlanner.CreateInput {
    StarterPackPlanner.CreateInput(
      name: "Bluesky for Art History",
      description: description,
      memberDIDs: members,
      feedURIs: feeds,
      repo: Fixtures.authorDID,
      createdAt: createdAt)
  }

  // MARK: - Create

  @Test("the create plan is list create, one list-item batch, pack create")
  func createPlanShape() {
    let plan = StarterPackPlanner.create(createInput())
    #expect(plan.steps.count == 3)
    guard case .createList(let listCollection, _) = plan.steps[0] else {
      Issue.record("expected a list create first")
      return
    }
    #expect(listCollection == "app.bsky.graph.list")
    guard case .applyWrites(let repo, let writes) = plan.steps[1] else {
      Issue.record("expected an applyWrites second")
      return
    }
    #expect(repo == Fixtures.authorDID)
    #expect(writes.count == 2)
    guard case .createStarterPack(let collection, _) = plan.steps[2] else {
      Issue.record("expected a pack create last")
      return
    }
    #expect(collection == "app.bsky.graph.starterpack")
  }

  @Test("the create plan names the placeholder it will substitute")
  func createPlanPlaceholder() {
    let plan = StarterPackPlanner.create(createInput())
    #expect(plan.listPlaceholder != nil)
    #expect(StarterPackPlanner.isPlaceholder(plan.listPlaceholder ?? ""))
  }

  @Test("a create plan carries the exact list and pack payloads")
  func createPlanPayloads() {
    let plan = StarterPackPlanner.create(createInput(members: ["did:plc:a"], feeds: ["at://did:plc:feeds/app.bsky.feed.generator/a"]))
    let placeholder = plan.listPlaceholder ?? ""

    guard case .createList(_, let listRecord) = plan.steps[0],
      case .createStarterPack(_, let packRecord) = plan.steps[2]
    else {
      Issue.record("expected list and pack creates")
      return
    }

    #expect(
      Fixtures.canonical(listRecord)
        == #"{"$type":"app.bsky.graph.list","createdAt":"2026-08-31T00:00:00.000Z","name":"Bluesky for Art History","purpose":"app.bsky.graph.defs#referencelist"}"#)

    #expect(
      Fixtures.canonical(packRecord)
        == """
        {"$type":"app.bsky.graph.starterpack","createdAt":"2026-08-31T00:00:00.000Z",\
        "feeds":[{"uri":"at://did:plc:feeds/app.bsky.feed.generator/a"}],\
        "list":"\(placeholder)","name":"Bluesky for Art History"}
        """)
  }

  @Test("the create plan's list-item batch references the placeholder list")
  func createPlanListItems() {
    let plan = StarterPackPlanner.create(createInput(members: ["did:plc:a", "did:plc:b"]))
    let placeholder = plan.listPlaceholder ?? ""
    guard case .applyWrites(_, let writes) = plan.steps[1] else {
      Issue.record("expected an applyWrites")
      return
    }
    for (index, subject) in ["did:plc:a", "did:plc:b"].enumerated() {
      #expect(
        Fixtures.canonical(writes[index])
          == """
          {"$type":"com.atproto.repo.applyWrites#create","collection":"app.bsky.graph.listitem",\
          "value":{"$type":"app.bsky.graph.listitem","createdAt":"2026-08-31T00:00:00.000Z",\
          "list":"\(placeholder)","subject":"\(subject)"}}
          """)
    }
  }

  @Test("the create path does not chunk: a fresh pack sends one batch")
  func createPlanDoesNotChunk() {
    let members = (0..<60).map { "did:plc:p\($0)" }
    let plan = StarterPackPlanner.create(createInput(members: members))
    let batches = plan.steps.filter {
      if case .applyWrites = $0 { return true } else { return false }
    }
    #expect(batches.count == 1)
    guard case .applyWrites(_, let writes) = batches[0] else { return }
    #expect(writes.count == 60)
  }

  @Test("a create with no members produces no plan")
  func createPlanWithoutMembers() {
    let plan = StarterPackPlanner.create(createInput(members: []))
    #expect(plan.steps.isEmpty)
  }

  @Test("resolving the list URI rewrites the placeholder everywhere")
  func createPlanResolution() {
    let plan = StarterPackPlanner.create(createInput(members: ["did:plc:a"]))
    let resolved = plan.resolvingListURI("at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e")
    #expect(resolved.listPlaceholder == nil)

    guard case .createStarterPack(_, let packRecord) = resolved.steps[2],
      case .applyWrites(_, let writes) = resolved.steps[1]
    else {
      Issue.record("expected pack and writes")
      return
    }
    #expect(Fixtures.canonical(packRecord).contains("at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e"))
    #expect(Fixtures.canonical(writes[0]).contains("at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e"))
    #expect(Fixtures.canonical(packRecord).contains("pending.invalid") == false)
  }

  @Test("the create(listURI:) overload produces an already-resolved plan")
  func createPlanConvenienceOverload() {
    let plan = StarterPackPlanner.create(
      createInput(members: ["did:plc:a"]),
      listURI: "at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e")
    guard case .createStarterPack(_, let packRecord) = plan.steps[2] else { return }
    #expect(Fixtures.canonical(packRecord).contains("at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e"))
  }

  // MARK: - Edit

  private func editInput(
    currentItems: [App.Bsky.GraphDefs_ListItemView],
    selected: [WizardProfile],
    feeds: [StarterPackJSON] = [],
    authorDID: String = Fixtures.authorDID
  ) -> StarterPackPlanner.EditInput {
    StarterPackPlanner.EditInput(
      packURI: Fixtures.packURI(),
      repo: authorDID,
      authorDID: authorDID,
      listURI: Fixtures.listURI(),
      currentItems: currentItems,
      selectedProfiles: selected,
      feedValues: feeds,
      name: "Renamed",
      description: nil,
      createdAt: "2024-09-22T03:52:03.686Z",
      updatedAt: updatedAt)
  }

  @Test("the edit plan derives its rkey from the pack URI")
  func editPlanRkey() {
    let plan = StarterPackPlanner.edit(
      editInput(
        currentItems: [Fixtures.listItem(Fixtures.authorDID)],
        selected: [Fixtures.wizardProfile(Fixtures.authorDID)]))
    #expect(plan?.rkey == Fixtures.packRkey)
  }

  @Test("an unparseable pack URI produces no edit plan")
  func editPlanBadURI() {
    var input = editInput(
      currentItems: [Fixtures.listItem(Fixtures.authorDID)],
      selected: [Fixtures.wizardProfile(Fixtures.authorDID)])
    input = StarterPackPlanner.EditInput(
      packURI: "not-a-uri", repo: input.repo, authorDID: input.authorDID,
      listURI: input.listURI, currentItems: input.currentItems,
      selectedProfiles: input.selectedProfiles, feedValues: input.feedValues,
      name: input.name, description: input.description, createdAt: input.createdAt,
      updatedAt: input.updatedAt)
    #expect(StarterPackPlanner.edit(input) == nil)
  }

  @Test("the removed set excludes the author and keeps selected members")
  func removedItems() {
    let input = editInput(
      currentItems: [
        Fixtures.listItem(Fixtures.authorDID, rkey: "self"),
        Fixtures.listItem(Fixtures.memberDID, rkey: "keep"),
        Fixtures.listItem(Fixtures.otherDID, rkey: "drop"),
      ],
      selected: [
        Fixtures.wizardProfile(Fixtures.authorDID), Fixtures.wizardProfile(Fixtures.memberDID),
      ])

    let removed = StarterPackPlanner.removedItems(input)
    #expect(removed.map { $0.subject.did.rawValue } == [Fixtures.otherDID])
  }

  @Test("the author is never in the removed set, even when unselected")
  func removedItemsNeverIncludesAuthor() {
    let input = editInput(
      currentItems: [Fixtures.listItem(Fixtures.authorDID, rkey: "self")],
      selected: [])
    #expect(StarterPackPlanner.removedItems(input).isEmpty)
  }

  @Test("the added set is the selected profiles not already in the list")
  func addedProfiles() {
    let input = editInput(
      currentItems: [Fixtures.listItem(Fixtures.memberDID, rkey: "existing")],
      selected: [
        Fixtures.wizardProfile(Fixtures.memberDID), Fixtures.wizardProfile(Fixtures.otherDID),
      ])
    #expect(StarterPackPlanner.addedProfiles(input).map(\.did) == [Fixtures.otherDID])
  }

  @Test("the edit plan is deletes, then adds, then putRecord")
  func editPlanOrder() {
    let plan = StarterPackPlanner.edit(
      editInput(
        currentItems: [
          Fixtures.listItem(Fixtures.authorDID, rkey: "self"),
          Fixtures.listItem(Fixtures.memberDID, rkey: "drop"),
        ],
        selected: [Fixtures.wizardProfile(Fixtures.otherDID)]))
    guard let plan else {
      Issue.record("expected a plan")
      return
    }
    #expect(plan.steps.count == 3)
    guard case .applyWrites(_, let deletes) = plan.steps[0],
      case .applyWrites(_, let adds) = plan.steps[1],
      case .putStarterPack(_, let rkey, _) = plan.steps[2]
    else {
      Issue.record("unexpected step kinds")
      return
    }
    #expect(rkey == Fixtures.packRkey)
    #expect(
      Fixtures.canonical(deletes[0])
        == #"{"$type":"com.atproto.repo.applyWrites#delete","collection":"app.bsky.graph.listitem","rkey":"drop"}"#)
    #expect(
      Fixtures.canonical(adds[0])
        == #"{"$type":"com.atproto.repo.applyWrites#create","collection":"app.bsky.graph.listitem","value":{"$type":"app.bsky.graph.listitem","createdAt":"2026-08-31T01:00:00.000Z","list":"at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e","subject":"did:plc:other"}}"#)
  }

  @Test("the edit putRecord carries createdAt over and sets updatedAt")
  func editPutRecordPayload() {
    let plan = StarterPackPlanner.edit(
      editInput(
        currentItems: [Fixtures.listItem(Fixtures.authorDID)],
        selected: [Fixtures.wizardProfile(Fixtures.authorDID)],
        feeds: [.object(["uri": .string("at://did:plc:feeds/app.bsky.feed.generator/a")])]))
    guard let plan, case .putStarterPack(let collection, _, let record) = plan.steps.last else {
      Issue.record("expected a putRecord last")
      return
    }
    #expect(collection == "app.bsky.graph.starterpack")
    #expect(
      Fixtures.canonical(record)
        == #"{"$type":"app.bsky.graph.starterpack","createdAt":"2024-09-22T03:52:03.686Z","feeds":[{"uri":"at://did:plc:feeds/app.bsky.feed.generator/a"}],"list":"at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e","name":"Renamed","updatedAt":"2026-08-31T01:00:00.000Z"}"#)
  }

  @Test("an edit with no changes produces only the putRecord")
  func editPlanNoDiff() {
    let plan = StarterPackPlanner.edit(
      editInput(
        currentItems: [Fixtures.listItem(Fixtures.memberDID, rkey: "keep")],
        selected: [Fixtures.wizardProfile(Fixtures.memberDID)]))
    #expect(plan?.steps.count == 1)
    guard case .putStarterPack = plan?.steps.first else {
      Issue.record("expected only a putRecord")
      return
    }
  }

  @Test("the edit path chunks deletes at 50 and adds at 50, deletes first")
  func editPlanChunking() {
    let drops = (0..<120).map { Fixtures.listItem("did:plc:d\($0)", rkey: "d\($0)") }
    let adds = (0..<60).map { Fixtures.wizardProfile("did:plc:a\($0)") }
    let plan = StarterPackPlanner.edit(editInput(currentItems: drops, selected: adds))
    guard let plan else {
      Issue.record("expected a plan")
      return
    }
    let batches = plan.steps.compactMap { step -> [StarterPackJSON]? in
      if case .applyWrites(_, let writes) = step { return writes } else { return nil }
    }
    #expect(batches.map(\.count) == [50, 50, 20, 50, 10])
    // Every delete batch precedes every add batch.
    let kinds = plan.steps.compactMap { step -> String? in
      guard case .applyWrites(_, let writes) = step else { return nil }
      return writes.first?["$type"]?.stringValue
    }
    #expect(
      kinds == [
        StarterPackRecords.deleteWriteType, StarterPackRecords.deleteWriteType,
        StarterPackRecords.deleteWriteType, StarterPackRecords.createWriteType,
        StarterPackRecords.createWriteType,
      ])
  }

  @Test("a delete batch carries the rkey of each item's own URI")
  func editDeleteRkeys() {
    let drops = (0..<3).map { Fixtures.listItem("did:plc:d\($0)", rkey: "r\($0)") }
    let plan = StarterPackPlanner.edit(editInput(currentItems: drops, selected: []))
    guard let plan, case .applyWrites(_, let writes) = plan.steps.first else {
      Issue.record("expected a delete batch")
      return
    }
    #expect(writes.compactMap { $0["rkey"]?.stringValue } == ["r0", "r1", "r2"])
  }

  // MARK: - Delete

  @Test("the delete plan removes the list first, then the pack")
  func deletePlanOrder() {
    let plan = StarterPackPlanner.delete(listURI: Fixtures.listURI(), rkey: Fixtures.packRkey)
    #expect(plan.steps.count == 2)
    guard case .deleteRecord(let firstCollection, let firstRkey) = plan.steps[0],
      case .deleteRecord(let secondCollection, let secondRkey) = plan.steps[1]
    else {
      Issue.record("expected two deletes")
      return
    }
    #expect(firstCollection == "app.bsky.graph.list")
    #expect(firstRkey == Fixtures.listRkey)
    #expect(secondCollection == "app.bsky.graph.starterpack")
    #expect(secondRkey == Fixtures.packRkey)
  }

  @Test("the delete plan skips the list delete when the pack has no list")
  func deletePlanWithoutList() {
    let plan = StarterPackPlanner.delete(listURI: nil, rkey: Fixtures.packRkey)
    #expect(plan.steps.count == 1)
    guard case .deleteRecord(let collection, _) = plan.steps[0] else {
      Issue.record("expected a delete")
      return
    }
    #expect(collection == "app.bsky.graph.starterpack")
  }

  // MARK: - Executor

  @Test("the executor creates the list, resolves the placeholder, then writes")
  func executorCreate() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.setCreatedURI(
      "at://did:plc:author/app.bsky.graph.list/real1", for: "app.bsky.graph.list")
    let executor = StarterPackPlanExecutor(xrpc: xrpc, repo: Fixtures.authorDID)

    let plan = StarterPackPlanner.create(createInput(members: ["did:plc:a"]))
    let ref = try await executor.run(plan)

    let calls = xrpc.calls
    #expect(calls.count == 3)
    guard case .createRecord(_, let firstCollection, let firstRkey, _) = calls[0] else {
      Issue.record("expected a list create first")
      return
    }
    #expect(firstCollection == "app.bsky.graph.list")
    #expect(firstRkey == nil)

    guard case .applyWrites(_, let writes) = calls[1] else {
      Issue.record("expected an applyWrites second")
      return
    }
    #expect(Fixtures.canonical(writes[0]).contains("at://did:plc:author/app.bsky.graph.list/real1"))
    #expect(Fixtures.canonical(writes[0]).contains("pending.invalid") == false)

    guard case .createRecord(_, let lastCollection, _, let record) = calls[2] else {
      Issue.record("expected a pack create last")
      return
    }
    #expect(lastCollection == "app.bsky.graph.starterpack")
    #expect(Fixtures.canonical(record).contains("at://did:plc:author/app.bsky.graph.list/real1"))
    #expect(ref?.uri == "at://did:plc:author/app.bsky.graph.starterpack/created2")
  }

  @Test("the executor runs an edit plan without inventing a list create")
  func executorEdit() async throws {
    let xrpc = FakeStarterPackXrpc()
    let executor = StarterPackPlanExecutor(xrpc: xrpc, repo: Fixtures.authorDID)
    let plan = StarterPackPlanner.edit(
      editInput(
        currentItems: [Fixtures.listItem(Fixtures.memberDID, rkey: "drop")],
        selected: [Fixtures.wizardProfile(Fixtures.otherDID)]))
    guard let plan else {
      Issue.record("expected a plan")
      return
    }
    let ref = try await executor.run(plan)

    let calls = xrpc.calls
    #expect(calls.count == 3)
    guard case .applyWrites = calls[0], case .applyWrites = calls[1],
      case .putRecord(_, let collection, let rkey, _) = calls[2]
    else {
      Issue.record("unexpected call sequence")
      return
    }
    #expect(collection == "app.bsky.graph.starterpack")
    #expect(rkey == Fixtures.packRkey)
    #expect(ref?.uri == "at://did:plc:author/app.bsky.graph.starterpack/\(Fixtures.packRkey)")
  }

  @Test("the executor runs a delete plan's deletes in order")
  func executorDelete() async throws {
    let xrpc = FakeStarterPackXrpc()
    let executor = StarterPackPlanExecutor(xrpc: xrpc, repo: Fixtures.authorDID)
    try await executor.run(
      StarterPackPlanner.delete(listURI: Fixtures.listURI(), rkey: Fixtures.packRkey))
    let collections = xrpc.calls.compactMap { call -> String? in
      if case .deleteRecord(_, let collection, _) = call { return collection } else { return nil }
    }
    #expect(collections == ["app.bsky.graph.list", "app.bsky.graph.starterpack"])
  }

  @Test("a failing write surfaces the error and stops the plan")
  func executorFailure() async throws {
    let xrpc = FakeStarterPackXrpc()
    xrpc.fail("createRecord")
    let executor = StarterPackPlanExecutor(xrpc: xrpc, repo: Fixtures.authorDID)
    await #expect(throws: (any Error).self) {
      try await executor.run(StarterPackPlanner.create(createInput(members: ["did:plc:a"])))
    }
    #expect(xrpc.calls.count == 1)
  }
}
