import Foundation
import Lexicons
import SwiftAtproto

@testable import StarterPacksLogic

/// Fixture builders for the starter-pack suites.
enum Fixtures {
  /// An ISO-8601 timestamp the lexicon `FormatString<Date>` accepts.
  static let defaultDate = "2026-08-31T00:00:00.000Z"

  /// The author every fixture pack belongs to.
  static let authorDID = "did:plc:author"
  /// Another account, used as a member.
  static let memberDID = "did:plc:member"
  /// A third account.
  static let otherDID = "did:plc:other"
  /// The backing list's rkey.
  static let listRkey = "3l4posztwzy2e"
  /// The pack's rkey.
  static let packRkey = "3l4poszxde32k"

  /// The backing list URI for a pack owned by `did`.
  static func listURI(did: String = authorDID, rkey: String = listRkey) -> String {
    "at://\(did)/app.bsky.graph.list/\(rkey)"
  }

  /// The pack URI for a record owned by `did`.
  static func packURI(did: String = authorDID, rkey: String = packRkey) -> String {
    "at://\(did)/app.bsky.graph.starterpack/\(rkey)"
  }

  // MARK: - Profiles and generators

  /// A profile view basic.
  static func profileBasic(
    did: String, handle: String = "alice.test", displayName: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<SwiftAtproto.DID>(rawValue: did),
      displayName: displayName,
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle))
  }

  /// A full profile view, with a viewer state.
  static func profile(
    did: String,
    handle: String = "alice.test",
    displayName: String? = nil,
    viewer: App.Bsky.ActorDefs_ViewerState? = nil,
    labeler: Bool = false
  ) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      associated: labeler ? App.Bsky.ActorDefs_ProfileAssociated(labeler: true) : nil,
      did: FormatString<SwiftAtproto.DID>(rawValue: did),
      displayName: displayName,
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle),
      viewer: viewer)
  }

  /// A wizard member from a DID.
  static func wizardProfile(
    _ did: String, handle: String? = nil, displayName: String? = nil
  ) -> WizardProfile {
    WizardProfile(
      did: did, handle: handle ?? did.replacingOccurrences(of: "did:plc:", with: "") + ".test",
      displayName: displayName)
  }

  /// A wizard feed from a URI.
  static func wizardFeed(
    _ rkey: String, displayName: String? = nil, did: String = "did:plc:feeds"
  ) -> WizardFeed {
    WizardFeed(
      uri: "at://\(did)/app.bsky.feed.generator/\(rkey)",
      displayName: displayName ?? rkey)
  }

  /// A feed generator view.
  static func generatorView(
    _ rkey: String,
    displayName: String = "Cool Feed",
    did: String = "did:plc:feeds"
  ) -> App.Bsky.FeedDefs_GeneratorView {
    App.Bsky.FeedDefs_GeneratorView(
      cid: FormatString<LexLink>(rawValue: "gencid"),
      creator: profile(did: did, handle: "feedmaker.test"),
      did: FormatString<SwiftAtproto.DID>(rawValue: did),
      displayName: displayName,
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      uri: FormatString<ATURI>(rawValue: "at://\(did)/app.bsky.feed.generator/\(rkey)"))
  }

  /// A list-item view for a member.
  static func listItem(
    _ did: String,
    handle: String = "member.test",
    displayName: String? = nil,
    rkey: String = "item1",
    subjectOptedOut: Bool? = nil,
    viewer: App.Bsky.ActorDefs_ViewerState? = nil,
    labeler: Bool = false
  ) -> App.Bsky.GraphDefs_ListItemView {
    App.Bsky.GraphDefs_ListItemView(
      subject: profile(
        did: did, handle: handle, displayName: displayName, viewer: viewer, labeler: labeler),
      subjectOptedOut: subjectOptedOut,
      uri: FormatString<ATURI>(
        rawValue: "at://\(authorDID)/app.bsky.graph.listitem/\(rkey)"))
  }

  /// A profile view with a following relationship set.
  static func following(_ did: String) -> App.Bsky.ActorDefs_ViewerState {
    App.Bsky.ActorDefs_ViewerState(
      following: FormatString<ATURI>(rawValue: "at://did:plc:author/app.bsky.graph.follow/1"))
  }

  /// A blocked profile view's state.
  static func blocked() -> App.Bsky.ActorDefs_ViewerState {
    App.Bsky.ActorDefs_ViewerState(blockedBy: true)
  }

  /// A muted profile view's state.
  static func muted() -> App.Bsky.ActorDefs_ViewerState {
    App.Bsky.ActorDefs_ViewerState(muted: true)
  }

  // MARK: - Pack views and records

  /// A `app.bsky.graph.starterpack` record.
  static func packRecord(
    name: String = "Bluesky for Art History",
    description: String? = nil,
    listURI: String? = nil,
    feeds: [String]? = nil,
    createdAt: String = defaultDate
  ) -> App.Bsky.GraphStarterpack {
    App.Bsky.GraphStarterpack(
      createdAt: FormatString<Date>(rawValue: createdAt),
      description: description,
      feeds: feeds?.map { App.Bsky.GraphStarterpack_FeedItem(uri: FormatString<ATURI>(rawValue: $0)) },
      list: FormatString<ATURI>(rawValue: listURI ?? Fixtures.listURI()),
      name: name)
  }

  /// A full `#starterPackView`.
  static func packView(
    name: String = "Bluesky for Art History",
    description: String? = nil,
    creatorDID: String = authorDID,
    creatorHandle: String = "joshuajfriedman.com",
    listURI: String? = nil,
    listItemCount: Int? = nil,
    listItemsSample: [App.Bsky.GraphDefs_ListItemView]? = nil,
    listViewer: App.Bsky.GraphDefs_ListViewerState? = nil,
    feeds: [App.Bsky.FeedDefs_GeneratorView]? = nil,
    joinedWeekCount: Int? = nil,
    joinedAllTimeCount: Int? = nil,
    rkey: String = packRkey,
    omitList: Bool = false
  ) -> App.Bsky.GraphDefs_StarterPackView {
    let resolvedListURI = listURI ?? Fixtures.listURI(did: creatorDID)
    return App.Bsky.GraphDefs_StarterPackView(
      cid: FormatString<LexLink>(rawValue: "bafyreiaxduxpwdpjgvve3klfs4flkwjwfqiurszw4o6jvjarpqqmeqwiza"),
      creator: profileBasic(did: creatorDID, handle: creatorHandle),
      feeds: feeds,
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      joinedAllTimeCount: joinedAllTimeCount,
      joinedWeekCount: joinedWeekCount,
      list: omitList
        ? nil
        : App.Bsky.GraphDefs_ListViewBasic(
          cid: FormatString<LexLink>(rawValue: "listcid"),
          listItemCount: listItemCount,
          name: name,
          purpose: .appBskyGraphDefsReferencelist,
          uri: FormatString<ATURI>(rawValue: resolvedListURI),
          viewer: listViewer),
      listItemsSample: listItemsSample,
      record: .record(
        packRecord(
          name: name, description: description, listURI: resolvedListURI,
          feeds: feeds?.map(\.uri.rawValue))),
      uri: FormatString<ATURI>(rawValue: Fixtures.packURI(did: creatorDID, rkey: rkey)))
  }

  /// A basic `#starterPackViewBasic`.
  static func packViewBasic(
    name: String = "Bluesky for Art History",
    creatorDID: String = authorDID,
    rkey: String = packRkey
  ) -> App.Bsky.GraphDefs_StarterPackViewBasic {
    App.Bsky.GraphDefs_StarterPackViewBasic(
      cid: FormatString<LexLink>(rawValue: "bafyreiaxduxpwdpjgvve3klfs4flkwjwfqiurszw4o6jvjarpqqmeqwiza"),
      creator: profileBasic(did: creatorDID),
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      record: .record(packRecord(name: name)),
      uri: FormatString<ATURI>(rawValue: Fixtures.packURI(did: creatorDID, rkey: rkey)))
  }

  /// A `WithMembership` row.
  static func membershipRow(
    packURI: String = Fixtures.packURI(),
    name: String = "Bluesky for Art History",
    member: Bool
  ) -> App.Bsky.GraphGetStarterPacksWithMembership_StarterPackWithMembership {
    App.Bsky.GraphGetStarterPacksWithMembership_StarterPackWithMembership(
      listItem: member
        ? App.Bsky.GraphDefs_ListItemView(
          subject: profile(did: authorDID),
          uri: FormatString<ATURI>(rawValue: "at://\(authorDID)/app.bsky.graph.listitem/m1"))
        : nil,
      starterPack: packView(name: name, rkey: StarterPackURI.parse(packURI)?.rkey ?? packRkey))
  }

  // MARK: - JSON

  /// A JSON object fixture.
  static func json(_ members: [String: StarterPackJSON]) -> StarterPackJSON {
    .object(members)
  }

  /// Encodes a JSON value to a sorted-key string, for exact payload comparison.
  static func canonical(_ value: StarterPackJSON) -> String {
    let encoder = JSONEncoder()
    // `withoutEscapingSlashes` matches the JS `JSON.stringify` output the
    // expectations are written from; without it every `at://` URI reads as
    // `at:\/\/` and no table compares equal.
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8)
    else { return "<unencodable>" }
    return text
  }
}
