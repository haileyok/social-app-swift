import Foundation
import Lexicons
import RichText
import SwiftAtproto
import Testing

@testable import ComposerLogic

/// Server-side draft CRUD and draft <-> composer conversion.
///
/// Ported from `drafts/state/queries.ts` and `drafts/state/api.ts`.
@Suite("ComposerDrafts")
struct ComposerDraftsTests {

  // MARK: - CRUD

  @Test("saving a new composer state creates a draft and returns its id")
  func createDraft() async throws {
    let service = FakeDraftsService()
    let drafts = ComposerDrafts(service: service, deviceId: "device-1")
    let state = ComposerReducer.createState(ComposerInit(text: "hello", firstPostId: "p0"))

    let result = try await drafts.save(
      state: state, existingDraftId: nil, deviceName: "Test Device")
    #expect(result.draftId == "draft-1")
    #expect(service.calls == ["createDraft"])
    let stored = service.draft("draft-1")
    #expect(stored?.posts.first?.text == "hello")
    #expect(stored?.deviceId == "device-1")
    #expect(stored?.deviceName == "Test Device")
  }

  @Test("saving an existing draft updates rather than creating")
  func updateDraft() async throws {
    let service = FakeDraftsService()
    service.seed(
      "draft-9",
      App.Bsky.DraftDefs_Draft(posts: [App.Bsky.DraftDefs_DraftPost(
        text: "old"
      )]))
    let drafts = ComposerDrafts(service: service, deviceId: "device-1")
    let state = ComposerReducer.createState(ComposerInit(text: "new", firstPostId: "p0"))

    let result = try await drafts.save(
      state: state, existingDraftId: "draft-9", deviceName: "Test Device")
    #expect(result.draftId == "draft-9")
    #expect(service.calls == ["updateDraft(draft-9)"])
    #expect(service.draft("draft-9")?.posts.first?.text == "new")
  }

  @Test("a device name longer than 100 characters is truncated")
  func deviceNameTruncated() async throws {
    let service = FakeDraftsService()
    let drafts = ComposerDrafts(service: service, deviceId: "d")
    let state = ComposerReducer.createState(ComposerInit(text: "x", firstPostId: "p0"))
    _ = try await drafts.save(
      state: state, existingDraftId: nil, deviceName: String(repeating: "a", count: 150))
    #expect(service.draft("draft-1")?.deviceName?.count == 100)
  }

  @Test("deleting a draft removes it from the server")
  func deleteDraft() async throws {
    let service = FakeDraftsService()
    service.seed("draft-1", App.Bsky.DraftDefs_Draft(posts: []))
    let drafts = ComposerDrafts(service: service, deviceId: "d")
    try await drafts.delete(
      draftId: "draft-1", draft: App.Bsky.DraftDefs_Draft(posts: []))
    #expect(service.calls.contains("deleteDraft(draft-1)"))
    #expect(service.draft("draft-1") == nil)
  }

  @Test("listing drafts paginates through the cursor")
  func listDrafts() async throws {
    let service = FakeDraftsService(cursors: ["next-page", nil])
    service.seed("draft-1", App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        text: "first"
      )
    ]))
    let drafts = ComposerDrafts(service: service, deviceId: "d")

    let first = try await drafts.drafts()
    #expect(first.cursor == "next-page")
    #expect(first.drafts.count == 1)
    #expect(first.drafts[0].posts.first?.text == "first")

    let second = try await drafts.drafts(cursor: "next-page")
    #expect(second.cursor == nil)
  }

  @Test("the draft limit error is surfaced distinctly")
  func draftLimitError() async {
    let service = FakeDraftsService()
    service.setCreateError(ComposerDraftsError.draftLimitReached)
    let drafts = ComposerDrafts(service: service, deviceId: "d")
    let state = ComposerReducer.createState(ComposerInit(text: "x", firstPostId: "p0"))
    await #expect(throws: ComposerDraftsError.draftLimitReached) {
      try await drafts.save(state: state, existingDraftId: nil, deviceName: "D")
    }
  }

  // MARK: - Network first, local media second

  @Test("media is saved only after the server accepted the draft")
  func networkBeforeLocalMedia() async throws {
    let log = OperationLog()
    let service = FakeDraftsService(log: log)
    let storage = FakeDraftMediaStorage(log: log)
    let drafts = ComposerDrafts(service: service, deviceId: "d", storage: storage)

    let images = [
      ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10, alt: "a")
    ]
    let post = Fixtures.post(id: "p0", text: "pic", embed: EmbedDraft(media: .images(.images(images))))
    let state = Fixtures.state(Fixtures.thread(posts: [post]))

    _ = try await drafts.save(
      state: state, existingDraftId: nil, deviceName: "D",
      idGenerator: { "ref1" })
    #expect(log.all.first == "createDraft")
    #expect(log.all.contains("save(image:ref1)"))
    #expect(log.all.firstIndex(of: "createDraft")! < log.all.firstIndex(of: "save(image:ref1)")!)
  }

  @Test("a failed create writes no local media")
  func failedCreateWritesNoMedia() async {
    let log = OperationLog()
    let service = FakeDraftsService(log: log)
    service.setCreateError(ComposerDraftsError.draftLimitReached)
    let storage = FakeDraftMediaStorage(log: log)
    let drafts = ComposerDrafts(service: service, deviceId: "d", storage: storage)

    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10)]
    let post = Fixtures.post(id: "p0", text: "pic", embed: EmbedDraft(media: .images(.images(images))))
    let state = Fixtures.state(Fixtures.thread(posts: [post]))

    await #expect(throws: ComposerDraftsError.draftLimitReached) {
      try await drafts.save(
        state: state, existingDraftId: nil, deviceName: "D", idGenerator: { "ref1" })
    }
    #expect(!storage.operations.contains { $0.hasPrefix("save") })
  }

  @Test("an existing media file is not re-saved")
  func existingMediaNotResaved() async throws {
    let service = FakeDraftsService()
    let storage = FakeDraftMediaStorage(existing: ["image:ref1"])
    let drafts = ComposerDrafts(service: service, deviceId: "d", storage: storage)
    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10)]
    let post = Fixtures.post(id: "p0", text: "pic", embed: EmbedDraft(media: .images(.images(images))))
    let state = Fixtures.state(Fixtures.thread(posts: [post]))
    _ = try await drafts.save(state: state, existingDraftId: nil, deviceName: "D", idGenerator: { "ref1" })
    #expect(!storage.operations.contains("save(image:ref1)"))
  }

  @Test("orphaned media from a previous save is deleted")
  func orphanedMediaDeleted() async throws {
    let service = FakeDraftsService()
    let storage = FakeDraftMediaStorage(existing: ["image:old"])
    let drafts = ComposerDrafts(service: service, deviceId: "d", storage: storage)
    let images = [ComposerImage(id: "i1", path: "/a.jpg", width: 10, height: 10)]
    let post = Fixtures.post(id: "p0", text: "pic", embed: EmbedDraft(media: .images(.images(images))))
    let state = Fixtures.state(Fixtures.thread(posts: [post]))
    _ = try await drafts.save(
      state: state, existingDraftId: nil, deviceName: "D",
      originalLocalRefs: ["image:old"], idGenerator: { "new" })
    #expect(storage.operations.contains("delete(image:old)"))
  }

  @Test("deleting a draft removes its local media after the server call")
  func deleteRemovesMedia() async throws {
    let log = OperationLog()
    let service = FakeDraftsService(log: log)
    let storage = FakeDraftMediaStorage(existing: ["image:a"], log: log)
    let drafts = ComposerDrafts(service: service, deviceId: "d", storage: storage)
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        embedGallery: App.Bsky.DraftDefs_DraftEmbedGallery(items: [
          .draftDefsDraftEmbedImage(
            App.Bsky.DraftDefs_DraftEmbedImage(
              localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:a")))
        ]),
        text: "x"
      )
    ])
    try await drafts.delete(draftId: "draft-1", draft: draft)
    #expect(log.all.first == "deleteDraft")
    #expect(log.all.contains("delete(image:a)"))
  }

  @Test("a failed server delete leaves local media alone")
  func failedDeleteKeepsMedia() async {
    let log = OperationLog()
    let service = FakeDraftsService(log: log)
    service.setDeleteError(ComposerDraftsError.network)
    let storage = FakeDraftMediaStorage(existing: ["image:a"], log: log)
    let drafts = ComposerDrafts(service: service, deviceId: "d", storage: storage)
    let draft = App.Bsky.DraftDefs_Draft(posts: [
      App.Bsky.DraftDefs_DraftPost(
        embedGallery: App.Bsky.DraftDefs_DraftEmbedGallery(items: [
          .draftDefsDraftEmbedImage(
            App.Bsky.DraftDefs_DraftEmbedImage(
              localRef: App.Bsky.DraftDefs_DraftEmbedLocalRef(path: "image:a")))
        ]),
        text: "x"
      )
    ])
    await #expect(throws: (any Error).self) {
      try await drafts.delete(draftId: "draft-1", draft: draft)
    }
    #expect(!storage.operations.contains("delete(image:a)"))
  }
}
