import Foundation
import Preferences

/// The following-feed preferences, ported from
/// `screens/Settings/FollowingFeedPreferences.tsx`.
///
/// The RN screen shows positive toggles ("Show replies") and negates them
/// before writing, because the stored fields are `hide*`. That inversion is the
/// only interesting logic here, and it is reproduced exactly: the model exposes
/// *show* semantics and the write path negates.
///
/// The write goes to the `home` feed key. RN passes `feed: 'home'` and comments
/// that the following feed "was previously called `home`"; the preferences read
/// path merges that entry into `feedViewPrefs`.
public struct FollowingFeedPreferences: Sendable, Equatable {
  /// `!hideReplies`
  public var showReplies: Bool
  /// `!hideReposts`
  public var showReposts: Bool
  /// `!hideQuotePosts`
  public var showQuotePosts: Bool
  /// `lab_mergeFeedEnabled`, the "show samples of your saved feeds" toggle.
  public var mergeFeedEnabled: Bool

  public init(
    showReplies: Bool = true,
    showReposts: Bool = true,
    showQuotePosts: Bool = true,
    mergeFeedEnabled: Bool = false
  ) {
    self.showReplies = showReplies
    self.showReposts = showReposts
    self.showQuotePosts = showQuotePosts
    self.mergeFeedEnabled = mergeFeedEnabled
  }

  /// The RN defaults, from `DEFAULT_HOME_FEED_PREFS`.
  public static let `default` = FollowingFeedPreferences()

  /// Builds the show-semantics model from the stored view preference.
  public init(from stored: FeedViewPreference) {
    self.init(
      showReplies: !stored.hideReplies,
      showReposts: !stored.hideReposts,
      showQuotePosts: !stored.hideQuotePosts,
      mergeFeedEnabled: stored.lab_mergeFeedEnabled ?? false)
  }

  /// The wire fields this model produces for one field change, keyed by the
  /// stored (hide-semantics) member name.
  ///
  /// The engine's `FeedViewPrefPatch` keeps its member list internal, so the
  /// mapping the screen depends on is stated here instead: one entry per
  /// toggle, with the `hide*` fields negated and `lab_mergeFeedEnabled` not.
  public func wireFields(for field: Field) -> [String: Bool] {
    switch field {
    case .showReplies: return ["hideReplies": !showReplies]
    case .showReposts: return ["hideReposts": !showReposts]
    case .showQuotePosts: return ["hideQuotePosts": !showQuotePosts]
    case .mergeFeedEnabled: return ["lab_mergeFeedEnabled": mergeFeedEnabled]
    }
  }

  /// The patch this model produces for one field change.
  public func patch(for field: Field) -> FeedViewPrefPatch {
    switch field {
    case .showReplies: return FeedViewPrefPatch(hideReplies: !showReplies)
    case .showReposts: return FeedViewPrefPatch(hideReposts: !showReposts)
    case .showQuotePosts: return FeedViewPrefPatch(hideQuotePosts: !showQuotePosts)
    case .mergeFeedEnabled:
      return FeedViewPrefPatch(lab_mergeFeedEnabled: mergeFeedEnabled)
    }
  }

  /// The four toggles the screen renders.
  public enum Field: String, Sendable, Equatable, CaseIterable {
    case showReplies
    case showReposts
    case showQuotePosts
    case mergeFeedEnabled

    /// The toggle label RN renders.
    public var title: String {
      switch self {
      case .showReplies: return "Show replies"
      case .showReposts: return "Show reposts"
      case .showQuotePosts: return "Show quote posts"
      case .mergeFeedEnabled:
        return "Show samples of your saved feeds in your Following feed"
      }
    }

    /// Whether RN renders the toggle inside the experimental group.
    public var isExperimental: Bool {
      self == .mergeFeedEnabled
    }
  }

  /// The screen's rows, in order.
  public static let fields: [Field] = [
    .showReplies, .showReposts, .showQuotePosts, .mergeFeedEnabled,
  ]

  /// Reads a toggle's current value.
  public func value(of field: Field) -> Bool {
    switch field {
    case .showReplies: return showReplies
    case .showReposts: return showReposts
    case .showQuotePosts: return showQuotePosts
    case .mergeFeedEnabled: return mergeFeedEnabled
    }
  }

  /// The feed key RN writes these preferences under.
  public static let feedKey = "home"
}

/// The thread preferences, ported from `useThreadPreferences.ts` and
/// `screens/Settings/ThreadPreferences.tsx`.
///
/// Two values: the reply sort, and whether the tree view is on. RN's
/// `normalizeSort` maps anything unrecognized (including the historic
/// `hotness`) onto `top`, and `normalizeView` collapses the boolean into
/// `tree`/`linear`.
public struct ThreadPreferences: Sendable, Equatable {
  /// The reply sort option.
  public var sort: ThreadSortOption
  /// Whether replies render as a tree.
  public var view: ThreadViewOption

  public init(
    sort: ThreadSortOption = ThreadPreferences.defaultSort,
    view: ThreadViewOption = .linear
  ) {
    self.sort = sort
    self.view = view
  }

  /// `DEFAULT_THREAD_VIEW_PREFS.sort` is `hotness`, which normalizes to `top`.
  public static let defaultSort: ThreadSortOption = .top

  /// Builds the model from the stored thread view preference.
  public init(from stored: ThreadViewPreference) {
    self.init(
      sort: ThreadPreferences.normalizeSort(stored.sort),
      view: ThreadPreferences.normalizeView(
        treeViewEnabled: stored.lab_treeViewEnabled ?? false))
  }

  /// The wire fields this preference writes, keyed by member name.
  ///
  /// Mirrors ``wireFields(for:)`` for the thread pref, and exists for the same
  /// reason: the engine's patch type keeps its members internal.
  public var wireFields: [String: String] {
    ["sort": sort.rawValue, "lab_treeViewEnabled": view == .tree ? "true" : "false"]
  }

  /// The patch for a save.
  public var patch: ThreadViewPrefPatch {
    ThreadViewPrefPatch(sort: sort.rawValue, lab_treeViewEnabled: view == .tree)
  }

  /// `normalizeSort`: anything but `oldest`/`newest` is `top`.
  ///
  /// This is also the migration for the pre-V2 sort values; RN notes that
  /// `hotness` is the historic default.
  public static func normalizeSort(_ sort: String) -> ThreadSortOption {
    switch sort {
    case "oldest": return .oldest
    case "newest": return .newest
    default: return .top
    }
  }

  /// `normalizeView`: `treeViewEnabled` becomes `tree`/`linear`.
  public static func normalizeView(treeViewEnabled: Bool) -> ThreadViewOption {
    treeViewEnabled ? .tree : .linear
  }
}

/// The reply sort options. RN types this against
/// `app.bsky.unspecced.getPostThreadV2.$Params['sort']`.
public enum ThreadSortOption: String, Sendable, Equatable, CaseIterable {
  case top
  case oldest
  case newest

  /// The radio label RN renders.
  public var title: String {
    switch self {
    case .top: return "Top replies first"
    case .oldest: return "Oldest replies first"
    case .newest: return "Newest replies first"
    }
  }
}

/// The thread view options.
public enum ThreadViewOption: String, Sendable, Equatable, CaseIterable {
  case linear
  case tree
}
