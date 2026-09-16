import ATProtoClient
import ComposerLogic
import DesignSystem
import DesignSystemCore
import Foundation
import Lexicons
import RichText
import SwiftAtproto
import SwiftUI

// Re-exported so the app and its test targets reach `ComposerAccessibility` (and
// the rest of the composer surface) through `import AppShell` alone, the way
// they reach `ShellAccessibility` and `LoginAccessibility`. The XCUITest bundle
// is built by the project rather than by a package, so it links only the AppShell
// product.
@_exported import ComposerViews

/**
 The composer entry point.

 Mirrors `AppShell+Components.swift` and `AppShell+Login.swift`: the hook lives
 in its own file so the shell agent's work on the root view and this surface do
 not conflict. Nothing here is referenced by the root view by default.

 ```swift
 // Any screen, to present the composer:
 ComposerDebugButton()
 ```

 The screen underneath is fixture-driven (`ComposerDebugView`): it mounts
 `ComposerScreen` over a `ComposerFixtures` state, so the composer is reviewable -
 and screenshot-able - without an account, a backend or a media picker. The
 app's real composer wires the same screen to its own `ComposerState` and
 callbacks; see the `ComposerScreen` initialiser.
 */
public enum ComposerSurfaces {
  /// The composer screen for a fixture surface, themed.
  ///
  /// This is the one function the app shell exposes: the debug button below is a
  /// thin presentation wrapper, and a real hosting screen can call this directly.
  public static func composerScreen(theme: ThemePreference = .system) -> some View {
    ComposerDebugView(theme: theme)
  }

  /// The composer screen pinned to one fixture surface.
  public static func composerScreen(
    surface: ComposerSurface,
    theme: ThemePreference = .system
  ) -> some View {
    ComposerDebugView(surface: surface, theme: theme)
  }
}

/// The shell-level identifiers this hook adds.
///
/// Declared here rather than in `ShellAccessibility.swift` so the hook stays one
/// self-contained file (the shell agent owns that file). Names are dot-scoped on
/// `app.` like the rest of the shell's identifiers.
enum ComposerShellAccessibility {
  /// The toolbar button that presents the composer.
  static let debugButton = "app.debug.composer"
  /// The presented composer screen.
  static let sheet = "app.composer"
}

/**
 The debug toolbar button that presents the composer.

 The stopgap entry point while the shell keeps the 5-tab root and its smoke tests
 untouched, exactly as `LoginDebugButton` is for the login flow.
 */
public struct ComposerDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "square.and.pencil")
    }
    .accessibilityLabel("Composer")
    .accessibilityIdentifier(ComposerShellAccessibility.debugButton)
    .sheet(isPresented: $isPresented) {
      ComposerDebugSheet()
    }
  }
}

/// The presented composer, wrapped in its own `NavigationStack` for a title bar
/// and the platform's close affordance.
public struct ComposerDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      // The screen carries its own cancel control, so the nav bar does not add
      // a second one (and a second `composer.cancel` identifier).
      ComposerDebugView(theme: resolvedTheme, onCancel: { dismiss() })
        .navigationTitle("New post")
        .navigationBarTitleDisplayMode(.inline)
    }
    .theme(resolvedTheme)
    .accessibilityIdentifier(ComposerShellAccessibility.sheet)
  }

  /// The stored preference, falling back to `.system` for an unknown value.
  private var resolvedTheme: ThemePreference {
    ThemePreference(rawValue: themePreference) ?? .system
  }
}

/// A hydrated target used to seed a reply composer.
struct ComposerReplyTarget: Identifiable {
  let parent: RecordReference
  let root: RecordReference
  let display: ComposerReplyContext

  var id: String { parent.uri }
}

/// Production composer button backed by the signed-in account's PDS client.
struct LiveComposerButton: View {
  let clients: AppSessionClients
  var replyTarget: ComposerReplyTarget?
  var onPublished: () async -> Void = {}

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: replyTarget == nil ? "square.and.pencil" : "arrowshape.turn.up.left")
    }
    .accessibilityLabel(replyTarget == nil ? "New post" : "Reply")
    .sheet(isPresented: $isPresented) {
      LiveComposerSheet(
        clients: clients,
        replyTarget: replyTarget,
        onPublished: onPublished)
    }
  }
}

/// App-owned state and network host for a text post or reply.
struct LiveComposerSheet: View {
  let clients: AppSessionClients
  let replyTarget: ComposerReplyTarget?
  let onPublished: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var state: ComposerState
  @State private var languages = LanguageSelection(languages: [])
  @State private var allowQuotes = true
  @State private var phase: ComposerPublishPhase?

  init(
    clients: AppSessionClients,
    replyTarget: ComposerReplyTarget?,
    onPublished: @escaping () async -> Void
  ) {
    self.clients = clients
    self.replyTarget = replyTarget
    self.onPublished = onPublished
    _state = State(
      initialValue: ComposerReducer.createState(
        ComposerInit(firstPostId: UUID().uuidString.lowercased())))
  }

  var body: some View {
    NavigationStack {
      ComposerScreen(
        state: state,
        replyContext: replyTarget?.display,
        publishPhase: phase,
        languages: languages,
        allowQuotes: allowQuotes,
        onReduce: reduce,
        onLanguagesChange: { languages = $0 },
        onAllowQuotesChange: updateAllowQuotes,
        onPublish: { Task { await publish() } },
        onCancel: { dismiss() })
        .navigationTitle(replyTarget == nil ? "New post" : "Reply")
        .navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled(isPosting)
  }

  private var isPosting: Bool {
    if case .posting = phase { return true }
    return false
  }

  private func updateAllowQuotes(_ allowed: Bool) {
    allowQuotes = allowed
    state = ComposerReducer.reduce(
      state,
      .updatePostgate(
        ComposerGates.placeholderPostgateRecord(
          embeddingRules: allowed ? [] : [ComposerGates.disableRule])))
  }

  private func reduce(_ action: ComposerAction) {
    // Multi-post publishing still needs local DAG-CBOR CID generation. Keep the
    // production surface honest for now: text posts and replies are supported,
    // while the add-post control is inert instead of publishing a broken chain.
    if case .addPost = action { return }
    state = ComposerReducer.reduce(state, action)
  }

  @MainActor
  private func publish() async {
    guard !isPosting, state.thread.posts.count == 1 else { return }
    phase = .posting(detail: replyTarget == nil ? "Publishing post…" : "Publishing reply…")

    do {
      let post = state.thread.posts[0]
      let rkey = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
      let resolvedMentions = await resolveMentions(in: post.richText)
      let resolvedMedia = try await resolveMedia(for: post)
      let inputs = PublishInputs(
        thread: state.thread,
        langs: languages.codes,
        reply: replyTarget.map { ReplyContext(root: $0.root, parent: $0.parent) },
        resolvedMentions: resolvedMentions,
        media: resolvedMedia.map { [post.id: $0] } ?? [:],
        rkeys: [post.id: rkey],
        did: clients.did)
      let built = try ComposerRecordBuilder.build(inputs) { _ in
        throw LiveComposerError.unexpectedCIDRequest
      }
      guard let record = built.first else { throw LiveComposerError.emptyPost }

      let writes = ComposerRecordBuilder.writes(from: [record]).map(ComposerApplyWrite.init)
      let _: IgnoreApplyWritesOutput = try await clients.pds.procedure(
        "com.atproto.repo.applyWrites",
        body: ComposerApplyWritesBody(repo: clients.did, writes: writes, validate: true))
      await onPublished()
      dismiss()
    } catch {
      phase = .failed(message: error.localizedDescription)
    }
  }

  private func resolveMedia(for post: PostDraft) async throws -> ResolvedEmbedMedia? {
    guard case .images(let media) = post.embed.media else { return nil }
    var resolved: [ResolvedImage] = []
    for image in media.images {
      let data = try Data(contentsOf: URL(fileURLWithPath: image.sourcePath))
      let uploaded = try await clients.pds.uploadBlob(data, mimeType: image.mime)
      guard let link = uploaded.blob.ref?.link else { throw LiveComposerError.invalidBlobResponse }
      let blobJSON: [String: Any] = [
        "$type": "blob",
        "ref": ["$link": link],
        "mimeType": uploaded.blob.mimeType ?? image.mime,
        "size": uploaded.blob.size ?? data.count,
      ]
      let blobData = try JSONSerialization.data(withJSONObject: blobJSON)
      let blob = try JSONDecoder().decode(LexBlob.self, from: blobData)
      resolved.append(
        ResolvedImage(
          blob: blob,
          alt: image.alt,
          width: image.width,
          height: image.height))
    }
    switch ImagesMedia.variant(for: media.images) {
    case .images:
      return .images(resolved)
    case .gallery:
      return .gallery(resolved)
    }
  }

  private func resolveMentions(in value: RichTextValue) async -> [String: String] {
    let detected = value.detectingFacetsWithoutResolution()
    let handles = Set(
      (detected.facets ?? []).flatMap(\.features).compactMap { feature -> String? in
        guard case .mention(let handle) = feature else { return nil }
        return handle.lowercased()
      })
    var resolved: [String: String] = [:]
    for handle in handles {
      let output: ResolveHandleOutput? = try? await clients.appview.get(
        "com.atproto.identity.resolveHandle", params: [("handle", handle)])
      if let did = output?.did, !did.isEmpty {
        resolved[handle] = did
      }
    }
    return resolved
  }
}

private struct ResolveHandleOutput: Decodable {
  let did: String
}

/// One atomic repo transaction, matching RN's composer `applyWrites` request.
private struct ComposerApplyWritesBody: Encodable, Sendable {
  let repo: String
  let writes: [ComposerApplyWrite]
  let validate: Bool
}

private enum ComposerApplyWrite: Encodable, Sendable {
  case post(collection: String, rkey: String, value: Lexicons.App.Bsky.FeedPost)
  case threadgate(collection: String, rkey: String, value: Lexicons.App.Bsky.FeedThreadgate)
  case postgate(collection: String, rkey: String, value: Lexicons.App.Bsky.FeedPostgate)

  init(_ write: ComposerWrite) {
    switch write {
    case .create(let collection, let rkey, let value):
      self = .post(collection: collection, rkey: rkey, value: value)
    case .createThreadgate(let collection, let rkey, let value):
      self = .threadgate(collection: collection, rkey: rkey, value: value)
    case .createPostgate(let collection, let rkey, let value):
      self = .postgate(collection: collection, rkey: rkey, value: value)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type = "$type"
    case collection
    case rkey
    case value
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("com.atproto.repo.applyWrites#create", forKey: .type)
    switch self {
    case .post(let collection, let rkey, let value):
      try container.encode(collection, forKey: .collection)
      try container.encode(rkey, forKey: .rkey)
      try container.encode(value.typed, forKey: .value)
    case .threadgate(let collection, let rkey, let value):
      try container.encode(collection, forKey: .collection)
      try container.encode(rkey, forKey: .rkey)
      try container.encode(value.typed, forKey: .value)
    case .postgate(let collection, let rkey, let value):
      try container.encode(collection, forKey: .collection)
      try container.encode(rkey, forKey: .rkey)
      try container.encode(value.typed, forKey: .value)
    }
  }
}

/// `applyWrites` returns commit metadata that the composer does not consume.
private struct IgnoreApplyWritesOutput: Decodable {
  init(from decoder: any Decoder) throws {
    _ = try decoder.singleValueContainer()
  }
}

private enum LiveComposerError: LocalizedError {
  case emptyPost
  case invalidBlobResponse
  case unexpectedCIDRequest

  var errorDescription: String? {
    switch self {
    case .emptyPost: "There is no post to publish."
    case .invalidBlobResponse: "The server did not return a valid image reference."
    case .unexpectedCIDRequest: "This post requires unsupported local CID generation."
    }
  }
}

#Preview {
  ComposerDebugSheet()
}
