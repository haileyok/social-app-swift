import Foundation
import Lexicons
import Testing

@testable import PostThreadLogic

/// Show-more: the parent and reply windows.
///
/// Ports RN's `maxParents`/`maxReplies` chunking in `PostThread.tsx`
/// (commit `c5641ac2b`): `PARENTS_CHUNK_SIZE = 15`, a reply cap of 100, and a
/// `LOAD_MORE` sentinel appended when replies are truncated.
@Suite("Show more")
struct ShowMoreTests {
  /// A thread with `parentCount` ancestors above the anchor.
  static func threadWithParents(_ parentCount: Int) -> FlattenedThread {
    // Build root <- p1 <- p2 <- ... <- anchor, then flatten.
    var chain: ThreadNode = Fixtures.post("at://root")
    for index in 1..<parentCount {
      chain = Fixtures.post("at://p\(index)", parent: chain)
    }
    let anchor = Fixtures.post("at://anchor", parent: chain)
    return ThreadFlattener.flatten(Fixtures.withDepths(anchor))
  }

  /// A thread whose anchor has `replyCount` replies.
  static func threadWithReplies(_ replyCount: Int) -> FlattenedThread {
    let replies = (0..<replyCount).map { Fixtures.post("at://r\($0)") }
    return ThreadFlattener.flatten(
      Fixtures.withDepths(Fixtures.post("at://anchor", replies: replies)))
  }

  @Test("the default window is one parent chunk and a 100-reply cap")
  func defaults() {
    #expect(ThreadShowMore.defaultParentsChunkSize == 15)
    #expect(ThreadShowMore.defaultMaxReplies == 100)
    #expect(ThreadShowMore.initial().maxParents == 15)
  }

  @Test("a short parent chain is shown whole")
  func shortChain() {
    let thread = Self.threadWithParents(3)
    let window = ThreadShowMore.initial().window(thread)
    #expect(window.map(\.uri) == ["at://root", "at://p1", "at://p2", "at://anchor"])
  }

  @Test("a long parent chain keeps only the last chunk, nearest the anchor")
  func longChainWindowsTheTail() {
    // 19 parents + anchor.
    let thread = Self.threadWithParents(19)
    let window = ThreadShowMore.initial().window(thread)

    // The nearest parent and the anchor are always present.
    #expect(window.contains { $0.uri == "at://anchor" })
    #expect(window.contains { $0.uri == "at://p18" })

    // The oldest parent is withheld. (The read-more-up row points *at* the
    // oldest withheld parent, so compare only the post rows.)
    let parentRows = window.filter(\.isPost).filter { !$0.isAnchor }
    #expect(!parentRows.contains { $0.uri == "at://root" })
    #expect(parentRows.count == 15)

    // The first row is the read-more-up affordance standing in for the
    // withheld ancestors.
    guard case .readMore(let content) = window[0].content else {
      Issue.record("expected a read-more row")
      return
    }
    #expect(content.direction == .up)
    #expect(content.moreReplies == 19 - 15)
  }

  @Test("revealing more parents grows the window by one chunk")
  func revealMoreParents() {
    let thread = Self.threadWithParents(19)
    var showMore = ThreadShowMore.initial()
    showMore = showMore.revealingMoreParents()
    #expect(showMore.maxParents == 30)

    let window = showMore.window(thread)
    // With a 30-parent window the whole chain fits, so no read-more-up row.
    #expect(window.first?.uri == "at://root")
    #expect(!window.contains { $0.isAnchor == false && $0.connector == nil && $0.uri == "" })
  }

  @Test("a short reply list is not truncated")
  func shortReplies() {
    let window = ThreadShowMore.initial().window(Self.threadWithReplies(5))
    #expect(window.count == 6)
    #expect(!window.contains { if case .showMore = $0.content { return true }; return false })
  }

  @Test("a long reply list is capped and gets a show-more row")
  func replyCap() {
    let thread = Self.threadWithReplies(150)
    let window = ThreadShowMore.initial().window(thread)

    // 100 replies + the anchor + the show-more row.
    #expect(window.count == 102)
    #expect(window.last?.content.isShowMore == true)

    // The last visible reply is the 100th; the rest are withheld.
    let visibleReplies = window.filter(\.isPost).filter { !$0.isAnchor }
    #expect(visibleReplies.count == 100)
    #expect(visibleReplies.last?.uri == "at://r99")
  }

  @Test("revealing more replies doubles the cap")
  func revealMoreReplies() {
    let thread = Self.threadWithReplies(150)
    var showMore = ThreadShowMore.initial()
    showMore = showMore.revealingMoreReplies()
    #expect(showMore.maxReplies == 200)

    let window = showMore.window(thread)
    // Everything now fits: 150 replies + anchor, no show-more row.
    #expect(window.count == 151)
    #expect(!window.contains { $0.content.isShowMore })
  }

  @Test("hasMoreParents reports whether the window is complete")
  func hasMoreParents() {
    let showMore = ThreadShowMore.initial()
    #expect(showMore.hasMoreParents(totalParents: 3) == false)
    #expect(showMore.hasMoreParents(totalParents: 19) == true)
  }

  @Test("a window holds an anchor with no parents")
  func noParents() {
    let thread = ThreadFlattener.flatten(
      Fixtures.withDepths(Fixtures.post("at://anchor")))
    let window = ThreadShowMore.initial().window(thread)
    #expect(window.count == 1)
    #expect(window[0].isAnchor)
  }

  @Test("the thread window tracks the parents it has revealed")
  func windowState() {
    let thread = Self.threadWithParents(19)
    var window = ThreadWindow(thread: thread)
    #expect(window.hasMoreParents)
    // read-more-up + 15 parents + anchor
    #expect(window.items.count == 17)

    window.revealMoreParents()
    #expect(!window.hasMoreParents)
    #expect(window.items.first?.uri == "at://root")
  }

  @Test("the thread window exposes reply expansion")
  func windowReplyExpansion() {
    var window = ThreadWindow(thread: Self.threadWithReplies(150))
    #expect(window.items.count == 102)

    window.revealMoreReplies()
    #expect(window.items.count == 151)
  }

  @Test("updating the thread keeps the window state")
  func updateKeepsWindow() {
    var window = ThreadWindow(thread: Self.threadWithParents(19))
    window.revealMoreParents()
    let before = window.showMore.maxParents

    window.update(thread: Self.threadWithParents(19))
    #expect(window.showMore.maxParents == before)
  }
}

extension ThreadItem.Content {
  var isShowMore: Bool {
    if case .showMore = self { return true }
    return false
  }
}
