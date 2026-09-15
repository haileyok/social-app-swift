import Foundation
import Lexicons
import SearchLogic
import SwiftAtproto

/// Sample data for the search surfaces: the CI screenshot fixture and previews.
///
/// Built through the real ``SearchLogic/ExploreAssembly`` rather than by hand,
/// so what the fixture renders is what the assembly actually produces — the
/// section order, the truncations and the load-more row are the logic layer's,
/// not a mock's. Every value is a plain, public AT-Protocol-shaped object; no
/// network is involved.
public enum SearchFixtures {
  /// An ISO-8601 timestamp the lexicon `FormatString<Date>` accepts.
  public static let defaultDate = "2026-09-14T12:00:00.000Z"

  // MARK: - Profiles

  /// A basic profile.
  public static func profile(
    handle: String,
    displayName: String? = nil,
    did: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<SwiftAtproto.DID>(rawValue: did ?? "did:plc:\(handle)"),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle),
      displayName: displayName ?? handle)
  }

  /// A full profile, with a bio.
  public static func profileView(
    handle: String,
    displayName: String? = nil,
    bio: String? = nil,
    did: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      description: bio,
      did: FormatString<SwiftAtproto.DID>(rawValue: did ?? "did:plc:\(handle)"),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle),
      displayName: displayName ?? handle,
      indexedAt: FormatString<Date>(rawValue: defaultDate))
  }

  /// A post view with plain text.
  ///
  /// The record is a real ``App/Bsky/FeedPost`` so the row's rich-text path
  /// runs for real rather than rendering an empty body.
  public static func post(
    _ text: String,
    handle: String = "alice.bsky.social",
    displayName: String? = "Alice",
    id: String = "1"
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: profile(handle: handle, displayName: displayName),
      cid: FormatString<LexLink>(rawValue: "cid-\(id)"),
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      likeCount: 12,
      record: .record(
        App.Bsky.FeedPost(
          createdAt: FormatString<Date>(rawValue: defaultDate), text: text)),
      replyCount: 3,
      repostCount: 1,
      uri: FormatString<ATURI>(
        rawValue: "at://did:plc:\(handle)/app.bsky.feed.post/\(id)"))
  }

  // MARK: - Feed generators

  /// A feed generator view.
  public static func feed(
    name: String,
    handle: String = "alice.bsky.social",
    description: String? = nil
  ) -> App.Bsky.FeedDefs_GeneratorView {
    App.Bsky.FeedDefs_GeneratorView(
      cid: FormatString<LexLink>(rawValue: "cid-\(name)"),
      creator: profileView(handle: handle),
      description: description,
      did: FormatString<SwiftAtproto.DID>(rawValue: "did:web:\(handle)"),
      displayName: name,
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      likeCount: 5,
      uri: FormatString<ATURI>(rawValue: "at://did:web:\(handle)/app.bsky.feed.generator/\(name)"))
  }

  // MARK: - Starter packs

  /// A starter pack view, carrying its name on the backing list as the API does.
  public static func starterPack(
    name: String,
    handle: String = "alice.bsky.social"
  ) -> App.Bsky.GraphDefs_StarterPackView {
    App.Bsky.GraphDefs_StarterPackView(
      cid: FormatString<LexLink>(rawValue: "cid-\(name)"),
      creator: profile(handle: handle),
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      list: App.Bsky.GraphDefs_ListViewBasic(
        cid: FormatString<LexLink>(rawValue: "cid-list"),
        name: name,
        purpose: .appBskyGraphDefsCuratelist,
        uri: FormatString<ATURI>(
          rawValue: "at://did:plc:\(handle)/app.bsky.graph.list/\(name)")),
      record: .any("app.bsky.graph.starterpack"),
      uri: FormatString<ATURI>(
        rawValue: "at://did:plc:\(handle)/app.bsky.graph.starterpack/\(name)"))
  }

  /// A trending topic.
  public static func trendingTopic(
    _ topic: String, displayName: String? = nil, description: String? = nil
  ) -> App.Bsky.UnspeccedDefs_TrendingTopic {
    App.Bsky.UnspeccedDefs_TrendingTopic(
      description: description,
      displayName: displayName ?? topic,
      link: "https://bsky.app/hashtag/\(topic)",
      topic: topic)
  }

  /// A trending video row.
  public static func trendVideo(_ displayName: String, postCount: Int = 42)
    -> App.Bsky.UnspeccedDefs_TrendView {
    App.Bsky.UnspeccedDefs_TrendView(
      actors: [profile(handle: "alice.bsky.social")],
      displayName: displayName,
      link: "https://bsky.app/trend/\(displayName)",
      postCount: postCount,
      startedAt: FormatString<Date>(rawValue: defaultDate),
      topic: displayName)
  }

  // MARK: - Assembled pages

  /// The Explore page the fixture renders: trending, suggested accounts,
  /// discover feeds, and starter packs, in the assembly's order.
  public static var explorePage: ExplorePageData {
    ExploreAssembly.build(
      ExploreAssembly.Input(
        trendingTopics: App.Bsky.UnspeccedGetTrendingTopics_Output(
          suggested: [], topics: [trendingTopic("SwiftUI"), trendingTopic("atproto")]),
        trendingVideos: [trendVideo("Live from the summit")],
        suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(
          actors: [
            profileView(
              handle: "alice.bsky.social", displayName: "Alice",
              bio: "Building the open social web."),
            profileView(
              handle: "bob.bsky.social", displayName: "Bob", bio: "Swift and bikes."),
            profileView(handle: "carol.bsky.social", displayName: "Carol"),
          ],
          recIdStr: "rec-explore-1"),
        suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output(feeds: [
          feed(name: "Discover", description: "Posts from across Bluesky."),
          feed(name: "Science", description: "Science feeds, curated."),
          feed(name: "Art", description: "Art and illustration."),
          feed(name: "News", description: "Headlines, unfiltered."),
          feed(name: "Cats", description: "Cats of the atmosphere."),
          feed(name: "Books", description: "What people are reading."),
          feed(name: "Music", description: "New releases and playlists."),
        ]),
        suggestedStarterPacks: App.Bsky.UnspeccedGetSuggestedStarterPacks_Output(
          starterPacks: [
            starterPack(name: "Bluesky Swift devs"),
            starterPack(name: "Climbing"),
          ]),
        feedPreviews: [],
        useFullExperience: true))
  }

  /// Suggested posts for the results fixture.
  public static var posts: [App.Bsky.FeedDefs_PostView] {
    [
      post("Hello from the new Swift client.", id: "1"),
      post("Search is a good place to start.", handle: "bob.bsky.social", displayName: "Bob",
        id: "2"),
      post("Testing the results tab.", handle: "carol.bsky.social", displayName: "Carol",
        id: "3"),
    ]
  }

  /// Suggested actors for the People tab.
  public static var actors: [App.Bsky.ActorDefs_ProfileView] {
    [
      profileView(handle: "alice.bsky.social", displayName: "Alice", bio: "Building things."),
      profileView(handle: "bob.bsky.social", displayName: "Bob", bio: "Swift and bikes."),
    ]
  }

  /// Suggested feeds for the Feeds tab.
  public static var feeds: [App.Bsky.FeedDefs_GeneratorView] {
    [feed(name: "Discover", description: "Posts from across Bluesky.")]
  }

  /// Recent searches for the suggestion fixture.
  public static var history: [SearchHistoryEntry] {
    [
      SearchHistoryEntry(q: "swiftui"),
      SearchHistoryEntry(q: "atproto"),
      SearchHistoryEntry(q: "bluesky"),
    ]
  }

  /// A committed results model for the results fixture.
  ///
  /// Exposed from this package so the app's hook can render a results surface
  /// without naming a `SearchLogic` type (and therefore without a second direct
  /// dependency in `App/Package.swift`).
  public static var resultsModel: SearchStateModel {
    SearchStateModel(
      state: .results(
        SearchResultsState(
          query: "swiftui", filters: SearchFilters(), tab: .top, fromMe: false)),
      query: "swiftui")
  }

  /// A resolved suggestion sub-state for the suggestions fixture.
  public static var suggestions: SearchSuggestionState {
    .loaded(
      query: "alice",
      items: [
        profile(handle: "alice.bsky.social", displayName: "Alice"),
        profile(handle: "alice.dev", displayName: "Alice Dev"),
      ])
  }
}
