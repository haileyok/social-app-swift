import Foundation
import Lexicons
import SwiftAtproto

/// The presentation-ready shape of a starter pack view.
///
/// Ports the derivation `screens/StarterPack/StarterPackScreen.tsx` performs on
/// a `getStarterPack` result: which tabs exist, whether the viewer owns the pack,
/// whether the pack is valid, and the header stats the screen renders.
///
/// This is a Logic type, so it holds counts and booleans, not views. A Views
/// layer reads these to decide what to render.
public struct StarterPackDetail: Sendable {
  /// The pack's AT URI.
  public let uri: String
  /// The pack's CID.
  public let cid: String
  /// The pack record's name.
  public let name: String
  /// The pack record's description, when set.
  public let description: String?
  /// The description facets, when set.
  public let descriptionFacets: [App.Bsky.RichtextFacet]?
  /// The record's creation timestamp.
  public let createdAt: String
  /// The creator's DID.
  public let creatorDID: String
  /// The creator's handle.
  public let creatorHandle: String
  /// The creator's display name, when set.
  public let creatorDisplayName: String?
  /// The backing list's URI, when the pack has one.
  public let listURI: String?
  /// The backing list's viewer state, when present.
  public let listViewer: App.Bsky.GraphDefs_ListViewerState?
  /// The number of members in the backing list. RN: `list.listItemCount`.
  public let listItemCount: Int
  /// The member sample the appview attached, up to twelve.
  public let listItemsSample: [App.Bsky.GraphDefs_ListItemView]
  /// The feed generators the pack pins, in pack order.
  public let feeds: [App.Bsky.FeedDefs_GeneratorView]
  /// The estimated number of accounts that joined through this pack this week.
  public let joinedWeekCount: Int
  /// The number of accounts that have joined through this pack.
  public let joinedAllTimeCount: Int
  /// Whether the viewer is the pack's creator.
  public let isOwn: Bool
  /// Whether packaging the record requires the `UnknownATPValue` shape's
  /// `app.bsky.graph.starterpack` variant.
  public let hasList: Bool

  /// Creates a detail.
  public init(
    uri: String,
    cid: String,
    name: String,
    description: String?,
    descriptionFacets: [App.Bsky.RichtextFacet]?,
    createdAt: String,
    creatorDID: String,
    creatorHandle: String,
    creatorDisplayName: String?,
    listURI: String?,
    listViewer: App.Bsky.GraphDefs_ListViewerState?,
    listItemCount: Int,
    listItemsSample: [App.Bsky.GraphDefs_ListItemView],
    feeds: [App.Bsky.FeedDefs_GeneratorView],
    joinedWeekCount: Int,
    joinedAllTimeCount: Int,
    isOwn: Bool
  ) {
    self.uri = uri
    self.cid = cid
    self.name = name
    self.description = description
    self.descriptionFacets = descriptionFacets
    self.createdAt = createdAt
    self.creatorDID = creatorDID
    self.creatorHandle = creatorHandle
    self.creatorDisplayName = creatorDisplayName
    self.listURI = listURI
    self.listViewer = listViewer
    self.listItemCount = listItemCount
    self.listItemsSample = listItemsSample
    self.feeds = feeds
    self.joinedWeekCount = joinedWeekCount
    self.joinedAllTimeCount = joinedAllTimeCount
    self.isOwn = isOwn
    self.hasList = listURI != nil
  }

  /// The record key this pack lives under.
  public var rkey: String { StarterPackURI.parse(uri)?.rkey ?? "" }
}

/// The tab set the pack screen derives from a view.
public enum StarterPackTabs {
  /// The people tab is shown whenever the pack has a backing list.
  public static func showsPeople(_ detail: StarterPackDetail) -> Bool { detail.hasList }
  /// The feeds tab is shown whenever the pack pins at least one feed.
  public static func showsFeeds(_ detail: StarterPackDetail) -> Bool { !detail.feeds.isEmpty }
  /// The posts tab is shown whenever the pack has a backing list.
  public static func showsPosts(_ detail: StarterPackDetail) -> Bool { detail.hasList }
}

/// Assembles ``StarterPackDetail`` values from wire views.
///
/// Ports the derivation in `StarterPackScreen` (validity, ownership, tab set,
/// header stats) and `StarterPackLandingScreen` (the sample and the stat line).
public enum StarterPackViewBuilder {
  /// Builds a detail from a full pack view.
  ///
  /// - Parameters:
  ///   - view: the `#starterPackView` the appview returned.
  ///   - viewerDID: the signed-in account's DID, for the ownership flag.
  public static func detail(
    _ view: App.Bsky.GraphDefs_StarterPackView, viewerDID: String? = nil
  ) -> StarterPackDetail {
    let record = view.record.starterPackRecord
    return StarterPackDetail(
      uri: view.uri.rawValue,
      cid: view.cid.rawValue,
      name: record?.name ?? view.list?.name ?? "",
      description: record?.description,
      descriptionFacets: record?.descriptionFacets,
      createdAt: record?.createdAt.rawValue ?? view.indexedAt.rawValue,
      creatorDID: view.creator.did.rawValue,
      creatorHandle: view.creator.handle.rawValue,
      creatorDisplayName: view.creator.displayName,
      listURI: view.list?.uri.rawValue,
      listViewer: view.list?.viewer,
      listItemCount: view.list?.listItemCount ?? view.listItemsSample?.count ?? 0,
      listItemsSample: view.listItemsSample ?? [],
      feeds: view.feeds ?? [],
      joinedWeekCount: view.joinedWeekCount ?? 0,
      joinedAllTimeCount: view.joinedAllTimeCount ?? 0,
      isOwn: viewerDID != nil && view.creator.did.rawValue == viewerDID)
  }

  /// Whether a fetched view is usable by the screen.
  ///
  /// Port of the `isValid` expression in `StarterPackScreenInner`: the view must
  /// be a trusted full view carrying a starter-pack record, and must either have
  /// a backing list or belong to the viewer (so an owner can still manage a pack
  /// whose list is missing).
  public static func isValid(
    _ view: App.Bsky.GraphDefs_StarterPackView, viewerDID: String? = nil
  ) -> Bool {
    guard view.record.starterPackRecord != nil else { return false }
    if view.list != nil { return true }
    return viewerDID != nil && view.creator.did.rawValue == viewerDID
  }

  /// Whether the pack is invalid in the specific way the screen calls out: the
  /// viewer owns it but its backing list is gone.
  ///
  /// Port of the `if (!starterPack.list && starterPack.creator.did ===
  /// currentAccount?.did)` branch.
  public static func isDeletedListOwned(
    _ view: App.Bsky.GraphDefs_StarterPackView, viewerDID: String?
  ) -> Bool {
    view.list == nil && viewerDID != nil && view.creator.did.rawValue == viewerDID
  }

  /// The header's "people have joined" line, or nil when it is hidden.
  ///
  /// Port of the `joinedAllTimeCount >= 25` gate. RN renders the line only above
  /// the threshold.
  public static func joinedLine(_ detail: StarterPackDetail) -> String? {
    guard detail.joinedAllTimeCount >= StarterPackConstants.joinedCountDisplayThreshold else {
      return nil
    }
    return "\(detail.joinedAllTimeCount)"
  }

  /// The posts-tab URI, which is the backing list when there is one.
  public static func postsListURI(_ detail: StarterPackDetail) -> String? { detail.listURI }

  /// The landing screen's "you'll follow these people" sample.
  ///
  /// Port of `starterPack.listItemsSample?.filter(p =>
  /// !p.subject.associated?.labeler).slice(0, 8)`: labeler accounts are dropped
  /// and the list is capped at eight.
  public static func landingSample(_ detail: StarterPackDetail) -> [App.Bsky.GraphDefs_ListItemView] {
    detail.listItemsSample
      .filter { $0.subject.associated?.labeler == nil }
      .prefix(StarterPackConstants.landingSampleThreshold)
      .map { $0 }
  }

  /// The landing screen's follow-count copy key.
  ///
  /// Port of the `listItemsCount <= 8` branch: at or below the threshold the
  /// screen reads "You'll follow these people right away", above it the screen
  /// names the remainder.
  public static func landingFollowCopy(_ detail: StarterPackDetail) -> LandingFollowCopy {
    if detail.listItemCount <= StarterPackConstants.landingSampleThreshold {
      return .allOfThem
    }
    return .someRemainder(count: detail.listItemCount - StarterPackConstants.landingSampleThreshold)
  }
}

/// Which follow-count sentence the landing screen shows.
public enum LandingFollowCopy: Sendable, Equatable {
  /// "You'll follow these people right away".
  case allOfThem
  /// "You'll follow these people and N others".
  case someRemainder(count: Int)
}

extension UnknownATPValue {
  /// The `app.bsky.graph.starterpack` record, when this value is one.
  public var starterPackRecord: App.Bsky.GraphStarterpack? {
    guard case .record(let record) = self else { return nil }
    return record as? App.Bsky.GraphStarterpack
  }
}

extension App.Bsky.GraphDefs_StarterPackViewBasic {
  /// The `app.bsky.graph.starterpack` record, when this value carries one.
  public var starterPackRecord: App.Bsky.GraphStarterpack? {
    record.starterPackRecord
  }
}
