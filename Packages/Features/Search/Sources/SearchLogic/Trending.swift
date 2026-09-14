import Foundation
import Lexicons

/// The trending module's data transform.
///
/// Ported from the `select` callback of
/// `state/queries/trending/useGetTrendsQuery.ts`: dedupe by `link`, drop trends
/// whose `topic`/`displayName`/`category` text matches a muted word, then slice
/// to the display limit. The fetch limit (20 by default) is larger than the
/// display limit (5) precisely so the filter still has rows to show.
public enum Trending {
  /// The number of trends shown on the Explore module.
  public static let defaultDisplayLimit = 5
  /// The number of trends requested from the endpoint.
  public static let defaultFetchLimit = 20

  /// The filtered, sliced trends plus the recommendation id.
  public struct Trends: Sendable, Equatable {
    /// The trends to render.
    public let trends: [App.Bsky.UnspeccedDefs_TrendView]
    /// The snowflake to report recommendation events against, if any.
    public let recId: String?

    public init(trends: [App.Bsky.UnspeccedDefs_TrendView], recId: String? = nil) {
      self.trends = trends
      self.recId = recId
    }
  }

  /// Dedupes trends by `link`, preserving order.
  public static func dedupe(
    _ trends: [App.Bsky.UnspeccedDefs_TrendView]
  ) -> [App.Bsky.UnspeccedDefs_TrendView] {
    var seen = Set<String>()
    return trends.filter { seen.insert($0.link).inserted }
  }

  /// The text a muted word is matched against: `topic`, `displayName` and
  /// `category` joined with spaces, exactly as the RN select builds it.
  public static func mutedWordText(_ trend: App.Bsky.UnspeccedDefs_TrendView) -> String {
    "\(trend.topic) \(trend.displayName) \(trend.category ?? "")"
  }

  /// Applies the muted-word filter, dedupe and display-limit slice.
  ///
  /// - Parameters:
  ///   - data: the raw `getTrends` output.
  ///   - isMuted: predicate deciding whether a trend's text matches a muted
  ///     word. Injected so this package stays free of the moderation package;
  ///     the caller passes the same `hasMutedWord` check the RN select uses.
  ///   - limit: the display limit.
  public static func applyMutedWordFilter(
    _ data: App.Bsky.UnspeccedGetTrends_Output,
    isMuted: (String) -> Bool = { _ in false },
    limit: Int = defaultDisplayLimit
  ) -> Trends {
    let filtered = dedupe(data.trends).filter { !isMuted(mutedWordText($0)) }
    return Trends(trends: Array(filtered.prefix(limit)), recId: data.recIdStr)
  }
}
