import Foundation
import Preferences

/// Reads the v2 saved-feeds preference into the ordered model.
///
/// Port of the `preferences.savedFeeds.filter(feed => feed.pinned)` reads in
/// `src/state/queries/feed.ts` and the `allFeeds` derivation in
/// `src/view/screens/Home.tsx`.
///
/// Saved order *is* pin order: ``PreferencesEngine`` maintains the array so the
/// timeline is first, then pinned feeds in their stored order, then saved-only
/// entries (see the v1 migration in `Hydrate.swift`). This helper preserves that
/// order and never sorts.
public enum SavedFeedReader {
  /// Every saved-feed entry, in stored order, dropping malformed records.
  public static func entries(from preferences: Preferences) -> [SavedFeedEntry] {
    preferences.savedFeeds.compactMap(SavedFeedEntry.init(prefObject:))
  }

  /// Only the pinned entries, in stored order. RN: `savedFeeds.filter(pinned)`.
  public static func pinnedEntries(from preferences: Preferences) -> [SavedFeedEntry] {
    entries(from: preferences).filter(\.pinned)
  }

  /// The v2 saved-feeds preference object type, for callers assembling a
  /// preference array by hand.
  public static let prefType = PrefType.savedFeedsPrefV2
}
