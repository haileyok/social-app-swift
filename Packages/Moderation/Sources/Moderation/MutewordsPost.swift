import Foundation

/// The stable inputs for matching mute words across a post and its embeds.
struct PostMuteWordsContext {
  let subjectPost: FeedPostRecord?
  let postAuthor: ProfileViewBasic
  let now: Date
}

/// Matches every piece of text the engine considers part of a post: its own
/// text and tags, its images and gallery alt text, and the same surfaces of a
/// quoted post. Returns the first non-empty match set, in engine order.
public func matchAllMuteWords(
  _ subject: PostView,
  mutedWords: [MutedWord],
  now: Date = Date()
) -> [MutedWordMatch]? {
  if mutedWords.isEmpty { return nil }
  let postAuthor = subject.author
  let subjectPost = isPostRecord(subject.record) ? subject.record : nil
  let context = PostMuteWordsContext(
    subjectPost: subjectPost, postAuthor: postAuthor, now: now)

  if let post = subjectPost,
    let matches = matchPostRecord(post, author: postAuthor, mutedWords: mutedWords, now: now) {
    return matches
  }
  guard let embed = subject.embed else { return nil }
  return matchViewEmbed(embed, context: context, mutedWords: mutedWords)
}

/// Matches a post record's text, tags, and its own images and gallery, using
/// the post's own languages.
private func matchPostRecord(
  _ post: FeedPostRecord,
  author: ProfileViewBasic,
  mutedWords: [MutedWord],
  now: Date
) -> [MutedWordMatch]? {
  if let matches = matchPostText(post, actor: author, mutedWords: mutedWords, now: now) {
    return matches
  }
  let languages = post.langs
  switch post.embed {
  case .images(let images):
    return matchImages(images, languages: languages, actor: author, mutedWords: mutedWords, now: now)
  case .gallery(let items):
    return matchGallery(items, languages: languages, actor: author, mutedWords: mutedWords, now: now)
  default:
    return nil
  }
}

/// Matches a hydrated (view) embed: a quoted post, a link card, or a quoted
/// post with media.
private func matchViewEmbed(
  _ embed: PostViewEmbed,
  context: PostMuteWordsContext,
  mutedWords: [MutedWord]
) -> [MutedWordMatch]? {
  switch embed {
  case .record(let record):
    guard let viewRecord = record.record?.viewRecord,
      let quotedPost = viewRecord.value,
      isPostRecord(quotedPost),
      let embedAuthor = viewRecord.author
    else { return nil }
    return matchQuotedPost(
      quotedPost, author: embedAuthor, mutedWords: mutedWords, now: context.now)
  case .external(let external):
    // link card
    return matchExternal(
      external, actor: context.postAuthor, mutedWords: mutedWords, now: context.now)
  case .recordWithMedia(let media):
    guard let viewRecord = media.record?.record?.viewRecord,
      let embedAuthor = viewRecord.author
    else { return nil }
    return matchRecordWithMedia(
      media,
      quotedPost: viewRecord.value,
      author: embedAuthor,
      context: context,
      mutedWords: mutedWords
    )
  default:
    return nil
  }
}

/// Matches a quoted post's text, images, gallery, link card, and the media of
/// a nested quote-with-media. Languages come from the quoted post except where
/// the engine (deliberately) omits them.
private func matchQuotedPost(
  _ post: FeedPostRecord,
  author: ProfileViewBasic,
  mutedWords: [MutedWord],
  now: Date
) -> [MutedWordMatch]? {
  if let matches = matchPostText(post, actor: author, mutedWords: mutedWords, now: now) {
    // quoted post text
    return matches
  }
  let languages = post.langs
  switch post.embed {
  case .images(let images):
    // quoted post's images
    if let matches = matchImages(
      images, languages: languages, actor: author, mutedWords: mutedWords, now: now
    ) {
      return matches
    }
  case .gallery(let items):
    // quoted post's gallery
    if let matches = matchGallery(
      items, languages: languages, actor: author, mutedWords: mutedWords, now: now
    ) {
      return matches
    }
  case .external(let external):
    // quoted post's link card
    return matchExternal(external, actor: author, mutedWords: mutedWords, now: now)
  case .recordWithMedia(let recordWithMedia):
    return matchNestedRecordWithMedia(
      recordWithMedia, author: author, mutedWords: mutedWords, now: now
    )
  default:
    break
  }
  return nil
}

/// Matches the media of a quoted post that itself carried a quote-with-media.
/// The engine intentionally passes no languages for images and gallery here.
private func matchNestedRecordWithMedia(
  _ recordWithMedia: RecordWithMediaMain,
  author: ProfileViewBasic,
  mutedWords: [MutedWord],
  now: Date
) -> [MutedWordMatch]? {
  switch recordWithMedia.media {
  case .external(let external):
    // quoted post's link card when it did a quote + media
    return matchExternal(external, actor: author, mutedWords: mutedWords, now: now)
  case .images(let images):
    // NOTE: preserves a latent quirk of the original implementation, which
    // never populated languages here; fixing this changes muteword matching
    // behavior and should be its own change.
    return matchImages(images, languages: [], actor: author, mutedWords: mutedWords, now: now)
  case .gallery(let items):
    // NOTE: preserves a latent quirk of the original implementation.
    return matchGallery(items, languages: [], actor: author, mutedWords: mutedWords, now: now)
  default:
    return nil
  }
}

/// Matches the quoted text and media of an `recordWithMedia#view`, using the
/// quoting post's languages for images and gallery.
private func matchRecordWithMedia(
  _ media: EmbedRecordWithMediaView,
  quotedPost: FeedPostRecord?,
  author: ProfileViewBasic,
  context: PostMuteWordsContext,
  mutedWords: [MutedWord]
) -> [MutedWordMatch]? {
  let now = context.now
  if let quotedPost, isPostRecord(quotedPost),
    let matches = matchPostText(quotedPost, actor: author, mutedWords: mutedWords, now: now) {
    // quoted post text
    return matches
  }
  let languages = context.subjectPost?.langs ?? []
  switch media.media {
  case .images(let images):
    // quoted post images
    return matchImages(images, languages: languages, actor: author, mutedWords: mutedWords, now: now)
  case .gallery(let items):
    // quoted post gallery
    return matchGallery(items, languages: languages, actor: author, mutedWords: mutedWords, now: now)
  case .external(let external):
    return matchExternal(external, actor: author, mutedWords: mutedWords, now: now)
  default:
    return nil
  }
}

/// Matches a post's own text plus its facet tags and outline tags.
private func matchPostText(
  _ post: FeedPostRecord,
  actor: ProfileViewBasic,
  mutedWords: [MutedWord],
  now: Date
) -> [MutedWordMatch]? {
  matchMuteWords(
    mutedWords: mutedWords,
    text: post.text,
    facets: post.facets,
    outlineTags: post.tags,
    languages: post.langs,
    actor: actor,
    now: now
  )
}

/// Matches each image's alt text, returning the first match.
private func matchImages(
  _ images: [EmbedImage],
  languages: [String]?,
  actor: ProfileViewBasic,
  mutedWords: [MutedWord],
  now: Date
) -> [MutedWordMatch]? {
  for image in images {
    if let matches = matchMuteWords(
      mutedWords: mutedWords,
      text: image.alt ?? "",
      languages: languages,
      actor: actor,
      now: now
    ) {
      return matches
    }
  }
  return nil
}

/// Matches each gallery item's alt text, returning the first match.
private func matchGallery(
  _ items: [EmbedGalleryItem],
  languages: [String]?,
  actor: ProfileViewBasic,
  mutedWords: [MutedWord],
  now: Date
) -> [MutedWordMatch]? {
  for item in items {
    guard let alt = item.alt else { continue }
    if let matches = matchMuteWords(
      mutedWords: mutedWords,
      text: alt,
      languages: languages,
      actor: actor,
      now: now
    ) {
      return matches
    }
  }
  return nil
}

/// Matches a link card's title and description. The engine passes no
/// languages for link cards.
private func matchExternal(
  _ external: EmbedExternal,
  actor: ProfileViewBasic,
  mutedWords: [MutedWord],
  now: Date
) -> [MutedWordMatch]? {
  matchMuteWords(
    mutedWords: mutedWords,
    text: "\(external.title ?? "") \(external.description ?? "")",
    languages: [],
    actor: actor,
    now: now
  )
}

/// Whether a raw post record is actually an `app.bsky.feed.post`. The engine's
/// `$isTypeOf` discriminates on `$type`; a record without one is not a post.
private func isPostRecord(_ record: FeedPostRecord?) -> Bool {
  record?.type == "app.bsky.feed.post"
}
