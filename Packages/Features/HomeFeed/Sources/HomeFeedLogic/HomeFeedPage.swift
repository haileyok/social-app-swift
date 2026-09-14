import Domain
import Foundation
import Lexicons
import QueryStore
import SwiftAtproto

/// One page's worth of tuned slices, derived from the store's page payload.
///
/// The store holds `InfiniteQueryData<HomeFeedSlice>` (the flattened, tuned
/// model), so this is a read-side grouping of a page rather than a stored shape.
public struct HomeFeedPage: Sendable {
  /// The tuned, renderable slices for this page.
  public var slices: [HomeFeedSlice]
  /// The page's next cursor.
  public var cursor: String?
  /// The cursor that produced this page.
  public var requestCursor: String?

  public init(
    slices: [HomeFeedSlice], cursor: String? = nil, requestCursor: String? = nil
  ) {
    self.slices = slices
    self.cursor = cursor
    self.requestCursor = requestCursor
  }

  /// Number of posts across this page's slices, the RN `itemCount` input.
  public var itemCount: Int { slices.reduce(0) { $0 + $1.items.count } }

  /// True when this page produced no slices.
  public var isEmpty: Bool { slices.isEmpty }
}

extension InfiniteQueryData where Item == HomeFeedSlice {
  /// The page-grouped view of the tuned slices.
  public var feedPages: [HomeFeedPage] {
    pages.map {
      HomeFeedPage(
        slices: $0.items, cursor: $0.cursor, requestCursor: $0.requestCursor)
    }
  }

  /// Every tuned slice across every page.
  public var slices: [HomeFeedSlice] { items }

  /// True when no page produced a single slice. Port of `isEmpty` in
  /// `src/view/com/posts/PostFeed.tsx`:
  /// `!data?.pages?.some(page => page.slices.length)`.
  public var isEmptyFeed: Bool { !pages.contains { !$0.items.isEmpty } }
}

/// The tuned, renderable home-feed payload, the Swift counterpart of
/// `InfiniteData<FeedPage>` in `src/state/queries/post-feed.ts`.
///
/// The store payload is `InfiniteQueryData<HomeFeedSlice>`: one *slice* per item,
/// so the store's item count - which drives ``QueryStore/autoPaginate`` - counts
/// slices rather than pages. That is what makes the ported auto-pagination
/// scheduler work on feed content.
///
/// Deviation: RN's `itemCount` sums `slice.items.length` (posts, so a thread
/// counts for its whole length), while `QueryStore.autoPaginate` compares slice
/// count. On a following feed most slices are single posts, so the two agree;
/// they diverge only on thread-heavy pages, where this port fills slightly less
/// per pass.
public typealias HomeFeedData = InfiniteQueryData<HomeFeedSlice>
