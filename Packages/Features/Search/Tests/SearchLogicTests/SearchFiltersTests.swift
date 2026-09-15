import Testing

@testable import SearchLogic

/// Ports the `searchParams` suite from
/// `screens/Search/__tests__/searchParams.test.ts`.
@Suite("SearchFilters")
struct SearchFiltersTests {
  @Test("reads present string filters")
  func readsPresent() {
    let filters = SearchFilters.read(from: ["q": "cats", "author": "alice", "domain": "bsky.app"])
    #expect(filters == SearchFilters(author: "alice", domain: "bsky.app"))
  }

  @Test("ignores the literal string undefined")
  func ignoresUndefinedLiteral() {
    let filters = SearchFilters.read(from: [
      "q": "cats", "author": "alice", "mentions": "undefined", "domain": "undefined",
    ])
    #expect(filters == SearchFilters(author: "alice"))
  }

  @Test("ignores empty and non-string values")
  func ignoresEmpty() {
    #expect(SearchFilters.read(from: ["author": "", "tag": nil]) == SearchFilters())
  }

  @Test("hasPostOnlyFilters returns false for a lang-only filter")
  func postOnlyLangOnly() {
    #expect(SearchFilters(lang: "en").hasPostOnlyFilters == false)
  }

  @Test("hasPostOnlyFilters returns false for no filters")
  func postOnlyNone() {
    #expect(SearchFilters().hasPostOnlyFilters == false)
  }

  @Test("hasPostOnlyFilters returns true for a post-restricting filter")
  func postOnlyTrue() {
    #expect(SearchFilters(author: "alice").hasPostOnlyFilters)
    #expect(SearchFilters(media: "true").hasPostOnlyFilters)
    #expect(SearchFilters(excludeTag: "spam").hasPostOnlyFilters)
  }

  @Test("hasPostOnlyFilters returns true when lang is combined with a post-only filter")
  func postOnlyCombined() {
    #expect(SearchFilters(author: "alice", lang: "en").hasPostOnlyFilters)
  }

  @Test("hasActiveFilters includes the structured Me author filter")
  func activeFilters() {
    #expect(SearchFilters().isActive == false)
    #expect(SearchFilters(from: "me").isActive)
    #expect(SearchFilters(author: "alice").isActive)
  }

  @Test("definedFilterParams omits absent keys entirely")
  func definedParams() {
    #expect(SearchFilters(author: "alice").definedParams == ["author": "alice"])
  }

  @Test("withoutFilterParams strips filter keys but keeps q/tab/name")
  func withoutFilterParams() {
    let stripped = SearchFilters.withoutFilterParams([
      "q": "cats", "tab": "latest", "name": "alice", "author": "alice", "domain": "undefined",
    ])
    #expect(stripped == ["q": "cats", "tab": "latest", "name": "alice"])
  }

  @Test("filtersToApiParams splits list fields into arrays and maps v2-only filters")
  func dialogParamsSplitList() {
    let params = SearchPostsV2Filters.fromDialogFilters(
      SearchFilters(
        author: "alice bob", domain: "bsky.app", tag: "atproto bluesky", lang: "en",
        replies: "none", media: "true"))
    #expect(params.authors == ["alice", "bob"])
    #expect(params.domains == ["bsky.app"])
    #expect(params.hashtags == ["atproto", "bluesky"])
    #expect(params.language == "en")
    #expect(params.hasMedia)
    #expect(params.excludeReplies)
  }

  @Test("filtersToApiParams maps video/following and repliesOnly")
  func dialogParamsBooleans() {
    let params = SearchPostsV2Filters.fromDialogFilters(
      SearchFilters(replies: "only", video: "true", following: "true"))
    #expect(params.hasVideo)
    #expect(params.following)
    #expect(params.repliesOnly)
    #expect(params.excludeReplies == false)
  }

  @Test("filtersToApiParams maps exclude* keys to v2 exclude* arrays")
  func dialogParamsExcludes() {
    let params = SearchPostsV2Filters.fromDialogFilters(
      SearchFilters(
        excludeAuthor: "alice bob", excludeMentions: "carol", excludeDomain: "spam.com",
        excludeUrl: "spam.com/x", excludeTag: "nsfw promo"))
    #expect(params.excludeAuthors == ["alice", "bob"])
    #expect(params.excludeMentions == ["carol"])
    #expect(params.excludeDomains == ["spam.com"])
    #expect(params.excludeUrls == ["spam.com/x"])
    #expect(params.excludeHashtags == ["nsfw", "promo"])
  }

  @Test("countActiveFilters counts each structured filter key once")
  func countActive() {
    #expect(SearchFilters().countActiveFilters() == 0)
    #expect(SearchFilters(from: "me").countActiveFilters() == 1)
    #expect(SearchFilters(author: "alice bob", domain: "bsky.app").countActiveFilters() == 2)
  }
}

/// Ports the `search history serialize/parse` block from the same test file.
@Suite("SearchHistoryCoding")
struct SearchHistoryCodingTests {
  @Test("stores a filter-less search as a plain string")
  func plainString() {
    #expect(SearchHistoryCoding.serialize(q: "cats") == "cats")
  }

  @Test("stores a filtered search as JSON")
  func filteredJSON() {
    let stored = SearchHistoryCoding.serialize(q: "cats", filters: SearchFilters(author: "alice"))
    #expect(stored != "cats")
    let parsed = SearchHistoryCoding.parse(stored)
    #expect(parsed.q == "cats")
    #expect(parsed.filters == SearchFilters(author: "alice"))
  }

  @Test("round-trips a promoted Me-only search")
  func meOnly() {
    let stored = SearchHistoryCoding.serialize(q: "", filters: SearchFilters(from: "me"))
    let parsed = SearchHistoryCoding.parse(stored)
    #expect(parsed.q.isEmpty)
    #expect(parsed.filters == SearchFilters(from: "me"))
  }

  @Test("round-trips query + filters")
  func queryAndFilters() {
    let filters = SearchFilters(author: "alice", tag: "black orange", since: "2024-01-01")
    let stored = SearchHistoryCoding.serialize(q: "cats", filters: filters)
    let parsed = SearchHistoryCoding.parse(stored)
    #expect(parsed.q == "cats")
    #expect(parsed.filters == filters)
  }

  @Test("reads a legacy plain-string entry as a query with no filters")
  func legacy() {
    let parsed = SearchHistoryCoding.parse("plain old search")
    #expect(parsed.q == "plain old search")
    #expect(parsed.filters == SearchFilters())
  }

  @Test("treats malformed JSON as a plain query without throwing")
  func malformed() {
    let parsed = SearchHistoryCoding.parse("{not valid json")
    #expect(parsed.q == "{not valid json")
    #expect(parsed.filters == SearchFilters())
  }

  @Test("treats a JSON value lacking a string q as a plain query")
  func jsonWithoutQ() {
    let weird = "{\"foo\":\"bar\"}"
    let parsed = SearchHistoryCoding.parse(weird)
    #expect(parsed.q == weird)
    #expect(parsed.filters == SearchFilters())
  }
}
