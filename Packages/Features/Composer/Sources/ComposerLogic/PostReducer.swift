import Domain
import Foundation
import Lexicons
import RichText

/// An action on a single post.
///
/// Ported from the `PostAction` union in `state/composer.ts`.
public enum PostAction: Sendable {
  /// The post's text changed (with facets).
  case updateRichText(RichTextValue)
  /// The post's self-labels changed.
  case updateLabels(SelfLabelSet)
  /// Images were added.
  case addImages([ComposerImage])
  /// One image was replaced (alt text or a transform).
  case updateImage(ComposerImage)
  /// One image was removed.
  case removeImage(ComposerImage)
  /// A video was picked and its pipeline started.
  case addVideo(ComposerVideo)
  /// The video pipeline advanced.
  case updateVideo(VideoAction)
  /// The video was removed.
  case removeVideo
  /// A detected URI was accepted as a quote or link card.
  case addURI(String)
  /// The quote was removed.
  case removeQuote
  /// The link card was removed.
  case removeLink
  /// A GIF was attached.
  case addGif(GifMedia)
  /// The GIF's alt text changed.
  case updateGifAlt(String)
  /// The GIF was removed.
  case removeGif
}

/// The per-post reducer.
///
/// Ported from `postReducer` in `state/composer.ts`. The rules that matter and
/// are easy to get wrong:
///
/// - **Media exclusivity.** `addImages` only ever *grows* an existing
///   images/gallery embed; adding images to a post that holds a video or GIF is
///   a no-op, exactly as in RN. The same holds in reverse for video and GIF.
/// - **Variant re-picking.** Removing enough images to drop from gallery to
///   legacy `images` demotes the variant, so older clients can still render it.
/// - **Label clearing.** Removing the last piece of media clears the post's
///   self-labels *unless* a link card remains (a link can still be adult
///   content). This is the `if (!state.embed.link) nextLabels = []` branch and
///   it repeats across `embed_remove_image`, `embed_remove_video` and
///   `embed_remove_link`.
public enum PostReducer {
  /// Applies `action` to `state`, returning the new post.
  public static func reduce(_ state: PostDraft, _ action: PostAction) -> PostDraft {
    switch action {
    case .updateRichText(let value): return applyRichText(state, value)
    case .updateLabels(let labels): return applyLabels(state, labels)
    case .addImages(let images): return applyAddImages(state, images)
    case .updateImage(let image): return applyUpdateImage(state, image)
    case .removeImage(let image): return applyRemoveImage(state, image)
    case .addVideo(let video): return applyAddVideo(state, video)
    case .updateVideo(let videoAction): return applyUpdateVideo(state, videoAction)
    case .removeVideo: return applyRemoveVideo(state)
    case .addURI(let uri): return applyAddURI(state, uri)
    case .removeLink: return applyRemoveLink(state)
    case .removeQuote: return applyRemoveQuote(state)
    case .addGif(let gif): return applyAddGif(state, gif)
    case .updateGifAlt(let alt): return applyGifAlt(state, alt)
    case .removeGif: return applyRemoveGif(state)
    }
  }

  /// Replaces the text and recomputes the shortened grapheme length.
  static func applyRichText(_ state: PostDraft, _ richText: RichTextValue) -> PostDraft {
    var next = state
    next.richText = richText
    next.shortenedGraphemeLength = ComposerText.shortenedGraphemeLength(richText)
    return next
  }

  /// Replaces the self-labels.
  static func applyLabels(_ state: PostDraft, _ labels: SelfLabelSet) -> PostDraft {
    var next = state
    next.labels = labels
    return next
  }

  /// Grows the images embed, or starts one. A video or GIF owns the slot, so
  /// adding images to one is a no-op.
  static func applyAddImages(_ state: PostDraft, _ images: [ComposerImage]) -> PostDraft {
    guard !images.isEmpty else { return state }
    var next = state
    switch state.embed.media {
    case nil:
      next.embed.media = .images(.variant(for: images))
    case .images(let media):
      next.embed.media = .images(.variant(for: media.images + images))
    case .video, .gif:
      return state
    }
    return next
  }

  /// Replaces one image in place, by id.
  static func applyUpdateImage(_ state: PostDraft, _ image: ComposerImage) -> PostDraft {
    guard case .images(let media) = state.embed.media else { return state }
    let updated = media.images.map { $0.id == image.id ? image : $0 }
    var next = state
    next.embed.media = .images(.variant(for: updated))
    return next
  }

  /// Removes one image, re-picking the variant and clearing labels when the
  /// last image goes and no link card remains.
  static func applyRemoveImage(_ state: PostDraft, _ image: ComposerImage) -> PostDraft {
    guard case .images(let media) = state.embed.media else { return state }
    let remaining = media.images.filter { $0.id != image.id }
    var next = state
    if remaining.isEmpty {
      next.embed.media = nil
      if state.embed.link == nil { next.labels = SelfLabelSet() }
    } else {
      // Re-pick the variant so a gallery shrinking to <= 4 demotes back to the
      // legacy `images` shape.
      next.embed.media = .images(.variant(for: remaining))
    }
    return next
  }

  /// Attaches a video when the embed slot is free.
  static func applyAddVideo(_ state: PostDraft, _ video: ComposerVideo) -> PostDraft {
    guard state.embed.media == nil else { return state }
    var next = state
    next.embed.media = .video(video)
    return next
  }

  /// Feeds an action into the attached video's state machine.
  static func applyUpdateVideo(_ state: PostDraft, _ action: VideoAction) -> PostDraft {
    guard case .video(let current) = state.embed.media else { return state }
    var next = state
    next.embed.media = .video(VideoReducer.reduce(current, action))
    return next
  }

  /// Removes the video and clears labels when no link card remains.
  static func applyRemoveVideo(_ state: PostDraft) -> PostDraft {
    var next = state
    if case .video = state.embed.media {
      next.embed.media = nil
    }
    if state.embed.link == nil { next.labels = SelfLabelSet() }
    return next
  }

  /// Files a URI as a quote (post URLs) or a link card (everything else),
  /// without overwriting one already present.
  static func applyAddURI(_ state: PostDraft, _ uri: String) -> PostDraft {
    var next = state
    if URLHelpers.isBskyPostUrl(uri) {
      if state.embed.quote == nil { next.embed.quote = QuoteLink(uri: uri) }
    } else {
      if state.embed.link == nil { next.embed.link = ExternalLink(uri: uri) }
    }
    return next
  }

  /// Removes the link card, clearing labels when no media remains.
  static func applyRemoveLink(_ state: PostDraft) -> PostDraft {
    var next = state
    if state.embed.media == nil { next.labels = SelfLabelSet() }
    next.embed.link = nil
    return next
  }

  /// Removes the quote.
  static func applyRemoveQuote(_ state: PostDraft) -> PostDraft {
    var next = state
    next.embed.quote = nil
    return next
  }

  /// Attaches a GIF when the embed slot is free.
  static func applyAddGif(_ state: PostDraft, _ gif: GifMedia) -> PostDraft {
    guard state.embed.media == nil else { return state }
    var next = state
    next.embed.media = .gif(gif)
    return next
  }

  /// Replaces the GIF's alt text.
  static func applyGifAlt(_ state: PostDraft, _ alt: String) -> PostDraft {
    guard case .gif(let current) = state.embed.media else { return state }
    var next = state
    next.embed.media = .gif(GifMedia(gif: current.gif, alt: alt))
    return next
  }

  /// Removes the GIF.
  static func applyRemoveGif(_ state: PostDraft) -> PostDraft {
    guard case .gif = state.embed.media else { return state }
    var next = state
    next.embed.media = nil
    return next
  }
}
