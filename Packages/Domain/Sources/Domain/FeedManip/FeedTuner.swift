import Foundation
import Lexicons

// Port of the `FeedTuner` class from `src/lib/api/feed-manip.ts`.

// MARK: - Tuner

/// The tuner step signature.
public typealias FeedTunerFn = @Sendable (FeedTuner, [FeedViewPostsSlice], Bool) -> [FeedViewPostsSlice]

/// Dedupes and filters feed slices across pages.
public final class FeedTuner {
  public var seenKeys: Set<String> = []
  public var seenUris: Set<String> = []
  public var seenRootUris: Set<String> = []
  public let tunerFns: [FeedTunerFn]

  public init(tunerFns: [FeedTunerFn]) {
    self.tunerFns = tunerFns
  }

  public func tune(_ feed: [FeedViewPost], dryRun: Bool = false) -> [FeedViewPostsSlice] {
    var slices = createFeedViewPostsSlices(feed)

    // Run the custom tuners.
    for tunerFn in tunerFns {
      slices = tunerFn(self, Array(slices), dryRun)
    }

    slices = slices.filter { slice in
      if seenKeys.contains(slice.reactKey) {
        return false
      }
      // Some feeds, like Following, dedupe by thread, so you only see the most
      // recent reply. However, we don't want per-thread dedupe for author feeds
      // (where we need to show every post) or for feedgens (where we want to
      // let the feed serve multiple replies if it chooses to). To avoid showing
      // the same context (root and/or parent) more than once, we do last resort
      // per-post deduplication. It hides already seen posts as long as this
      // doesn't break the thread.
      var i = 0
      while i < slice.items.count {
        let item = slice.items[i]
        if seenUris.contains(item.post.uri.rawValue) {
          if i == 0 {
            // Omit contiguous seen leading items.
            // For example, [A -> B -> C], [A -> D -> E], [A -> D -> F]
            // would turn into [A -> B -> C], [D -> E], [F].
            slice.items.remove(at: 0)
            i -= 1
          }
          if i == slice.items.count - 1 {
            // If the last item in the slice was already seen, omit the whole
            // slice. This means we'd miss its parents, but the user can "show
            // more" to see them.
            return false
          }
        } else {
          if !dryRun {
            // Reposting a reply elevates it to top-level, so its parent/root
            // won't be displayed. Disable in-thread dedupe for this case since
            // we don't want to miss them later.
            let disableDedupe = slice.isReply && slice.isRepost
            if !disableDedupe {
              seenUris.insert(item.post.uri.rawValue)
            }
          }
        }
        i += 1
      }
      if !dryRun {
        seenKeys.insert(slice.reactKey)
      }
      return true
    }

    return slices
  }

  // MARK: Static tuner steps

  public static func removeReplies(tuner _: FeedTuner, slices: [FeedViewPostsSlice], dryRun _: Bool)
    -> [FeedViewPostsSlice] {
    var slices = slices
    var i = 0
    while i < slices.count {
      let slice = slices[i]
      if slice.isReply && !slice.isRepost && !areSameAuthor(slice.getAuthors()) {
        slices.remove(at: i)
        continue
      }
      i += 1
    }
    return slices
  }

  public static func removeReposts(tuner _: FeedTuner, slices: [FeedViewPostsSlice], dryRun _: Bool)
    -> [FeedViewPostsSlice] {
    var slices = slices
    var i = 0
    while i < slices.count {
      if slices[i].isRepost {
        slices.remove(at: i)
        continue
      }
      i += 1
    }
    return slices
  }

  public static func removeQuotePosts(tuner _: FeedTuner, slices: [FeedViewPostsSlice], dryRun _: Bool)
    -> [FeedViewPostsSlice] {
    var slices = slices
    var i = 0
    while i < slices.count {
      if slices[i].isQuotePost {
        slices.remove(at: i)
        continue
      }
      i += 1
    }
    return slices
  }

  public static func removeOrphans(tuner _: FeedTuner, slices: [FeedViewPostsSlice], dryRun _: Bool)
    -> [FeedViewPostsSlice] {
    var slices = slices
    var i = 0
    while i < slices.count {
      if slices[i].isOrphan {
        slices.remove(at: i)
        continue
      }
      i += 1
    }
    return slices
  }

  public static func removeMutedThreads(tuner _: FeedTuner, slices: [FeedViewPostsSlice], dryRun _: Bool)
    -> [FeedViewPostsSlice] {
    var slices = slices
    var i = 0
    while i < slices.count {
      if slices[i].isThreadMuted {
        slices.remove(at: i)
        continue
      }
      i += 1
    }
    return slices
  }

  public static func dedupThreads(tuner: FeedTuner, slices: [FeedViewPostsSlice], dryRun: Bool)
    -> [FeedViewPostsSlice] {
    var slices = slices
    var i = 0
    while i < slices.count {
      let rootUri = slices[i].rootUri
      if !slices[i].isRepost && tuner.seenRootUris.contains(rootUri) {
        slices.remove(at: i)
        continue
      } else if !dryRun {
        tuner.seenRootUris.insert(rootUri)
      }
      i += 1
    }
    return slices
  }

  /// Keeps only replies from the user or people they follow.
  public static func followedRepliesOnly(userDid: String) -> FeedTunerFn {
    { _, slices, _ in
      var slices = slices
      var i = 0
      while i < slices.count {
        let slice = slices[i]
        if slice.isReply && !slice.isRepost
          && !shouldDisplayReplyInFollowing(slice.getAuthors(), userDid: userDid) {
          slices.remove(at: i)
          continue
        }
        i += 1
      }
      return slices
    }
  }

  /// Keeps only slices whose items are in a preferred language.
  ///
  /// Deviation: `isPostInLanguage` runs the `lande` language model for posts
  /// with more than one declared language. That model is not ported, so the
  /// model path behaves as "language undetermined", which the RN code treats as
  /// a match. Posts with exactly one declared language are matched exactly.
  public static func preferredLangOnly(_ preferredLangsCode2: [String]) -> FeedTunerFn {
    { _, slices, _ in
      if preferredLangsCode2.isEmpty {
        return slices
      }

      let candidateSlices = slices.filter { slice in
        slice.items.contains { isPostInLanguage($0.post, targetLangs: preferredLangsCode2) }
      }

      // If the language filter cleared out the entire page, return the original
      // set so that something always shows.
      if candidateSlices.isEmpty {
        return slices
      }

      return candidateSlices
    }
  }
}

// MARK: - Author predicates

/// Whether every author in the context shares the selected post's DID.
func areSameAuthor(_ authors: AuthorContext) -> Bool {
  let authorDid = authors.author.did.rawValue
  if let parentAuthor = authors.parentAuthor, parentAuthor.did.rawValue != authorDid {
    return false
  }
  if let grandparentAuthor = authors.grandparentAuthor,
    grandparentAuthor.did.rawValue != authorDid {
    return false
  }
  if let rootAuthor = authors.rootAuthor, rootAuthor.did.rawValue != authorDid {
    return false
  }
  return true
}

func shouldDisplayReplyInFollowing(_ authors: AuthorContext, userDid: String) -> Bool {
  let authorDid = authors.author.did.rawValue
  if !isSelfOrFollowing(authors.author, userDid: userDid) {
    // Only show replies from self or people you follow.
    return false
  }
  if (authors.parentAuthor == nil || authors.parentAuthor?.did.rawValue == authorDid)
    && (authors.rootAuthor == nil || authors.rootAuthor?.did.rawValue == authorDid)
    && (authors.grandparentAuthor == nil || authors.grandparentAuthor?.did.rawValue == authorDid) {
    // Always show self-threads.
    return true
  }
  // From this point on we need at least one more reason to show it.
  if let parentAuthor = authors.parentAuthor, parentAuthor.did.rawValue != authorDid,
    isSelfOrFollowing(parentAuthor, userDid: userDid) {
    return true
  }
  if let grandparentAuthor = authors.grandparentAuthor,
    grandparentAuthor.did.rawValue != authorDid,
    isSelfOrFollowing(grandparentAuthor, userDid: userDid) {
    return true
  }
  if let rootAuthor = authors.rootAuthor, rootAuthor.did.rawValue != authorDid,
    isSelfOrFollowing(rootAuthor, userDid: userDid) {
    return true
  }
  return false
}

func isSelfOrFollowing(_ profile: App.Bsky.ActorDefs_ProfileViewBasic, userDid: String) -> Bool {
  profile.did.rawValue == userDid || profile.viewer?.following != nil
}

// MARK: - Language matching

/// Port of `isPostInLanguage` from `src/locale/helpers.ts`.
///
/// Deviation: the text-model path (`lande`) is not ported; a post with more
/// than one declared language and non-empty text is treated as undetermined,
/// which returns `true` (the RN "no language found" behaviour).
public func isPostInLanguage(_ post: App.Bsky.FeedDefs_PostView, targetLangs: [String]) -> Bool {
  guard let lang = getPostLanguage(post) else {
    // The post has no determinable language, so we just say "yes" for now.
    return true
  }
  return basicFilter(lang: lang, ranges: targetLangs) > 0
}

func getPostLanguage(_ post: App.Bsky.FeedDefs_PostView) -> String? {
  let candidates = post.record.feedPostRecord?.langs?.map { $0.rawValue } ?? []

  // If there's only one declared language, use that.
  if candidates.count == 1 {
    return candidates[0]
  }
  return nil
}

/// `bcp-47-match` `basicFilter`: the count of target language ranges that match.
func basicFilter(lang: String, ranges: [String]) -> Int {
  ranges.filter { matchesLanguageRange(lang: lang, range: $0) }.count
}

/// Approximates `bcp-47-match` `basicFilter` semantics: case-insensitive,
/// `*` matches anything, and a prefix subtag match is accepted.
func matchesLanguageRange(lang: String, range: String) -> Bool {
  if range == "*" { return true }
  let langParts = lang.lowercased().split(separator: "-").map(String.init)
  let rangeParts = range.lowercased().split(separator: "-").map(String.init)
  guard !rangeParts.isEmpty, langParts.count >= rangeParts.count else { return false }
  for (index, part) in rangeParts.enumerated() where part != "*" {
    if langParts[index] != part { return false }
  }
  return true
}

// MARK: - Lexicon helpers

extension UnknownATPValue {
  /// The `app.bsky.feed.post` record, when this value is one.
  var feedPostRecord: App.Bsky.FeedPost? {
    if case .record(let record) = self {
      return record as? App.Bsky.FeedPost
    }
    return nil
  }
}

extension App.Bsky.FeedDefs_ReplyRef_Parent {
  /// The underlying post view, when this branch is one.
  public var postView: App.Bsky.FeedDefs_PostView? {
    if case .feedDefsPostView(let view) = self { return view }
    return nil
  }

  public var isBlocked: Bool {
    if case .feedDefsBlockedPost = self { return true }
    return false
  }

  public var isNotFound: Bool {
    if case .feedDefsNotFoundPost = self { return true }
    return false
  }
}

extension App.Bsky.FeedDefs_ReplyRef_Root {
  /// The underlying post view, when this branch is one.
  public var postView: App.Bsky.FeedDefs_PostView? {
    if case .feedDefsPostView(let view) = self { return view }
    return nil
  }

  public var isBlocked: Bool {
    if case .feedDefsBlockedPost = self { return true }
    return false
  }

  public var isNotFound: Bool {
    if case .feedDefsNotFoundPost = self { return true }
    return false
  }

  /// The root uri without unwrapping to a post view.
  var uriValue: String {
    switch self {
    case .feedDefsPostView(let view): return view.uri.rawValue
    case .feedDefsBlockedPost(let blocked): return blocked.uri.rawValue
    case .feedDefsNotFoundPost(let notFound): return notFound.uri.rawValue
    case ._other: return ""
    }
  }
}
