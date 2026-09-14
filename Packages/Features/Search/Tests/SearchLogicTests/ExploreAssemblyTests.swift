import Lexicons
import Testing

@testable import SearchLogic

/// Explore assembly from fixture responses.
@Suite("ExploreAssembly")
struct ExploreAssemblyTests {
  private func trendingOutput(
    topics: [App.Bsky.UnspeccedDefs_TrendingTopic]
  ) -> App.Bsky.UnspeccedGetTrendingTopics_Output {
    App.Bsky.UnspeccedGetTrendingTopics_Output(suggested: [], topics: topics)
  }

  @Test("full experience renders every section in order")
  func sectionOrder() {
    let input = ExploreAssembly.Input(
      trendingTopics: trendingOutput(topics: [
        ProfileFixtures.trendingTopic(link: "/t/1", topic: "art", displayName: "Art")
      ]),
      suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(
        actors: [ProfileFixtures.profile(did: "did:plc:a", handle: "alice.test")]),
      suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output(
        feeds: [ProfileFixtures.generatorView(uri: "at://f/1", did: "did:plc:f", name: "Feed")]),
      suggestedStarterPacks: App.Bsky.UnspeccedGetSuggestedStarterPacks_Output(
        starterPacks: [ProfileFixtures.starterPack(uri: "at://sp/1")]),
      feedPreviews: [.trendingTopic(ProfileFixtures.trendingTopic(
        link: "/t/2", topic: "news", displayName: "News"))],
      useFullExperience: true
    )
    let page = ExploreAssembly.build(input)
    #expect(
      page.sections.map(\.title)
        == [.trending, .suggestedFeeds, .suggestedAccounts, .starterPacks, .feedPreviews])
  }

  @Test("without the full experience only suggested accounts remain")
  func reducedExperience() {
    let input = ExploreAssembly.Input(
      trendingTopics: trendingOutput(topics: [
        ProfileFixtures.trendingTopic(link: "/t/1", topic: "art", displayName: "Art")
      ]),
      suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(
        actors: [ProfileFixtures.profile(did: "did:plc:a", handle: "alice.test")]),
      suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output(
        feeds: [ProfileFixtures.generatorView(uri: "at://f/1", did: "did:plc:f", name: "Feed")]),
      suggestedStarterPacks: App.Bsky.UnspeccedGetSuggestedStarterPacks_Output(
        starterPacks: [ProfileFixtures.starterPack(uri: "at://sp/1")]),
      useFullExperience: false
    )
    let page = ExploreAssembly.build(input)
    #expect(page.sections.map(\.title) == [.suggestedAccounts])
  }

  @Test("a missing trending response hides the section")
  func noTrendingHidesSection() {
    let input = ExploreAssembly.Input(useFullExperience: true)
    #expect(ExploreAssembly.buildTrending(input) == nil)
  }

  @Test("trending topics and videos both appear under the trending section")
  func trendingTopicsAndVideos() {
    let input = ExploreAssembly.Input(
      trendingTopics: trendingOutput(topics: [
        ProfileFixtures.trendingTopic(link: "/t/1", topic: "art", displayName: "Art")
      ]),
      trendingVideos: [ProfileFixtures.trend(link: "/v/1", topic: "v", displayName: "Video")]
    )
    let section = ExploreAssembly.buildTrending(input)
    #expect(section?.items.count == 2)
  }

  @Test("suggested accounts dedupe by DID and drop followed accounts")
  func suggestedAccountsDedupe() {
    let input = ExploreAssembly.Input(
      suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(
        actors: [
          ProfileFixtures.profile(did: "did:plc:a", handle: "alice.test"),
          ProfileFixtures.profile(did: "did:plc:a", handle: "alice.test"),
          ProfileFixtures.profile(
            did: "did:plc:b", handle: "bob.test", following: "at://follow/b"),
        ],
        recIdStr: "rec-1")
    )
    let section = ExploreAssembly.buildSuggestedAccounts(input)
    #expect(section?.items.count == 1)
    #expect(input.suggestedUsers?.recIdStr == "rec-1")
  }

  @Test("the default For You tab truncates suggested accounts to 5")
  func forYouTruncates() {
    let actors = (0..<8).map { index in
      ProfileFixtures.profile(did: "did:plc:\(index)", handle: "user\(index).test")
    }
    let input = ExploreAssembly.Input(
      suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(actors: actors),
      useFullExperience: true, selectedInterest: nil)
    let section = ExploreAssembly.buildSuggestedAccounts(input)
    #expect(section?.items.count == ExploreAssembly.suggestedAccountsForYouLimit)
  }

  @Test("a selected interest shows all suggested accounts")
  func selectedInterestShowsAll() {
    let actors = (0..<8).map { index in
      ProfileFixtures.profile(did: "did:plc:\(index)", handle: "user\(index).test")
    }
    let input = ExploreAssembly.Input(
      suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(actors: actors),
      useFullExperience: true, selectedInterest: "art")
    let section = ExploreAssembly.buildSuggestedAccounts(input)
    #expect(section?.items.count == 8)
  }

  @Test("a suggested-users error yields an error row with the RN copy")
  func suggestedUsersError() {
    let input = ExploreAssembly.Input(suggestedUsersError: "timeout")
    let section = ExploreAssembly.buildSuggestedAccounts(input)
    guard case .error(let error) = section?.items.first else {
      Issue.record("expected an error row")
      return
    }
    #expect(error.message == "Failed to load suggested follows")
    #expect(error.error == "timeout")
  }

  @Test("suggested feeds show 6 rows plus a load-more until pressed")
  func suggestedFeedsTruncate() {
    let feeds = (0..<10).map { index in
      ProfileFixtures.generatorView(uri: "at://f/\(index)", did: "did:plc:f\(index)", name: "F\(index)")
    }
    let input = ExploreAssembly.Input(
      suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output(feeds: feeds),
      useFullExperience: true, hasPressedLoadMoreFeeds: false)
    let section = ExploreAssembly.buildSuggestedFeeds(input)
    #expect(section?.items.count == ExploreAssembly.suggestedFeedsInitialLimit + 1)
    guard case .loadMore = section?.items.last else {
      Issue.record("expected a load-more row last")
      return
    }
  }

  @Test("pressing load more unslices the feeds and drops the row")
  func suggestedFeedsLoadMore() {
    let feeds = (0..<10).map { index in
      ProfileFixtures.generatorView(uri: "at://f/\(index)", did: "did:plc:f\(index)", name: "F\(index)")
    }
    let input = ExploreAssembly.Input(
      suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output(feeds: feeds),
      useFullExperience: true, hasPressedLoadMoreFeeds: true)
    let section = ExploreAssembly.buildSuggestedFeeds(input)
    #expect(section?.items.count == 10)
  }

  @Test("suggested feeds dedupe by URI")
  func suggestedFeedsDedupe() {
    let shared = ProfileFixtures.generatorView(uri: "at://f/1", did: "did:plc:f", name: "F")
    let input = ExploreAssembly.Input(
      suggestedFeeds: App.Bsky.UnspeccedGetSuggestedFeeds_Output(feeds: [shared, shared]),
      useFullExperience: true)
    let section = ExploreAssembly.buildSuggestedFeeds(input)
    #expect(section?.items.count == 1 + 1)  // one feed + the load-more row
  }

  @Test("a suggested-feeds error yields an error row")
  func suggestedFeedsError() {
    let input = ExploreAssembly.Input(useFullExperience: true, suggestedFeedsError: "boom")
    let section = ExploreAssembly.buildSuggestedFeeds(input)
    guard case .error(let error) = section?.items.first else {
      Issue.record("expected an error row")
      return
    }
    #expect(error.message == "Failed to load suggested feeds")
  }

  @Test("no suggested feeds drops the whole section including its header")
  func noSuggestedFeedsSection() {
    let input = ExploreAssembly.Input(useFullExperience: true)
    #expect(ExploreAssembly.buildSuggestedFeeds(input) == nil)
  }

  @Test("without the full experience feeds fall back to the popular list")
  func popularFeedsFallback() {
    let input = ExploreAssembly.Input(
      popularFeeds: [ProfileFixtures.generatorView(uri: "at://f/1", did: "did:plc:f", name: "F")],
      useFullExperience: false)
    let section = ExploreAssembly.buildSuggestedFeeds(input)
    #expect(section?.items.count == 1)
  }

  @Test("no starter packs drops the section")
  func noStarterPacks() {
    let empty = ExploreAssembly.Input(
      suggestedStarterPacks: App.Bsky.UnspeccedGetSuggestedStarterPacks_Output(starterPacks: []))
    #expect(ExploreAssembly.buildStarterPacks(empty) == nil)
  }

  @Test("starter packs render in response order")
  func starterPacks() {
    let input = ExploreAssembly.Input(
      suggestedStarterPacks: App.Bsky.UnspeccedGetSuggestedStarterPacks_Output(
        starterPacks: [ProfileFixtures.starterPack(uri: "at://sp/1"),
                       ProfileFixtures.starterPack(uri: "at://sp/2")]))
    let section = ExploreAssembly.buildStarterPacks(input)
    #expect(section?.items.count == 2)
  }

  @Test("the suggested-users recId surfaces on the page model")
  func recIdOnPage() {
    let input = ExploreAssembly.Input(
      suggestedUsers: App.Bsky.UnspeccedGetSuggestedUsersForExplore_Output(
        actors: [], recIdStr: "rec-9"))
    #expect(ExploreAssembly.build(input).recId == "rec-9")
  }
}

/// The trending data transform: dedupe, muted-word filter and slice.
@Suite("Trending")
struct TrendingTests {
  @Test("dedupes by link")
  func dedupe() {
    let trends = [
      ProfileFixtures.trend(link: "/t/1", topic: "a", displayName: "A"),
      ProfileFixtures.trend(link: "/t/1", topic: "a again", displayName: "A2"),
      ProfileFixtures.trend(link: "/t/2", topic: "b", displayName: "B"),
    ]
    #expect(Trending.dedupe(trends).count == 2)
  }

  @Test("slices to the display limit after filtering")
  func slices() {
    let trends = (0..<10).map { index in
      ProfileFixtures.trend(link: "/t/\(index)", topic: "t\(index)", displayName: "T\(index)")
    }
    let out = Trending.applyMutedWordFilter(
      App.Bsky.UnspeccedGetTrends_Output(trends: trends), limit: 5)
    #expect(out.trends.count == 5)
  }

  @Test("drops trends whose text matches a muted word")
  func mutedWords() {
    let trends = [
      ProfileFixtures.trend(link: "/t/1", topic: "art", displayName: "Art"),
      ProfileFixtures.trend(link: "/t/2", topic: "spam", displayName: "Spam"),
    ]
    let out = Trending.applyMutedWordFilter(
      App.Bsky.UnspeccedGetTrends_Output(trends: trends),
      isMuted: { $0.contains("spam") })
    #expect(out.trends.map(\.link) == ["/t/1"])
  }

  @Test("exposes the recommendation id")
  func recId() {
    let out = Trending.applyMutedWordFilter(
      App.Bsky.UnspeccedGetTrends_Output(recIdStr: "rec-3", trends: []))
    #expect(out.recId == "rec-3")
  }
}

/// Typeahead prefix normalization and suggestion filtering.
@Suite("ActorAutocomplete")
struct ActorAutocompleteTests {
  @Test("normalizes case and whitespace")
  func normalizes() {
    #expect(ActorAutocomplete.normalizePrefix("  ALI  ") == "ali")
  }

  @Test("drops one trailing dot so matches do not clear")
  func trailingDot() {
    #expect(ActorAutocomplete.normalizePrefix("foo.") == "foo")
    #expect(ActorAutocomplete.normalizePrefix("foo..") == "foo.")
  }

  @Test("an empty prefix does not fetch")
  func emptyPrefix() {
    #expect(ActorAutocomplete.shouldFetch(prefix: "") == false)
    #expect(ActorAutocomplete.shouldFetch(prefix: "a"))
  }

  @Test("dedupes by handle, keeping the first")
  func dedupesByHandle() {
    let items = ActorAutocomplete.suggestions(
      prefix: "a",
      searched: [
        ProfileFixtures.profileBasic(did: "did:plc:1", handle: "alice.test"),
        ProfileFixtures.profileBasic(did: "did:plc:2", handle: "alice.test"),
      ])
    #expect(items.count == 1)
    #expect(items.first?.did.rawValue == "did:plc:1")
  }

  @Test("keeps an unmoderated profile")
  func keepsClean() {
    #expect(
      ActorAutocomplete.shouldInclude(handle: "alice.test", prefix: "a", verdict: .clean))
  }

  @Test("drops a filtered profile that is not an exact match")
  func dropsFiltered() {
    let verdict = ActorAutocomplete.ModerationVerdict(
      filter: true, containsHideableOffense: false, isJustAMute: false)
    #expect(
      ActorAutocomplete.shouldInclude(handle: "alice.test", prefix: "a", verdict: verdict)
        == false)
  }

  @Test("keeps an exact handle match even when filtered")
  func keepsExactMatch() {
    let verdict = ActorAutocomplete.ModerationVerdict(
      filter: true, containsHideableOffense: false, isJustAMute: false)
    #expect(
      ActorAutocomplete.shouldInclude(handle: "alice.test", prefix: "alice.test", verdict: verdict))
  }

  @Test("drops an exact match carrying a hideable offense")
  func exactMatchHideable() {
    let verdict = ActorAutocomplete.ModerationVerdict(
      filter: true, containsHideableOffense: true, isJustAMute: false)
    #expect(
      ActorAutocomplete.shouldInclude(handle: "alice.test", prefix: "alice.test", verdict: verdict)
        == false)
  }

  @Test("keeps a merely muted profile")
  func keepsJustAMute() {
    let verdict = ActorAutocomplete.ModerationVerdict(
      filter: true, containsHideableOffense: false, isJustAMute: true)
    #expect(
      ActorAutocomplete.shouldInclude(handle: "alice.test", prefix: "a", verdict: verdict))
  }
}
