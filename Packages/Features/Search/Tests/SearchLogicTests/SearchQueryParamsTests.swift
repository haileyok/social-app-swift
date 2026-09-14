import Lexicons
import Testing

@testable import SearchLogic

/// Ports the `extractSearchPostsParams` table from
/// `state/queries/__tests__/search-posts-params.test.ts`.
@Suite("SearchQueryParams.extract")
struct SearchQueryParamsExtractTests {
  struct Row: Sendable, CustomStringConvertible {
    let name: String
    let input: String
    let output: ExtractedSearchParams
    var description: String { name }
  }

  static let rows: [Row] = [
    Row(name: "passes bare text through untouched", input: "hello world",
      output: .init(q: "hello world")),
    Row(name: "lifts from: into author and strips it from q", input: "cats from:alice",
      output: .init(q: "cats", author: "alice")),
    Row(name: "lifts to: into mentions (alias) and strips it from q", input: "cats to:alice",
      output: .init(q: "cats", mentions: "alice")),
    Row(name: "strips a leading @ from from:", input: "cats from:@alice.bsky.social",
      output: .init(q: "cats", author: "alice.bsky.social")),
    Row(name: "strips a leading @ from mentions:", input: "cats mentions:@alice.bsky.social",
      output: .init(q: "cats", mentions: "alice.bsky.social")),
    Row(name: "strips a leading @ from to: (mentions alias)", input: "cats to:@alice.bsky.social",
      output: .init(q: "cats", mentions: "alice.bsky.social")),
    Row(name: "keeps from:me in q verbatim", input: "cats from:me",
      output: .init(q: "cats from:me")),
    Row(name: "keeps to:me in q verbatim", input: "cats to:me",
      output: .init(q: "cats to:me")),
    Row(name: "keeps mentions:me in q verbatim", input: "cats mentions:me",
      output: .init(q: "cats mentions:me")),
    Row(name: "accumulates multiple hashtags into tag[]", input: "#cats #dogs",
      output: .init(q: "", tag: ["cats", "dogs"])),
    Row(name: "keeps quoted phrases in q", input: "\"no clues\" from:alice",
      output: .init(q: "\"no clues\"", author: "alice")),
    Row(name: "keeps OR groups in q", input: "(cats OR dogs) lang:en",
      output: .init(q: "(cats OR dogs)", lang: "en")),
    Row(name: "extracts a valid since date", input: "cats since:2024-01-01",
      output: .init(q: "cats", since: "2024-01-01")),
    Row(name: "leaves an invalid since date in q", input: "cats since:garbage",
      output: .init(q: "cats since:garbage")),
    Row(name: "leaves unsupported operators in q", input: "cats replies:only media:true",
      output: .init(q: "cats replies:only media:true")),
    Row(
      name: "lifts all supported operators at once",
      input:
        "term from:alice mentions:bob domain:bsky.app url:bsky.app/x lang:en since:2024-01-01 until:2024-02-01 #tag",
      output: .init(
        q: "term", author: "alice", mentions: "bob", domain: "bsky.app", url: "bsky.app/x",
        lang: "en", since: "2024-01-01", until: "2024-02-01", tag: ["tag"])),
    Row(name: "keeps the first value for a repeated singular operator",
      input: "from:alice from:bob", output: .init(q: "", author: "alice")),
    // CJK (and other space-free scripts) carries no whitespace, so the
    // whitespace-based tokenizer must keep it intact as bare query text.
    Row(name: "passes bare CJK text through untouched", input: "東京",
      output: .init(q: "東京")),
    Row(name: "lifts an operator from a CJK query and keeps the CJK text",
      input: "東京 from:alice", output: .init(q: "東京", author: "alice")),
    Row(name: "treats a whole CJK phrase as a single token", input: "寿司 ラーメン",
      output: .init(q: "寿司 ラーメン")),
    Row(name: "lifts a CJK hashtag into tag[]", input: "#日本 ramen",
      output: .init(q: "ramen", tag: ["日本"])),
  ]

  @Test("extractSearchPostsParams table", arguments: rows)
  func extractTable(_ row: Row) {
    #expect(SearchQueryParams.extract(row.input) == row.output)
  }
}

/// Ports the `extractFromMe / appendFromMe` block from the same test file.
@Suite("SearchQueryParams.fromMe")
struct SearchQueryParamsFromMeTests {
  @Test("strips a bare from:me token and reports it")
  func stripsFromMe() {
    #expect(SearchQueryParams.extractFromMe("cats from:me") == (q: "cats", fromMe: true))
    #expect(SearchQueryParams.extractFromMe("from:me") == (q: "", fromMe: true))
  }

  @Test("reports fromMe false when the token is absent")
  func reportsFalse() {
    #expect(SearchQueryParams.extractFromMe("cats from:alice") == (q: "cats from:alice", fromMe: false))
  }

  @Test("leaves a quoted from:me in the query text")
  func quotedFromMe() {
    #expect(SearchQueryParams.extractFromMe("\"from:me\"") == (q: "\"from:me\"", fromMe: false))
  }

  @Test("re-appends the token only when the filter is active")
  func appends() {
    #expect(SearchQueryParams.appendFromMe("cats", fromMe: true) == "cats from:me")
    #expect(SearchQueryParams.appendFromMe("cats", fromMe: false) == "cats")
    #expect(SearchQueryParams.appendFromMe("", fromMe: true) == "from:me")
  }

  @Test("does not duplicate an existing from:me token")
  func noDuplicate() {
    #expect(SearchQueryParams.appendFromMe("cats from:me", fromMe: true) == "cats from:me")
  }

  @Test("round-trips through extract and append")
  func roundTrip() {
    let (q, fromMe) = SearchQueryParams.extractFromMe("cats from:me")
    #expect(SearchQueryParams.appendFromMe(q, fromMe: fromMe) == "cats from:me")
  }
}

/// Ports the `buildSearchPostsV2Filters` block from the same test file.
@Suite("SearchPostsV2Filters.build")
struct SearchPostsV2FiltersTests {
  @Test("maps embedded operators alone into v2 plural params")
  func embeddedOnly() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: .init(q: "", author: "alice", domain: "bsky.app", lang: "en", tag: ["cats"]))
    #expect(built[.authors] == .list(["alice"]))
    #expect(built[.domains] == .list(["bsky.app"]))
    #expect(built[.languages] == .list(["en"]))
    #expect(built[.hashtags] == .list(["cats"]))
  }

  @Test("maps dialog filters alone, including v2-only booleans")
  func dialogOnly() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: ExtractedSearchParams(q: ""),
      filters: .init(author: "bob carol", replies: "none", media: "true"))
    #expect(built[.authors] == .list(["bob", "carol"]))
    #expect(built[.hasMedia] == .flag(true))
    #expect(built[.excludeReplies] == .flag(true))
  }

  @Test("unions list values from both sources without clobbering")
  func unionsLists() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: .init(q: "", author: "alice", tag: ["cats"]),
      filters: .init(author: "bob carol", tag: "dogs"))
    #expect(built[.authors] == .list(["alice", "bob", "carol"]))
    #expect(built[.hashtags] == .list(["cats", "dogs"]))
  }

  @Test("dedupes overlapping values across sources")
  func dedupesOverlap() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: .init(q: "", author: "alice"), filters: .init(author: "alice bob"))
    #expect(built[.authors] == .list(["alice", "bob"]))
  }

  @Test("prefers the dialog filter for scalar fields, falling back to embedded")
  func scalarPreference() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: .init(q: "", lang: "en", since: "2024-01-01"), filters: .init(lang: "ja"))
    #expect(built[.languages] == .list(["ja"]))
    #expect(built[.since] == .scalar("2024-01-01T00:00:00Z"))
  }

  @Test("normalizes date-only since/until to midnight UTC timestamps")
  func dateNormalization() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: .init(q: ""), filters: .init(since: "2024-01-01", until: "2024-02-01"))
    #expect(built[.since] == .scalar("2024-01-01T00:00:00Z"))
    #expect(built[.until] == .scalar("2024-02-01T00:00:00Z"))
  }

  @Test("leaves a timestamp with an explicit time component unchanged")
  func explicitTimestamp() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: .init(q: ""), filters: .init(until: "2024-02-01T12:30:00Z"))
    #expect(built[.until] == .scalar("2024-02-01T12:30:00Z"))
  }

  @Test("passes exclude lists through from dialog filters")
  func excludeLists() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(
      embedded: .init(q: "", author: "alice"),
      filters: .init(excludeAuthor: "bob carol", excludeTag: "spam"))
    #expect(built[.authors] == .list(["alice"]))
    #expect(built[.excludeAuthors] == .list(["bob", "carol"]))
    #expect(built[.excludeHashtags] == .list(["spam"]))
  }

  @Test("omits a field when no source supplies a value")
  func omitsAbsent() {
    let built: SearchPostsV2Filters = SearchPostsV2Filters.build(embedded: .init(q: ""))
    #expect(built.fields.isEmpty)
  }
}
