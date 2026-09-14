import Foundation
import Testing

@testable import Domain
@testable import Lexicons

/// Port of `src/lib/api/feed-manip.test.ts`.
///
/// The RN test mocks `./feed/home` to avoid pulling the feed module's
/// dependencies; the equivalent here is that ``Fixtures`` builds the posts
/// directly, so no module mock is needed.
@Suite("createFeedViewPostsSlices")
struct FeedManipTests {

  /// `src/lib/api/feed-manip.test.ts` - "preserves selected numbering and
  /// infers hydrated parent and root numbering".
  @Test func preservesSelectedNumberingAndInfersHydratedParentAndRootNumbering() {
    let root = Fixtures.post("root")
    let parent = Fixtures.post("parent")
    let selected = Fixtures.post("selected")

    let feedPost = Fixtures.feedViewPost(
      post: selected,
      reply: Fixtures.replyRef(
        parent: Fixtures.postViewReply(parent),
        root: Fixtures.postViewRoot(root)),
      opThreadPostIndex: 3,
      opThreadPostCount: 4
    )

    let slices = createFeedViewPostsSlices([feedPost])
    let slice = try! #require(slices.first)

    let actual = slice.items.map { item in
      [item.post.uri.rawValue, item.postNumbering?.opThreadPostIndex ?? 0,
       item.postNumbering?.opThreadPostCount ?? 0] as [Any]
    }
    let expected: [[Any]] = [
      [root.uri.rawValue, 1, 4],
      [parent.uri.rawValue, 2, 4],
      [selected.uri.rawValue, 3, 4],
    ]

    #expect(actual.count == expected.count)
    for (a, e) in zip(actual, expected) {
      #expect(a[0] as? String == e[0] as? String)
      #expect(a[1] as? Int == e[1] as? Int)
      #expect(a[2] as? Int == e[2] as? Int)
    }
  }

  /// `getPostNumbering` rejects out-of-range or missing numbering, so the
  /// inferred parent/root numbering is absent rather than clamped.
  @Test func rejectsInvalidNumbering() {
    let selected = Fixtures.post("selected")
    let parent = Fixtures.post("parent")
    let root = Fixtures.post("root")

    for (index, count) in [(0, 4), (5, 4), (3, 0)] {
      let feedPost = Fixtures.feedViewPost(
        post: selected,
        reply: Fixtures.replyRef(
          parent: Fixtures.postViewReply(parent),
          root: Fixtures.postViewRoot(root)),
        opThreadPostIndex: index,
        opThreadPostCount: count
      )
      let slice = createFeedViewPostsSlices([feedPost]).first
      #expect(slice?.items.allSatisfy { $0.postNumbering == nil } == true)
    }
  }
}
