#if canImport(SwiftUI)
import ComposerLogic
import DesignSystem
import DesignSystemCore
import DesignTokens
import Lexicons
import PhotosUI
import SwiftUI
import UIComponents
import UIKit
import UniformTypeIdentifiers
import UIComponentsCore

/// The composer screen.
///
/// Ported (LOOKS-only) from `src/view/com/composer/Composer.tsx` and its
/// children. Where the RN screen is a modal with a keyboard-tracking toolbar,
/// this is a plain screen the app can present modally or push; the layout is the
/// RN one, top to bottom:
///
/// ```
/// reply/quote context header
/// post editors (first + thread tail) with counters
/// attachments: link card, images, video, GIF
/// settings strip: warnings, languages, replies, drafts
/// publish banner (progress / failure)
/// validation line
/// toolbar: publish, media, add-post, save-draft
/// ```
///
/// Everything the screen decides comes from `ComposerLogic`: the state is a
/// ``ComposerState`` mutated only through ``ComposerReducer/reduce(_:_:)``, the
/// publish gate is ``ComposerValidation/canPost(thread:requireAltText:hasUnavailableChatInvite:)``,
/// the counter reads `PostDraft.shortenedGraphemeLength`, and the settings
/// sheets write `ThreadgateAllowUISetting` / `SelfLabelSet` / `LanguageSelection`
/// values. Nothing here re-derives a rule.
///
/// This is deliberately a *controlled* screen over a caller-owned state: the app
/// owns persistence, the network, and the video pipeline, and hands the screen
/// the current state plus the callbacks it needs. That keeps the screen
/// testable, keeps the app's dependency graph out of the Views package, and
/// means a fixture can mount it with no backend at all.
public struct ComposerScreen: View {
  /// The composer state.
  private let state: ComposerState
  /// Whether the account requires alt text on media.
  private let requireAltText: Bool
  /// The reply target's display data, when this is a reply.
  private let replyContext: ComposerReplyContext?
  /// The publish phase, when one is in flight or failed.
  private let publishPhase: ComposerPublishPhase?
  /// The thread's language selection.
  private let languages: LanguageSelection
  /// Whether anyone may quote the post.
  private let allowQuotes: Bool
  /// The draft rows the drafts sheet shows.
  private let drafts: [DraftSummary]

  private let onReduce: (ComposerAction) -> Void
  private let onLanguagesChange: (LanguageSelection) -> Void
  private let onAllowQuotesChange: (Bool) -> Void
  private let onPublish: () -> Void
  private let onCancel: () -> Void
  private let onOpenDraft: (DraftSummary) -> Void
  private let onDeleteDraft: (DraftSummary) -> Void

  @State private var isLanguagesPresented = false
  @State private var isLabelsPresented = false
  @State private var isThreadgatePresented = false
  @State private var isDraftsPresented = false
  @State private var pickedPhotos: [PhotosPickerItem] = []
  @FocusState private var isEditorFocused: Bool
  @Environment(\.alfTheme) private var theme

  /// Builds the screen.
  ///
  /// The callbacks default to no-ops so a fixture (and a `#Preview`) can mount
  /// the screen without a backend; the app passes its real ones.
  public init(
    state: ComposerState,
    requireAltText: Bool = false,
    replyContext: ComposerReplyContext? = nil,
    publishPhase: ComposerPublishPhase? = nil,
    languages: LanguageSelection = LanguageSelection(languages: []),
    allowQuotes: Bool = true,
    drafts: [DraftSummary] = [],
    onReduce: @escaping (ComposerAction) -> Void = { _ in },
    onLanguagesChange: @escaping (LanguageSelection) -> Void = { _ in },
    onAllowQuotesChange: @escaping (Bool) -> Void = { _ in },
    onPublish: @escaping () -> Void = {},
    onCancel: @escaping () -> Void = {},
    onOpenDraft: @escaping (DraftSummary) -> Void = { _ in },
    onDeleteDraft: @escaping (DraftSummary) -> Void = { _ in }
  ) {
    self.state = state
    self.requireAltText = requireAltText
    self.replyContext = replyContext
    self.publishPhase = publishPhase
    self.languages = languages
    self.allowQuotes = allowQuotes
    self.drafts = drafts
    self.onReduce = onReduce
    self.onLanguagesChange = onLanguagesChange
    self.onAllowQuotesChange = onAllowQuotesChange
    self.onPublish = onPublish
    self.onCancel = onCancel
    self.onOpenDraft = onOpenDraft
    self.onDeleteDraft = onDeleteDraft
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        if let replyContext {
          ComposerReplyHeader(context: replyContext)
        }
        if let quote = activePost.embed.quote {
          ComposerQuoteHeader(uri: quote.uri) {
            onReduce(.updatePost(postId: activePost.id, action: .removeQuote))
          }
        }

        editorSection
        threadTail
        attachmentSection
        ComposerSettingsStrip(
          labels: activePost.labels,
          languages: languages,
          threadgate: state.thread.threadgate,
          onLanguages: { isLanguagesPresented = true },
          onLabels: { isLabelsPresented = true },
          onThreadgate: { isThreadgatePresented = true },
          onDrafts: { isDraftsPresented = true })

        if let publishPhase {
          ComposerPublishBanner(phase: publishPhase, onRetry: onPublish)
        }

        validationLine
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .scrollDismissesKeyboard(.interactively)
    .safeAreaInset(edge: .bottom) { mediaBar }
    .background(theme.atomColors.bg)
    .toolbar { navigationActions }
    .accessibilityIdentifier(ComposerAccessibility.screen)
    .sheet(isPresented: $isLanguagesPresented) {
      ComposerLanguageSheet(selection: languages, onChange: onLanguagesChange) {
        isLanguagesPresented = false
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $isLabelsPresented) {
      ComposerLabelsSheet(labels: activePost.labels) { labels in
        onReduce(.updatePost(postId: activePost.id, action: .updateLabels(labels)))
      } onDone: {
        isLabelsPresented = false
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $isThreadgatePresented) {
      ComposerThreadgateSheet(
        threadgate: state.thread.threadgate,
        allowQuotes: allowQuotes,
        onChange: { onReduce(.updateThreadgate($0)) },
        onQuotesChange: onAllowQuotesChange,
        onDone: {
          isThreadgatePresented = false
        }
      )
      .presentationDetents([.medium])
    }
    .sheet(isPresented: $isDraftsPresented) {
      ComposerDraftsSheet(
        drafts: drafts,
        isLoading: false,
        onOpen: onOpenDraft,
        onDelete: onDeleteDraft
      ) {
        isDraftsPresented = false
      }
      .presentationDetents([.medium, .large])
    }
    .onAppear {
      if state.mutableNeedsFocusActive { isEditorFocused = true }
    }
  }

  // MARK: - Sections

  private var editorSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      ComposerTextEditor(
        richText: activeRichText,
        placeholder: ComposerCopy.textPlaceholder,
        identifier: ComposerAccessibility.textEditor,
        isFocused: $isEditorFocused)
        .frame(minHeight: 150, alignment: .top)
    }
  }

  private var threadTail: some View {
    let tail = Array(state.thread.posts.dropFirst())
    return ComposerThreadPosts(
      posts: tail,
      onText: { postId, richText in
        onReduce(.updatePost(postId: postId, action: .updateRichText(richText)))
      },
      onRemove: { postId in
        onReduce(.removePost(postId: postId))
      })
  }

  @ViewBuilder
  private var attachmentSection: some View {
    if let link = activePost.embed.link {
      ComposerLinkCardRow(uri: link.uri) {
        onReduce(.updatePost(postId: activePost.id, action: .removeLink))
      }
    }

    if let media = activePost.embed.media {
      switch media {
      case .images(let images):
        ForEach(images.images) { image in
          ComposerImageAttachRow(
            image: image,
            requireAltText: requireAltText,
            onAltChanged: { alt in
              var updated = image
              updated.alt = alt
              onReduce(.updatePost(postId: activePost.id, action: .updateImage(updated)))
            },
            onRemove: {
              onReduce(.updatePost(postId: activePost.id, action: .removeImage(image)))
            })
        }
        if images.images.contains(where: { $0.alt.isEmpty }) {
          imageAltTextHelp
        }

      case .video(let video):
        ComposerVideoAttachRow(
          video: video,
          requireAltText: requireAltText,
          onAltChanged: { alt in
            onReduce(
              .updatePost(
                postId: activePost.id,
                action: .updateVideo(
                  VideoAction.updateAltText(altText: alt, token: video.token))))
          },
          onRemove: {
            onReduce(.updatePost(postId: activePost.id, action: .removeVideo))
          })

      case .gif(let gif):
        ComposerGifAttachRow(
          gif: gif,
          requireAltText: requireAltText,
          onAltChanged: { alt in
            onReduce(.updatePost(postId: activePost.id, action: .updateGifAlt(alt)))
          },
          onRemove: {
            onReduce(.updatePost(postId: activePost.id, action: .removeGif))
          })
      }
    }
  }

  private var imageAltTextHelp: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "info.circle.fill")
        .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
        .foregroundStyle(theme.colors.primary500)
      AlfText(
        ComposerCopy.altTextHelp,
        scale: .sm,
        color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(Spacing.sm)
    .background(theme.atomColors.bgContrast25)
    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(ComposerAccessibility.imageAltHelp)
  }

  @ViewBuilder
  private var validationLine: some View {
    // The gate is the logic layer's; this only renders its reason.
    if let message = ComposerCopy.validationMessage(currentValidationError) {
      AlfText(message, scale: .sm, color: theme.colors.negative500)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(ComposerAccessibility.validationMessage)
    }
  }

  @ToolbarContentBuilder
  private var navigationActions: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button(ComposerCopy.cancelAction, action: onCancel)
        .foregroundStyle(theme.atomColors.text)
        .accessibilityIdentifier(ComposerAccessibility.cancelButton)
    }
    ToolbarItem(placement: .confirmationAction) {
      Button(
        state.thread.posts.count > 1 ? ComposerCopy.postAllAction : ComposerCopy.postAction,
        action: onPublish)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(!canPost)
        .accessibilityIdentifier(ComposerAccessibility.publishButton)
    }
  }

  private var mediaBar: some View {
    HStack(spacing: Spacing.md) {
      PhotosPicker(
        selection: $pickedPhotos,
        maxSelectionCount: max(1, remainingImageCapacity),
        matching: .images
      ) {
        Label(ComposerCopy.addMediaAction, systemImage: "photo.on.rectangle")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(theme.colors.primary500)
          .padding(.horizontal, Spacing.sm)
          .frame(height: 40)
          .background(theme.colors.primary50)
          .clipShape(Capsule())
      }
      .disabled(!canAttachImages)
      .accessibilityLabel(ComposerCopy.addMediaAction)
      .accessibilityIdentifier(ComposerAccessibility.addMediaButton)
      .onChange(of: pickedPhotos) { _, items in
        guard !items.isEmpty else { return }
        Task { await importPhotos(items) }
      }

      Spacer(minLength: 0)
      ComposerCharacterCounter(post: activePost)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(theme.atomColors.borderContrastLow)
        .frame(height: 1)
    }
  }

  // MARK: - Photo import

  private var remainingImageCapacity: Int {
    max(0, ComposerConstants.maxGalleryImages - (activePost.embed.media?.images?.count ?? 0))
  }

  private var canAttachImages: Bool {
    remainingImageCapacity > 0
      && (activePost.embed.media == nil || activePost.embed.media?.images != nil)
  }

  @MainActor
  private func importPhotos(_ items: [PhotosPickerItem]) async {
    defer { pickedPhotos = [] }
    var images: [ComposerImage] = []
    for item in items.prefix(remainingImageCapacity) {
      guard let data = try? await item.loadTransferable(type: Data.self),
        let platformImage = UIImage(data: data)
      else { continue }
      let contentType = item.supportedContentTypes.first ?? .jpeg
      let mime = contentType.preferredMIMEType ?? "image/jpeg"
      let ext = contentType.preferredFilenameExtension ?? "jpg"
      let id = UUID().uuidString.lowercased()
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("composer-\(id).\(ext)")
      do {
        try data.write(to: url, options: .atomic)
        images.append(
          ComposerImage(
            id: id,
            path: url.path,
            width: platformImage.size.width * platformImage.scale,
            height: platformImage.size.height * platformImage.scale,
            mime: mime))
      } catch {
        continue
      }
    }
    guard !images.isEmpty else { return }
    onReduce(.updatePost(postId: activePost.id, action: .addImages(images)))
  }

  // MARK: - Derivations from the logic layer

  private var activePost: PostDraft { state.activePost }

  private var activeRichText: Binding<RichTextValue> {
    Binding(
      get: { activePost.richText },
      set: { value in
        onReduce(.updatePost(postId: activePost.id, action: .updateRichText(value)))
      })
  }

  /// The reason the composer cannot publish, or `nil`.
  private var currentValidationError: ComposerValidationError? {
    ComposerValidation.validate(thread: state.thread, requireAltText: requireAltText)
  }

  /// The publish gate, from the logic layer.
  private var canPost: Bool {
    ComposerValidation.canPost(thread: state.thread, requireAltText: requireAltText)
  }
}

/// The composer debug surface.
///
/// The fixture-driven entry point: it mounts ``ComposerScreen`` over a
/// ``ComposerFixtures`` state and walks the fixture cases, so the screen (and its
/// screenshots) can be reviewed without an account, a backend, or a media picker.
/// It holds no state of its own beyond the fixture selection, which is what keeps
/// it useful as a UI-review surface.
public struct ComposerDebugView: View {
  private let requireAltText: Bool
  private let themeOverride: ThemePreference
  private let onCancel: () -> Void

  @State private var surface: ComposerSurface = .text
  @State private var state: ComposerState
  @State private var languages = LanguageSelection(languages: ["en"])

  /// Builds the debug surface, optionally pinned to one fixture.
  public init(
    surface: ComposerSurface? = nil,
    requireAltText: Bool = false,
    theme: ThemePreference = .system,
    onCancel: @escaping () -> Void = {}
  ) {
    self.requireAltText = requireAltText
    self.themeOverride = theme
    self.onCancel = onCancel
    _surface = State(initialValue: surface ?? .text)
    _state = State(initialValue: ComposerFixtures.state(for: surface ?? .text))
  }

  public var body: some View {
    ComposerScreen(
      state: state,
      requireAltText: requireAltText,
      replyContext: ComposerFixtures.replyContext(for: surface),
      publishPhase: ComposerFixtures.publishPhase(for: surface),
      languages: languages,
      allowQuotes: !FixtureState.hasDisableRule(state),
      drafts: ComposerFixtures.draftRows(for: surface),
      onReduce: { action in
        // The screen is a controlled view over this state, so the debug surface
        // is the reducer's caller - exactly as the app is.
        state = ComposerReducer.reduce(state, action)
      },
      onLanguagesChange: { languages = $0 },
      onCancel: onCancel
    )
    .theme(themeOverride)
    .overlay(alignment: .topTrailing) {
      surfaceMenu
        .padding(.md)
    }
  }

  /// The fixture picker, so a reviewer can step through every state.
  private var surfaceMenu: some View {
    Menu {
      Picker("Surface", selection: $surface) {
        ForEach(ComposerSurface.allCases, id: \.self) { item in
          Text(item.rawValue).tag(item)
        }
      }
    } label: {
      Image(systemName: "square.grid.2x2")
        .padding(.sm)
        .background(.thinMaterial, in: Circle())
    }
    .accessibilityLabel("Fixture")
    .onChange(of: surface) { _, newValue in
      state = ComposerFixtures.state(for: newValue)
    }
  }
}

/// Small helpers over a fixture state that the debug surface needs.
private enum FixtureState {
  /// Whether the thread's postgate disables embedding.
  static func hasDisableRule(_ state: ComposerState) -> Bool {
    let rules = state.thread.postgate.embeddingRules ?? []
    return rules.contains { rule in
      if case .feedPostgateDisableRule = rule { return true }
      return false
    }
  }
}

#Preview("Composer - text") {
  ComposerDebugView(surface: .text)
}

#Preview("Composer - images") {
  ComposerDebugView(surface: .images, requireAltText: true)
}
#endif
