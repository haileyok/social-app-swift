import RichText

/// Constants shared by the composer state machine and record construction.
///
/// Ported from `src/lib/constants.ts` and
/// `src/view/com/composer/state/composer.ts` in the RN app.
public enum ComposerConstants {
  /// `MAX_GRAPHEME_LENGTH` - the per-post limit, measured *after* link
  /// shortening. Re-exported from ``RichTextLimits/post`` so the composer and
  /// RichText cannot drift apart.
  public static let maxGraphemeLength = RichTextLimits.post

  /// `MAX_DRAFT_GRAPHEME_LENGTH` - the looser limit applied when text is held
  /// in a draft rather than published.
  public static let maxDraftGraphemeLength = RichTextLimits.draft

  /// `MAX_ALT_TEXT` - the per-image and per-video alt text limit.
  public static let maxAltText = RichTextLimits.altText

  /// `LEGACY_IMAGES_EMBED_MAX` - at or below this count the composer writes the
  /// legacy `app.bsky.embed.images` shape; above it, `app.bsky.embed.gallery`.
  public static let legacyImagesEmbedMax = 4

  /// `MAX_GALLERY_IMAGES` - the client-side soft cap on gallery items. The
  /// lexicon's schema ceiling is 20; the RN picker enforces 10.
  public static let maxGalleryImages = 10

  /// The lexicon's schema ceiling for gallery items (`app.bsky.embed.gallery`).
  public static let maxGalleryImagesSchema = 20

  /// The number of languages the composer will attach to a post. Mirrors the
  /// `langs.slice(0, 3)` in `lib/api/index.ts`, which the lexicon also enforces
  /// (`maxLength: 3`).
  public static let maxLanguages = 3

  /// `VIDEO_MAX_SIZE_MB` - the client-side pre-compression size ceiling.
  public static let videoMaxSizeMB = 100

  /// The interval between `getJobStatus` polls while a video is processing
  /// (1500 ms in `state/video.ts`).
  public static let videoPollIntervalSeconds = 1.5

  /// The interval between retries after a *failed* poll request (5000 ms).
  public static let videoPollRetryIntervalSeconds = 5.0

  /// `pollFailures < 50` - consecutive failed poll requests tolerated before
  /// the job is reported as failed.
  public static let videoMaxPollFailures = 50
}
