import Lexicons
import StarterPacksLogic
import SwiftAtproto

/**
 Sample packs for previews, the app's debug surface, and the UI tests.

 These are the Views package's own fixtures rather than the Logic test suite's,
 because the Logic fixtures are `@testable`-internal to that package's tests and
 a Preview cannot reach them. They are built through the same lexicon types the
 appview returns, so a fixture flows through ``StarterPackViewBuilder`` exactly
 as a network response does - nothing here hand-builds a ``StarterPackDetail``
 that the builder could not have produced.
 */
public enum StarterPacksFixtures {
  /// The author every sample pack belongs to.
  public static let authorDID = "did:plc:starterpackauthor"
  /// The handle the sample creator shows.
  public static let authorHandle = "joshuajfriedman.com"
  /// The sample pack's rkey.
  public static let packRkey = "3l4poszxde32k"
  /// The sample pack's backing list rkey.
  public static let listRkey = "3l4posztwzy2e"

  /// An ISO-8601 timestamp the generated types accept.
  public static let date = "2026-08-31T00:00:00.000Z"

  // MARK: - Pack views

  /// A full sample pack view with the members, feeds and join counts filled in.
  ///
  /// - Parameters:
  ///   - name: the pack's name.
  ///   - description: the pack's description.
  ///   - memberCount: how many members the backing list reports.
  ///   - joinedAllTimeCount: the all-time join count, which the 25-threshold
  ///     gates the header's line on.
  ///   - feedCount: how many feeds to pin.
  ///   - creatorDID: the pack's author, so a fixture can be "owned" by the
  ///     viewer for the edit affordances.
  public static func packView(
    name: String = "Bluesky for Art History",
    description: String? = "A starter pack of art historians, museums and critics.",
    memberCount: Int = 12,
    joinedAllTimeCount: Int = 1_284,
    feedCount: Int = 1,
    creatorDID: String = authorDID,
    creatorHandle: String = authorHandle
  ) -> App.Bsky.GraphDefs_StarterPackView {
    let listURI = "at://\(creatorDID)/app.bsky.graph.list/\(listRkey)"
    let members = memberItems(count: min(memberCount, 12))
    let feeds = (0..<feedCount).map { index in
      generatorView(index: index, creatorDID: creatorDID)
    }
    return App.Bsky.GraphDefs_StarterPackView(
      cid: FormatString<LexLink>(rawValue: "bafyreiforfixtureonly"),
      creator: profileBasic(
        did: creatorDID, handle: creatorHandle, displayName: "Joshua Friedman"),
      feeds: feeds.isEmpty ? nil : feeds,
      indexedAt: FormatString<Date>(rawValue: date),
      joinedAllTimeCount: joinedAllTimeCount,
      joinedWeekCount: 96,
      list: App.Bsky.GraphDefs_ListViewBasic(
        cid: FormatString<LexLink>(rawValue: "listcid"),
        listItemCount: memberCount,
        name: name,
        purpose: .appBskyGraphDefsReferencelist,
        uri: FormatString<ATURI>(rawValue: listURI)),
      listItemsSample: members,
      record: .record(
        App.Bsky.GraphStarterpack(
          createdAt: FormatString<Date>(rawValue: date),
          description: description,
          feeds: feeds.map { App.Bsky.GraphStarterpack_FeedItem(uri: $0.uri) },
          list: FormatString<ATURI>(rawValue: listURI),
          name: name)),
      uri: FormatString<ATURI>(
        rawValue: "at://\(creatorDID)/app.bsky.graph.starterpack/\(packRkey)"))
  }

  /// The detail a sample pack resolves to.
  public static func detail(
    name: String = "Bluesky for Art History",
    memberCount: Int = 12,
    isOwn: Bool = false,
    feedCount: Int = 1
  ) -> StarterPackDetail {
    let creator = isOwn ? "did:plc:viewer" : authorDID
    return StarterPackViewBuilder.detail(
      packView(
        name: name, memberCount: memberCount, feedCount: feedCount, creatorDID: creator),
      viewerDID: isOwn ? creator : "did:plc:viewer")
  }

  // MARK: - Members and feeds

  /// A member list-item for a synthetic account.
  public static func memberItem(
    index: Int, optedOut: Bool = false
  ) -> App.Bsky.GraphDefs_ListItemView {
    let did = "did:plc:member\(index)"
    return App.Bsky.GraphDefs_ListItemView(
      subject: profile(
        did: did,
        handle: "member\(index).test",
        displayName: ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson"][
          index % 4]),
      subjectOptedOut: optedOut ? true : nil,
      uri: FormatString<ATURI>(
        rawValue: "at://\(authorDID)/app.bsky.graph.listitem/item\(index)"))
  }

  /// A run of member items.
  public static func memberItems(count: Int) -> [App.Bsky.GraphDefs_ListItemView] {
    (0..<count).map { memberItem(index: $0) }
  }

  /// A pinned feed generator.
  public static func generatorView(
    index: Int, creatorDID: String = authorDID
  ) -> App.Bsky.FeedDefs_GeneratorView {
    let did = "did:plc:feed\(index)"
    return App.Bsky.FeedDefs_GeneratorView(
      cid: FormatString<LexLink>(rawValue: "gencid\(index)"),
      creator: profile(did: did, handle: "curator\(index).test", displayName: "Curator \(index)"),
      did: FormatString<DID>(rawValue: did),
      displayName: ["Art History Daily", "Museum Watch", "Studio Visits"][index % 3],
      indexedAt: FormatString<Date>(rawValue: date),
      uri: FormatString<ATURI>(rawValue: "at://\(did)/app.bsky.feed.generator/feed\(index)"))
  }

  /// Feed search results for the wizard's feeds step.
  public static func feedResults(count: Int = 3) -> [StarterPackFeedResult] {
    (0..<count).map { index in
      let generator = generatorView(index: index)
      return StarterPackFeedResult(
        uri: generator.uri.rawValue,
        displayName: generator.displayName,
        creatorHandle: generator.creator.handle.rawValue)
    }
  }

  /// Profile search results for the wizard's people step.
  public static func profileResults(count: Int = 12) -> [StarterPackProfileResult] {
    (0..<count).map { index in
      let item = memberItem(index: index)
      return StarterPackProfileResult(
        did: item.subject.did.rawValue,
        handle: item.subject.handle.rawValue,
        displayName: item.subject.displayName)
    }
  }

  // MARK: - Wizard

  /// A fresh wizard, seeded with a target profile and a default name.
  ///
  /// The name comes from ``StarterPackStrings/defaultPackName(displayName:handle:)``,
  /// which is the template RN seeds the details step with.
  public static func wizard(memberCount: Int = 9, feedCount: Int = 1) -> StarterPackWizard {
    let target = WizardProfile(
      did: "did:plc:target", handle: "target.test", displayName: "Ada Lovelace")
    var wizard = StarterPackWizard(targetProfile: target)
    wizard.setName(
      StarterPackStrings.defaultPackName(displayName: target.displayName, handle: target.handle))
    wizard.setDescription("A starter pack of art historians, museums and critics.")
    for index in 0..<max(0, memberCount - 1) {
      wizard.addProfile(
        WizardProfile(
          did: "did:plc:member\(index)", handle: "member\(index).test",
          displayName: "Member \(index)"))
    }
    for index in 0..<feedCount {
      let feed = generatorView(index: index)
      wizard.addFeed(WizardFeed(uri: feed.uri.rawValue, displayName: feed.displayName))
    }
    wizard.clearRefusals()
    return wizard
  }

  // MARK: - Landing and share

  /// The landing state for a sample pack.
  public static func landingState(
    name: String = "Bluesky for Art History"
  ) -> StarterPackLandingState {
    let view = packView(name: name)
    return StarterPackViewBuilder.landingState(view)
      ?? StarterPackLandingState(
        detail: StarterPackViewBuilder.detail(view),
        sample: [],
        followCopy: .allOfThem)
  }

  /// Share data with the short link already resolved, so a preview renders the
  /// ready state rather than the spinner.
  public static func shareData(
    detail: StarterPackDetail, shortLink: String? = "https://go.bsky.app/ArtHistory"
  ) -> StarterPackShareData {
    StarterPackShare.shareData(detail, shortLink: shortLink)
  }

  // MARK: - Private builders

  private static func profileBasic(
    did: String, handle: String, displayName: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<DID>(rawValue: did),
      displayName: displayName,
      handle: FormatString<Handle>(rawValue: handle))
  }

  private static func profile(
    did: String, handle: String, displayName: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      did: FormatString<DID>(rawValue: did),
      displayName: displayName,
      handle: FormatString<Handle>(rawValue: handle))
  }
}
