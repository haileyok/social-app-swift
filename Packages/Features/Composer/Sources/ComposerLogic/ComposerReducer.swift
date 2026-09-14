import Domain
import Foundation
import Lexicons
import RichText
import SwiftAtproto

/// An action on the composer as a whole.
///
/// Ported from the `ComposerAction` union in `state/composer.ts`.
public enum ComposerAction: Sendable {
  /// The postgate (embedding rules) changed.
  case updatePostgate(App.Bsky.FeedPostgate)
  /// The reply permissions changed.
  case updateThreadgate([ThreadgateAllowUISetting])
  /// A single post changed.
  case updatePost(postId: String, action: PostAction)
  /// A new empty post was inserted after the active one.
  case addPost(newId: String)
  /// The post with `postId` was removed.
  case removePost(postId: String)
  /// The active post changed.
  case focusPost(postId: String)
  /// The composer was hydrated from a draft.
  case restoreFromDraft(
    draftId: String,
    posts: [PostDraft],
    threadgateAllow: [App.Bsky.FeedThreadgate_Allow_Elem]?,
    postgateEmbeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem]?,
    createdAt: Date)
  /// The composer was reset to a fresh state.
  case clear(init: ComposerInit)
  /// The draft was saved; records its id and clears the dirty flag.
  case markSaved(draftId: String)
}

/// The initial inputs a composer can be opened with.
///
/// Ported from `createComposerState`'s parameters (`ComposerOpts` in RN).
public struct ComposerInit: Sendable {
  /// Prefilled text, used by share intents. When present, links and post URLs
  /// in it are suggested as embeds.
  public var text: String?
  /// A handle to prefill as a mention.
  public var mention: String?
  /// Image URIs to attach.
  public var imageUris: [ComposerImage]
  /// A post URI to open as a quote.
  public var quoteUri: String?
  /// The user's saved interaction settings.
  public var interactionSettings: PostInteractionSettings?
  /// A seed for the first post's id, so tests are deterministic.
  public var firstPostId: String

  public init(
    text: String? = nil,
    mention: String? = nil,
    imageUris: [ComposerImage] = [],
    quoteUri: String? = nil,
    interactionSettings: PostInteractionSettings? = nil,
    firstPostId: String = "post-0"
  ) {
    self.text = text
    self.mention = mention
    self.imageUris = imageUris
    self.quoteUri = quoteUri
    self.interactionSettings = interactionSettings
    self.firstPostId = firstPostId
  }
}

/// The user's saved post-interaction defaults.
///
/// Ported from `app.bsky.actor.defs#postInteractionSettingsPref`, reduced to the
/// two fields the composer consumes when it opens a blank state.
public struct PostInteractionSettings: Hashable, Sendable {
  /// `postgateEmbeddingRules` from the preference.
  public var postgateEmbeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem]
  /// `threadgateAllowRules` from the preference.
  public var threadgateAllowRules: [App.Bsky.FeedThreadgate_Allow_Elem]?

  public init(
    postgateEmbeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem] = [],
    threadgateAllowRules: [App.Bsky.FeedThreadgate_Allow_Elem]? = nil
  ) {
    self.postgateEmbeddingRules = postgateEmbeddingRules
    self.threadgateAllowRules = threadgateAllowRules
  }
}

/// The composer reducer.
///
/// Ported from `composerReducer` in `state/composer.ts`. Notes on the branches
/// that are easy to miss:
///
/// - `add_post` inserts **after the active post**, not at the end, and moves the
///   active index onto the new post.
/// - `remove_post` refuses to remove the last post, and moves the active index
///   to `max(0, removedIndex - 1)`.
/// - Every mutating branch sets `isDirty`, except `focus_post`, `clear` and
///   `restore_from_draft` (which explicitly marks the state clean).
public enum ComposerReducer {
  /// Applies `action` to `state`.
  public static func reduce(_ state: ComposerState, _ action: ComposerAction) -> ComposerState {
    switch action {
    case .updatePostgate(let postgate):
      var next = state
      next.isDirty = true
      next.thread.postgate = postgate
      return next

    case .updateThreadgate(let threadgate):
      var next = state
      next.isDirty = true
      next.thread.threadgate = threadgate
      return next

    case .updatePost(let postId, let postAction):
      guard let index = state.thread.posts.firstIndex(where: { $0.id == postId }) else {
        return state
      }
      var next = state
      next.isDirty = true
      next.thread.posts[index] = PostReducer.reduce(state.thread.posts[index], postAction)
      return next

    case .addPost(let newId): return addPost(state, newId: newId)
    case .removePost(let postId): return removePost(state, postId: postId)
    case .focusPost(let postId): return focusPost(state, postId: postId)
    case .restoreFromDraft(
      let draftId, let posts, let threadgateAllow, let postgateEmbeddingRules, let createdAt):
      return restoreFromDraft(
        draftId: draftId, posts: posts, threadgateAllow: threadgateAllow,
        postgateEmbeddingRules: postgateEmbeddingRules, createdAt: createdAt)
    case .clear(let initial): return createState(initial)
    case .markSaved(let draftId): return markSaved(state, draftId: draftId)
    }
  }

  /// Inserts an empty post after the active one and moves focus onto it.
  ///
  /// The index maths matters: later posts shift down, which is what lets a user
  /// insert a post in the middle of a thread.
  static func addPost(_ state: ComposerState, newId: String) -> ComposerState {
    var next = state
    next.isDirty = true
    next.thread.posts.insert(PostDraft.empty(id: newId), at: state.activePostIndex + 1)
    next.activePostIndex = state.activePostIndex + 1
    next.mutableNeedsFocusActive = true
    return next
  }

  /// Removes a post, refusing to remove the last one, and steps focus back.
  static func removePost(_ state: ComposerState, postId: String) -> ComposerState {
    guard state.thread.posts.count >= 2 else { return state }
    guard let index = state.thread.posts.firstIndex(where: { $0.id == postId }) else {
      return state
    }
    var next = state
    next.isDirty = true
    next.thread.posts.remove(at: index)
    next.activePostIndex = max(0, index - 1)
    next.mutableNeedsFocusActive = true
    return next
  }

  /// Moves focus onto an existing post.
  static func focusPost(_ state: ComposerState, postId: String) -> ComposerState {
    guard let index = state.thread.posts.firstIndex(where: { $0.id == postId }) else {
      return state
    }
    var next = state
    next.activePostIndex = index
    return next
  }

  /// Builds a clean state from a hydrated draft.
  static func restoreFromDraft(
    draftId: String,
    posts: [PostDraft],
    threadgateAllow: [App.Bsky.FeedThreadgate_Allow_Elem]?,
    postgateEmbeddingRules: [App.Bsky.FeedPostgate_EmbeddingRules_Elem]?,
    createdAt: Date
  ) -> ComposerState {
    ComposerState(
      thread: ThreadDraft(
        posts: posts,
        postgate: ComposerGates.placeholderPostgateRecord(
          embeddingRules: postgateEmbeddingRules ?? [], createdAt: createdAt),
        threadgate: ComposerGates.allowUISettings(
          from: App.Bsky.FeedThreadgate(
            allow: threadgateAllow,
            createdAt: FormatString<Date>(rawValue: isoString(createdAt)),
            post: FormatString<ATURI>(rawValue: "")))),
      activePostIndex: 0,
      mutableNeedsFocusActive: true,
      draftId: draftId,
      isDirty: false)
  }

  /// Records that the state was saved as a draft.
  static func markSaved(_ state: ComposerState, draftId: String) -> ComposerState {
    var next = state
    next.isDirty = false
    next.draftId = draftId
    return next
  }

  /// Builds the state a composer opens with.
  ///
  /// Ported from `createComposerState`. When `text` is supplied (share intents)
  /// links are detected and split into quote candidates (post URLs) and link
  /// candidates (everything else), with at most one of each suggested. When
  /// only `mention` is supplied, facets are detected solely to highlight it.
  public static func createState(_ initial: ComposerInit) -> ComposerState {
    let derived = deriveInitialEmbed(initial)
    let settings = initial.interactionSettings
    let threadgate = ComposerGates.allowUISettings(
      from: App.Bsky.FeedThreadgate(
        allow: settings?.threadgateAllowRules,
        createdAt: FormatString<Date>(rawValue: isoString(Date())),
        post: FormatString<ATURI>(rawValue: "")))

    return ComposerState(
      thread: ThreadDraft(
        posts: [
          PostDraft(
            id: initial.firstPostId,
            richText: derived.richText,
            embed: EmbedDraft(quote: derived.quote, media: derived.media, link: derived.link))
        ],
        postgate: ComposerGates.placeholderPostgateRecord(
          embeddingRules: settings?.postgateEmbeddingRules ?? []),
        threadgate: threadgate),
      activePostIndex: 0,
      mutableNeedsFocusActive: false,
      draftId: nil,
      isDirty: false)
  }

  /// The embed and text a new composer opens with.
  ///
  /// Ported from the derivation at the top of `createComposerState`: attached
  /// images, an explicit quote URI, and - for share intents only - one suggested
  /// link card and one suggested quote lifted out of the prefilled text.
  static func deriveInitialEmbed(
    _ initial: ComposerInit
  ) -> (richText: RichTextValue, quote: QuoteLink?, media: ComposerMedia?, link: ExternalLink?) {
    var media: ComposerMedia?
    if !initial.imageUris.isEmpty {
      media = .images(.variant(for: initial.imageUris))
    }

    var quote: QuoteLink?
    if let quoteUri = initial.quoteUri, let path = URLHelpers.postUriToRelativePath(quoteUri) {
      quote = QuoteLink(uri: URLHelpers.toBskyAppUrl(path))
    }

    var richText: RichTextValue
    if let text = initial.text {
      richText = RichTextValue(text: text)
    } else if let mention = initial.mention {
      richText = RichTextValue(text: insertMentionAt(handle: mention))
    } else {
      richText = .empty
    }

    var link: ExternalLink?
    if initial.text != nil {
      richText = richText.detectingFacetsWithoutResolution()
      let detected = detectLinkUris(in: richText)
      var pastSuggested = Set<String>()
      link = suggestLinkCard(
        detected.externalUris, pastSuggested: &pastSuggested)
      if quote == nil {
        quote = suggestQuote(detected.postUris, pastSuggested: &pastSuggested)
      }
    } else if initial.mention != nil {
      // Highlight the mention.
      richText = richText.detectingFacetsWithoutResolution()
    }
    return (richText, quote, media, link)
  }

  /// Suggests one external link card from a set of detected links.
  static func suggestLinkCard(
    _ detected: [String: LinkFacetMatch],
    pastSuggested: inout Set<String>
  ) -> ExternalLink? {
    guard let uri = suggestLinkCardUri(
      suggestImmediately: true,
      nextDetectedUris: detected,
      prevDetectedUris: [:],
      pastSuggestedUris: &pastSuggested)
    else { return nil }
    return ExternalLink(uri: uri)
  }

  /// Suggests one quote from a set of detected post links.
  static func suggestQuote(
    _ detected: [String: LinkFacetMatch],
    pastSuggested: inout Set<String>
  ) -> QuoteLink? {
    guard let uri = suggestLinkCardUri(
      suggestImmediately: true,
      nextDetectedUris: detected,
      prevDetectedUris: [:],
      pastSuggestedUris: &pastSuggested)
    else { return nil }
    return QuoteLink(uri: uri)
  }

  /// The `@handle` text `createComposerState` inserts when opened with a mention.
  ///
  /// Ported from the `insertMentionAt` call: RN builds `@handle`, then inserts
  /// the handle at index `handle.count + 1` (i.e. right after the `@`), which is
  /// equivalent to `"@" + handle`.
  public static func insertMentionAt(handle: String) -> String {
    "@" + handle
  }

  /// Splits a rich text's link facets into post links and other links.
  ///
  /// Ported from the `detectedExtUris`/`detectedPostUris` construction in
  /// `createComposerState`.
  public static func detectLinkUris(in richText: RichTextValue) -> DetectedLinkUris {
    var result = DetectedLinkUris()
    guard let facets = richText.facets else { return result }
    for facet in facets {
      for feature in facet.features {
        guard case .link(let uri) = feature else { continue }
        let match = LinkFacetMatch(richText: richText, facet: facet)
        if URLHelpers.isBskyPostUrl(uri) {
          result.postUris[uri] = match
        } else {
          result.externalUris[uri] = match
        }
      }
    }
    return result
  }
}
