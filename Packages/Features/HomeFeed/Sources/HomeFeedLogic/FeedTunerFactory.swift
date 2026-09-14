import Domain
import Foundation
import Preferences

/// The preference inputs the tuner stack depends on.
///
/// Port of the `useMemo` dependency list in `src/state/preferences/feed-tuners.tsx`:
/// the feed's own view prefs plus the content languages and the signed-in DID.
public struct FeedTunerOptions: Sendable, Equatable {
  /// `feedViewPrefs` for the feed. RN reads the top-level `feedViewPrefs`.
  public var hideReposts: Bool
  public var hideReplies: Bool
  public var hideQuotePosts: Bool
  /// `contentLanguages`, the language filter for feedgens.
  public var contentLanguages: [String]
  /// The signed-in DID, used by `followedRepliesOnly`.
  public var userDid: String

  public init(
    hideReposts: Bool = false,
    hideReplies: Bool = false,
    hideQuotePosts: Bool = false,
    contentLanguages: [String] = [],
    userDid: String = ""
  ) {
    self.hideReposts = hideReposts
    self.hideReplies = hideReplies
    self.hideQuotePosts = hideQuotePosts
    self.contentLanguages = contentLanguages
    self.userDid = userDid
  }

  /// Reads the tuner options for `descriptor` out of an interpreted preferences
  /// value. `feedViewPrefs` is keyed by feed id, with `home` for the timeline.
  public static func from(
    preferences: Preferences, descriptor: FeedDescriptor, userDid: String,
    contentLanguages: [String]
  ) -> FeedTunerOptions {
    let key: String
    switch descriptor {
    case .following: key = "home"
    case .feedgen(let uri), .list(let uri): key = uri
    }
    let pref = preferences.feedViewPrefs[key] ?? FeedViewPreference(feed: key)
    return FeedTunerOptions(
      hideReposts: pref.hideReposts,
      hideReplies: pref.hideReplies,
      hideQuotePosts: pref.hideQuotePosts,
      contentLanguages: contentLanguages,
      userDid: userDid)
  }
}

/// Builds the tuner stack for a feed descriptor.
///
/// Port of `useFeedTuners` in `src/state/preferences/feed-tuners.tsx`. The
/// ordering is load-bearing: `removeOrphans` runs before the preference
/// filters, and `dedupThreads` runs after them so thread de-duplication sees the
/// surviving slices.
///
/// ```
/// following | list:
///   removeOrphans
///   [hideReposts]  -> removeReposts
///   hideReplies    -> removeReplies
///   !hideReplies   -> followedRepliesOnly(userDid)
///   [hideQuotePosts] -> removeQuotePosts
///   dedupThreads
///   removeMutedThreads
///
/// feedgen:
///   preferredLangOnly(contentLanguages)
///   removeMutedThreads
/// ```
public enum FeedTunerFactory {
  /// The tuner functions for `descriptor`, in application order.
  public static func tuners(
    for descriptor: FeedDescriptor, options: FeedTunerOptions
  ) -> [FeedTunerFn] {
    switch descriptor {
    case .feedgen:
      return [
        FeedTuner.preferredLangOnly(options.contentLanguages),
        FeedTuner.removeMutedThreads,
      ]
    case .following, .list:
      var tuners: [FeedTunerFn] = [FeedTuner.removeOrphans]
      if options.hideReposts {
        tuners.append(FeedTuner.removeReposts)
      }
      if options.hideReplies {
        tuners.append(FeedTuner.removeReplies)
      } else {
        tuners.append(FeedTuner.followedRepliesOnly(userDid: options.userDid))
      }
      if options.hideQuotePosts {
        tuners.append(FeedTuner.removeQuotePosts)
      }
      tuners.append(FeedTuner.dedupThreads)
      tuners.append(FeedTuner.removeMutedThreads)
      return tuners
    }
  }

  /// A fresh ``FeedTuner`` for `descriptor`. A tuner carries the cross-page
  /// de-duplication state, so one instance belongs to one query.
  public static func makeTuner(
    for descriptor: FeedDescriptor, options: FeedTunerOptions
  ) -> FeedTuner {
    FeedTuner(tunerFns: tuners(for: descriptor, options: options))
  }
}
