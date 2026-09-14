import Foundation
import Lexicons
import Testing

@testable import StarterPacksLogic

/// Asserts the pack-view derivation: tabs, validity, ownership and header stats.
///
/// Ports the derivations in `StarterPackScreen` and `StarterPackLandingScreen`.
@Suite("StarterPackDetail")
struct StarterPackDetailTests {
  @Test("a detail carries the record's name, description and creator")
  func detailFields() {
    let view = Fixtures.packView(name: "Bluesky for Art History", description: "Art history!")
    let detail = StarterPackViewBuilder.detail(view)

    #expect(detail.name == "Bluesky for Art History")
    #expect(detail.description == "Art history!")
    #expect(detail.creatorDID == Fixtures.authorDID)
    #expect(detail.creatorHandle == "joshuajfriedman.com")
    #expect(detail.listURI == Fixtures.listURI())
    #expect(detail.rkey == Fixtures.packRkey)
    #expect(detail.createdAt == Fixtures.defaultDate)
  }

  @Test("the item count comes from the list view, falling back to the sample")
  func itemCount() {
    let counted = StarterPackViewBuilder.detail(
      Fixtures.packView(listItemCount: 42, listItemsSample: [Fixtures.listItem(Fixtures.memberDID)]))
    #expect(counted.listItemCount == 42)

    let sampled = StarterPackViewBuilder.detail(
      Fixtures.packView(listItemsSample: [
        Fixtures.listItem(Fixtures.memberDID, rkey: "a"),
        Fixtures.listItem(Fixtures.otherDID, rkey: "b"),
      ]))
    #expect(sampled.listItemCount == 2)
  }

  @Test("the feed list is preserved in pack order")
  func feeds() {
    let view = Fixtures.packView(feeds: [
      Fixtures.generatorView("a", displayName: "A"),
      Fixtures.generatorView("b", displayName: "B"),
    ])
    #expect(StarterPackViewBuilder.detail(view).feeds.map(\.displayName) == ["A", "B"])
  }

  @Test("ownership is set only for the creator")
  func ownership() {
    let view = Fixtures.packView()
    #expect(StarterPackViewBuilder.detail(view, viewerDID: Fixtures.authorDID).isOwn)
    #expect(StarterPackViewBuilder.detail(view, viewerDID: Fixtures.otherDID).isOwn == false)
    #expect(StarterPackViewBuilder.detail(view).isOwn == false)
  }

  // MARK: - Validity

  @Test("a pack with a list and a record is valid")
  func validWithList() {
    #expect(StarterPackViewBuilder.isValid(Fixtures.packView()))
  }

  @Test("a pack with no list is valid only for its owner")
  func validWithoutListForOwner() {
    let view = Fixtures.packView(omitList: true)
    #expect(StarterPackViewBuilder.isValid(view, viewerDID: Fixtures.authorDID))
    #expect(StarterPackViewBuilder.isValid(view, viewerDID: Fixtures.otherDID) == false)
    #expect(StarterPackViewBuilder.isValid(view) == false)
  }

  @Test("the missing-list-owned case is called out separately")
  func deletedListOwned() {
    let view = Fixtures.packView(omitList: true)
    #expect(StarterPackViewBuilder.isDeletedListOwned(view, viewerDID: Fixtures.authorDID))
    #expect(StarterPackViewBuilder.isDeletedListOwned(view, viewerDID: Fixtures.otherDID) == false)
    #expect(StarterPackViewBuilder.isDeletedListOwned(Fixtures.packView(), viewerDID: Fixtures.authorDID) == false)
  }

  @Test("the landing screen requires a list even for the owner")
  func landingValidity() {
    #expect(StarterPackViewBuilder.landingIsValid(Fixtures.packView()))
    // Unlike the signed-in screen, a listless pack owned by the viewer is not
    // landing-valid.
    #expect(StarterPackViewBuilder.landingIsValid(Fixtures.packView(omitList: true)) == false)
  }

  // MARK: - Tabs

  @Test("the people and posts tabs follow the list, the feeds tab the feeds")
  func tabs() {
    let full = StarterPackViewBuilder.detail(
      Fixtures.packView(listItemCount: 3, feeds: [Fixtures.generatorView("a")]))
    #expect(StarterPackTabs.showsPeople(full))
    #expect(StarterPackTabs.showsFeeds(full))
    #expect(StarterPackTabs.showsPosts(full))

    let listOnly = StarterPackViewBuilder.detail(Fixtures.packView(listItemCount: 3))
    #expect(StarterPackTabs.showsPeople(listOnly))
    #expect(StarterPackTabs.showsFeeds(listOnly) == false)
    #expect(StarterPackTabs.showsPosts(listOnly))

    let listless = StarterPackViewBuilder.detail(
      Fixtures.packView(feeds: [Fixtures.generatorView("a")], omitList: true))
    #expect(StarterPackTabs.showsPeople(listless) == false)
    #expect(StarterPackTabs.showsPosts(listless) == false)
    #expect(StarterPackTabs.showsFeeds(listless))
  }

  @Test("the posts tab reads the backing list")
  func postsURI() {
    let detail = StarterPackViewBuilder.detail(Fixtures.packView())
    #expect(StarterPackViewBuilder.postsListURI(detail) == Fixtures.listURI())
  }

  // MARK: - Header stats

  @Test("the joined line is hidden below 25 and shown at 25")
  func joinedLineThreshold() {
    let below = StarterPackViewBuilder.detail(Fixtures.packView(joinedAllTimeCount: 24))
    #expect(StarterPackViewBuilder.joinedLine(below) == nil)

    let at = StarterPackViewBuilder.detail(Fixtures.packView(joinedAllTimeCount: 25))
    #expect(StarterPackViewBuilder.joinedLine(at) == "25")

    let none = StarterPackViewBuilder.detail(Fixtures.packView())
    #expect(StarterPackViewBuilder.joinedLine(none) == nil)
  }

  // MARK: - Landing derivation

  @Test("the landing sample drops labeler accounts and caps at eight")
  func landingSample() {
    var items = (0..<10).map { Fixtures.listItem("did:plc:m\($0)", rkey: "r\($0)") }
    items.append(Fixtures.listItem("did:plc:labeler", rkey: "l", labeler: true))
    let detail = StarterPackViewBuilder.detail(
      Fixtures.packView(listItemCount: 11, listItemsSample: items))

    let sample = StarterPackViewBuilder.landingSample(detail)
    #expect(sample.count == 8)
    #expect(sample.contains { $0.subject.did.rawValue == "did:plc:labeler" } == false)
  }

  @Test("the follow copy names a remainder only above the threshold")
  func followCopy() {
    let atThreshold = StarterPackViewBuilder.detail(Fixtures.packView(listItemCount: 8))
    #expect(StarterPackViewBuilder.landingFollowCopy(atThreshold) == .allOfThem)

    let below = StarterPackViewBuilder.detail(Fixtures.packView(listItemCount: 3))
    #expect(StarterPackViewBuilder.landingFollowCopy(below) == .allOfThem)

    let above = StarterPackViewBuilder.detail(Fixtures.packView(listItemCount: 20))
    #expect(StarterPackViewBuilder.landingFollowCopy(above) == .someRemainder(count: 12))
  }

  @Test("the landing state is built only for a valid view")
  func landingState() {
    #expect(StarterPackViewBuilder.landingState(Fixtures.packView(omitList: true)) == nil)

    let state = StarterPackViewBuilder.landingState(
      Fixtures.packView(name: "Pack", description: "Desc", listItemCount: 3))
    #expect(state?.name == "Pack")
    #expect(state?.description == "Desc")
    #expect(state?.creatorHandle == "joshuajfriedman.com")
  }

  @Test("a pack's record is recoverable from a view and a basic view")
  func recordRecovery() {
    let full = Fixtures.packView(name: "From Record")
    #expect(full.record.starterPackRecord?.name == "From Record")
    #expect(Fixtures.packViewBasic(name: "Basic").starterPackRecord?.name == "Basic")
  }

  @Test("a basic view's rkey is the record's rkey, stable across forms")
  func basicViewRkey() {
    let basic = Fixtures.packViewBasic(rkey: "abc123")
    #expect(basic.uri.rawValue.hasSuffix("/abc123"))
  }
}
