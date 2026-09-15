import Moderation
import ProfileLogic
import UIComponentsCore

/// Fixture posts for the profile's feed tabs.
///
/// Built on the engine's stand-in ``PostView`` through ``GalleryFixtures`` so the
/// rows flow through the real ``feedItemViewData`` derivation and the real
/// ``PostFeedItem`` render path. The avatars and bodies are placeholders, and the
/// set is deterministic so screenshots are stable.
public enum ProfileFixturePosts {
  /// The render data for one page of a tab's fixture feed.
  public static func pages(for tab: ProfileTab, count: Int) -> [FeedItemViewData] {
    (0..<count).map { index in
      let post = GalleryFixtures.post(
        body(tab: tab, index: index),
        author: GalleryFixtures.profile(
          handle: "alice.bsky.social",
          displayName: "Alice"),
        embed: embed(tab: tab, index: index),
        indexedAt: "2026-09-14T12:00:00.000Z")
      return feedItemViewData(
        post,
        counts: FeedItemCounts(replyCount: 3 + index, repostCount: 5 + index, likeCount: 12 + index),
        options: FeedItemRenderOptions(now: GalleryFixtures.galleryNow))
    }
  }

  /// A short, tab-appropriate body.
  private static func body(tab: ProfileTab, index: Int) -> String {
    switch tab {
    case .posts: "A post about the open social web. (#\(index + 1))"
    case .replies: "A reply written on someone else's thread. (#\(index + 1))"
    case .media: "Some photos from today. (#\(index + 1))"
    case .videos: "A short clip. (#\(index + 1))"
    case .likes: "A post I liked. (#\(index + 1))"
    }
  }

  /// An embed appropriate to the tab.
  private static func embed(tab: ProfileTab, index: Int) -> PostViewEmbed? {
    switch tab {
    case .media: GalleryFixtures.images(index % 2 + 1)
    case .posts where index == 0: GalleryFixtures.external
    default: nil
    }
  }
}
