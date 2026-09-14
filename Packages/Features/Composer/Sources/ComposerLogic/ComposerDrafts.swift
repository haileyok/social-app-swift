import Foundation
import Lexicons
import SwiftAtproto

/// The server-side drafts API.
///
/// Ported from `src/view/composer/composer/drafts/state/queries.ts`, which
/// wraps four `app.bsky.draft.*` calls:
/// `getDrafts`, `createDraft`, `updateDraft` and `deleteDraft`.
public protocol ComposerDraftsService: Sendable {
  /// `app.bsky.draft.getDrafts` - a page of drafts.
  func getDrafts(cursor: String?) async throws -> App.Bsky.DraftGetDrafts_Output

  /// `app.bsky.draft.createDraft` - the new draft's id.
  ///
  /// - Throws: ``ComposerDraftsError/draftLimitReached`` when the server
  ///   rejects the create because the account is at its draft limit.
  func createDraft(_ draft: App.Bsky.DraftDefs_Draft) async throws -> String

  /// `app.bsky.draft.updateDraft`. Unknown ids are silently ignored by the
  /// server, so this does not throw for them.
  func updateDraft(id: String, draft: App.Bsky.DraftDefs_Draft) async throws

  /// `app.bsky.draft.deleteDraft`.
  func deleteDraft(id: String) async throws
}

/// Failures the drafts layer surfaces.
public enum ComposerDraftsError: Error, Sendable, Equatable {
  /// `app.bsky.draft.createDraft` rejected the write because the account is at
  /// its draft limit. The RN hook inspects the typed error for exactly this.
  case draftLimitReached
  /// The drafts page could not be fetched.
  case network
}

/// A paged drafts result, with display metadata computed.
public struct DraftsPage: Sendable {
  /// The next cursor, when there are more pages.
  public var cursor: String?
  /// The draft summaries on this page.
  public var drafts: [DraftSummary]

  public init(cursor: String?, drafts: [DraftSummary]) {
    self.cursor = cursor
    self.drafts = drafts
  }
}

/// One draft as the list UI shows it.
///
/// Ported from `DraftSummary` in `drafts/state/schema.ts`.
public struct DraftSummary: Sendable {
  /// The server's draft id.
  public var id: String
  /// When the draft was created.
  public var createdAt: String
  /// When the draft was last updated.
  public var updatedAt: String
  /// The raw draft, kept so opening it does not refetch.
  public var draft: App.Bsky.DraftDefs_Draft
  /// The per-post display content.
  public var posts: [DraftPostDisplay]
  /// Aggregate metadata for the list row.
  public var meta: DraftMeta
}

/// Display content for one post in a draft.
public struct DraftPostDisplay: Sendable, Hashable {
  public var id: String
  public var text: String
  public var images: [DraftMediaDisplay]?
  public var video: DraftMediaDisplay?
  public var gif: DraftGifDisplay?
}

/// A media file referenced by a draft, and whether it exists locally.
public struct DraftMediaDisplay: Sendable, Hashable {
  public var localPath: String
  public var altText: String
  public var exists: Bool
}

/// GIF display data parsed out of a draft's external embed URL.
public struct DraftGifDisplay: Sendable, Hashable {
  public var url: String
  public var width: Int
  public var height: Int
  public var alt: String
}

/// Aggregate metadata the draft list shows.
public struct DraftMeta: Sendable, Hashable {
  /// Whether this device created the draft (so its media may be present).
  public var isOriginatingDevice: Bool
  /// Number of posts in the thread.
  public var postCount: Int
  /// Number of posts after the anchor post.
  public var replyCount: Int
  /// Whether any post has media.
  public var hasMedia: Bool
  /// Whether some media is missing locally.
  public var hasMissingMedia: Bool
  /// Total media items.
  public var mediaCount: Int
  /// Whether any post quotes another.
  public var hasQuotes: Bool
  /// Total quoted records.
  public var quoteCount: Int
}

/// The drafts layer.
///
/// Ported from `drafts/state/queries.ts`. The ordering rule the RN hook encodes
/// is preserved at this level too: **network first, local media second**. Local
/// media is only written or deleted after the server call succeeds, so a failed
/// network operation never loses the bytes.
public struct ComposerDrafts: Sendable {
  let service: ComposerDraftsService
  /// The device id, so drafts can be marked as originating here.
  let deviceId: String
  /// Local media storage, when the app provides one.
  let storage: ComposerDraftMediaStorage?

  public init(
    service: ComposerDraftsService,
    deviceId: String,
    storage: ComposerDraftMediaStorage? = nil
  ) {
    self.service = service
    self.deviceId = deviceId
    self.storage = storage
  }

  /// Fetches a page of drafts, summarised for display.
  public func drafts(cursor: String? = nil) async throws -> DraftsPage {
    do {
      let output = try await service.getDrafts(cursor: cursor)
      return DraftsPage(
        cursor: output.cursor,
        drafts: output.drafts.map {
          summarise(id: $0.id.rawValue, createdAt: $0.createdAt.rawValue,
            updatedAt: $0.updatedAt.rawValue, draft: $0.draft)
        })
    } catch {
      throw ComposerDraftsError.network
    }
  }

  /// Saves a composer state as a draft, creating or updating as appropriate.
  ///
  /// Network first, then local media: new or changed files are written only
  /// after the server accepted the draft, and refs no longer present are deleted
  /// only then too.
  ///
  /// - Parameter originalLocalRefs: the refs the draft had before this save, so
  ///   orphans can be identified.
  /// - Returns: the draft id and the local refs now in use.
  @discardableResult
  public func save(
    state: ComposerState,
    existingDraftId: String?,
    deviceName: String,
    originalLocalRefs: Set<String>? = nil,
    idGenerator: () -> String = { UUID().uuidString },
    resolveQuote: (String) -> RecordReference? = { _ in nil }
  ) async throws -> (draftId: String, localRefPaths: [DraftMediaFile]) {
    let conversion = ComposerDraftCoding.draft(
      from: state,
      deviceId: deviceId,
      deviceName: deviceName,
      idGenerator: idGenerator,
      resolveQuote: resolveQuote)

    let draftId: String
    if let existingDraftId {
      try await service.updateDraft(id: existingDraftId, draft: conversion.draft)
      draftId = existingDraftId
    } else {
      draftId = try await service.createDraft(conversion.draft)
    }

    // Only now touch local storage.
    if let storage {
      for file in conversion.localRefPaths where !storage.mediaExists(file.localRefPath) {
        try? await storage.saveMedia(localRefPath: file.localRefPath, sourcePath: file.sourcePath)
      }
      if let originalLocalRefs {
        let current = Set(conversion.localRefPaths.map(\.localRefPath))
        for oldRef in originalLocalRefs where !current.contains(oldRef) {
          try? await storage.deleteMedia(localRefPath: oldRef)
        }
      }
    }

    return (draftId, conversion.localRefPaths)
  }

  /// Deletes a draft, then its local media.
  ///
  /// Ported from `useDeleteDraftMutation`: the media files are deleted only after
  /// the server deletion succeeds, so a failure leaves them for a retry.
  public func delete(draftId: String, draft: App.Bsky.DraftDefs_Draft) async throws {
    try await service.deleteDraft(id: draftId)
    guard let storage else { return }
    for ref in ComposerDraftCoding.localRefs(in: draft) {
      try? await storage.deleteMedia(localRefPath: ref)
    }
  }

  /// Deletes a draft that was just published, and its local media.
  ///
  /// Ported from `useCleanupPublishedDraftMutation`; failures here are not fatal
  /// because the post is already published, so the caller should swallow them.
  public func cleanupAfterPublish(draftId: String, originalLocalRefs: Set<String>) async throws {
    try await service.deleteDraft(id: draftId)
    guard let storage else { return }
    for ref in originalLocalRefs {
      try? await storage.deleteMedia(localRefPath: ref)
    }
  }

  /// Summarises a draft for the list.
  ///
  /// Ported from `draftViewToSummary`.
  public func summarise(
    id: String,
    createdAt: String,
    updatedAt: String,
    draft: App.Bsky.DraftDefs_Draft
  ) -> DraftSummary {
    var tally = Tally()
    let posts: [DraftPostDisplay] = draft.posts.enumerated().map { index, post in
      summarisePost(post, index: index, tally: &tally)
    }
    return DraftSummary(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      draft: draft,
      posts: posts,
      meta: DraftMeta(
        isOriginatingDevice: draft.deviceId.map { $0 == deviceId } ?? false,
        postCount: draft.posts.count,
        replyCount: draft.posts.count - 1,
        hasMedia: tally.hasMedia,
        hasMissingMedia: tally.hasMissingMedia,
        mediaCount: tally.mediaCount,
        hasQuotes: tally.quoteCount > 0,
        quoteCount: tally.quoteCount))
  }

  /// Running totals gathered while summarising a draft's posts.
  struct Tally {
    var hasMedia = false
    var hasMissingMedia = false
    var mediaCount = 0
    var quoteCount = 0
  }

  /// Summarises one draft post, accumulating into `tally`.
  func summarisePost(
    _ post: App.Bsky.DraftDefs_DraftPost,
    index: Int,
    tally: inout Tally
  ) -> DraftPostDisplay {
    var images: [DraftMediaDisplay] = []
    var video: DraftMediaDisplay?
    var gif: DraftGifDisplay?

    var draftImages: [App.Bsky.DraftDefs_DraftEmbedImage] = post.embedImages ?? []
    if let gallery = post.embedGallery {
      for item in gallery.items {
        if case .draftDefsDraftEmbedImage(let image) = item { draftImages.append(image) }
      }
    }
    for image in draftImages {
      let exists = storage?.mediaExists(image.localRef.path) ?? false
      tally.recordMedia(exists: exists)
      images.append(
        DraftMediaDisplay(
          localPath: image.localRef.path, altText: image.alt ?? "", exists: exists))
    }

    for item in post.embedVideos ?? [] {
      let exists = storage?.mediaExists(item.localRef.path) ?? false
      tally.recordMedia(exists: exists)
      video = DraftMediaDisplay(
        localPath: item.localRef.path, altText: item.alt ?? "", exists: exists)
    }

    for external in post.embedExternals ?? [] {
      if let parsed = ComposerDraftCoding.parseGifFromUrl(external.uri.rawValue) {
        tally.recordMedia(exists: true)
        gif = DraftGifDisplay(
          url: parsed.gif.url, width: parsed.gif.width, height: parsed.gif.height,
          alt: parsed.alt)
      }
    }

    tally.quoteCount += (post.embedRecords ?? []).count

    return DraftPostDisplay(
      id: "post-\(index)",
      text: post.text,
      images: images.isEmpty ? nil : images,
      video: video,
      gif: gif)
  }
}

extension ComposerDrafts.Tally {
  /// Records one media item and whether its file is present.
  mutating func recordMedia(exists: Bool) {
    hasMedia = true
    mediaCount += 1
    if !exists { hasMissingMedia = true }
  }
}

/// Local media storage the drafts layer uses.
///
/// Injected so this package depends on no file system of its own; RN's
/// `drafts/state/storage.ts` implements the same three operations.
public protocol ComposerDraftMediaStorage: Sendable {
  /// Whether a media file for `localRefPath` exists locally.
  func mediaExists(_ localRefPath: String) -> Bool
  /// Copies `sourcePath` into local storage under `localRefPath`.
  func saveMedia(localRefPath: String, sourcePath: String) async throws
  /// Deletes the local file for `localRefPath`.
  func deleteMedia(localRefPath: String) async throws
}
