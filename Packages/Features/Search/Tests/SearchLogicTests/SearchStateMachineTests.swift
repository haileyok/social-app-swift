import Foundation
import Lexicons
import Testing

@testable import SearchLogic

/// Debounce + cancellation transitions, driven by ``ManualSearchClock``.
///
/// These are behaviors rather than ported tests: the RN app gets them from React
/// effect timing, which has no unit test. The clock seam makes the same
/// semantics assertable.
@Suite("SearchStateMachine")
struct SearchStateMachineTests {
  /// A controllable typeahead stub.
  actor SuggestionStub {
    private(set) var queries: [String] = []
    private var result: [App.Bsky.ActorDefs_ProfileViewBasic] = []
    private var failure: (any Error)?
    /// Set to suspend a request until ``release()`` is called.
    private var gate: CheckedContinuation<Void, Never>?
    private var shouldGate = false

    func setResult(_ items: [App.Bsky.ActorDefs_ProfileViewBasic]) { result = items }
    func setFailure(_ error: any Error) { failure = error }
    func gateNextRequest() { shouldGate = true }

    func release() {
      gate?.resume()
      gate = nil
    }

    func fetch(_ query: String) async throws -> [App.Bsky.ActorDefs_ProfileViewBasic] {
      queries.append(query)
      if shouldGate {
        shouldGate = false
        await withCheckedContinuation { gate = $0 }
      }
      if let failure { throw failure }
      return result
    }
  }

  private func makeMachine(
    clock: ManualSearchClock,
    stub: SuggestionStub,
    debounceMilliseconds: UInt64 = 500
  ) -> SearchStateMachine {
    SearchStateMachine(
      clock: clock, debounceMilliseconds: debounceMilliseconds,
      fetchSuggestions: { query in try await stub.fetch(query) })
  }

  @Test("starts idle")
  func startsIdle() async {
    let machine = makeMachine(clock: ManualSearchClock(), stub: SuggestionStub())
    #expect(await machine.model.state == .idle)
  }

  @Test("typing debounces before fetching")
  func typingDebounces() async {
    let clock = ManualSearchClock()
    let stub = SuggestionStub()
    let machine = makeMachine(clock: clock, stub: stub)

    await machine.type("cat")
    #expect(await machine.model.state == .suggesting(.debouncing(query: "cat")))
    #expect(await stub.queries.isEmpty)
    #expect(clock.scheduledDelays == [500 * 1_000_000])
  }

  @Test("the debounce firing fetches and resolves to loaded")
  func debounceFires() async {
    let clock = ManualSearchClock()
    let stub = SuggestionStub()
    await stub.setResult([ProfileFixtures.profileBasic(did: "did:plc:a", handle: "alice.test")])
    let machine = makeMachine(clock: clock, stub: stub)

    await machine.type("alice")
    clock.advance(milliseconds: 500)
    await Task.yield()
    await Task.yield()
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(await stub.queries == ["alice"])
    if case .suggesting(.loaded(let query, let items)) = await machine.model.state {
      #expect(query == "alice")
      #expect(items.count == 1)
    } else {
      Issue.record("expected loaded, got \(await machine.model.state)")
    }
  }

  @Test("a keystroke before the debounce cancels the pending fetch")
  func keystrokeCancelsDebounce() async {
    let clock = ManualSearchClock()
    let stub = SuggestionStub()
    let machine = makeMachine(clock: clock, stub: stub)

    await machine.type("ca")
    clock.advance(milliseconds: 200)
    await machine.type("cat")
    // Reaching the first debounce's due time must not fire it.
    clock.advance(milliseconds: 300)
    await Task.yield()
    await Task.yield()
    #expect(await stub.queries.isEmpty)
    #expect(clock.scheduledDelays == [500 * 1_000_000, 500 * 1_000_000])
  }

  @Test("an empty query with no filters returns to idle without fetching")
  func emptyReturnsIdle() async {
    let clock = ManualSearchClock()
    let stub = SuggestionStub()
    let machine = makeMachine(clock: clock, stub: stub)

    await machine.type("cat")
    await machine.type("")
    clock.advance(milliseconds: 500)
    await Task.yield()
    #expect(await machine.model.state == .idle)
    #expect(await stub.queries.isEmpty)
  }

  @Test("an empty query with filters shows results")
  func emptyWithFiltersShowsResults() async {
    let machine = makeMachine(clock: ManualSearchClock(), stub: SuggestionStub())
    await machine.setFilters(SearchFilters(author: "alice"))
    await machine.type("")
    if case .results(let state) = await machine.model.state {
      #expect(state.filters == SearchFilters(author: "alice"))
    } else {
      Issue.record("expected results, got \(await machine.model.state)")
    }
  }

  @Test("submit moves to results and cancels pending suggestions")
  func submitCancels() async {
    let clock = ManualSearchClock()
    let stub = SuggestionStub()
    let machine = makeMachine(clock: clock, stub: stub)

    await machine.type("cat")
    await machine.submit()
    clock.advance(milliseconds: 500)
    await Task.yield()
    await Task.yield()

    if case .results(let state) = await machine.model.state {
      #expect(state.query == "cat")
    } else {
      Issue.record("expected results, got \(await machine.model.state)")
    }
    #expect(await stub.queries.isEmpty)
  }

  @Test("a from:me operator promotes to the Me filter on submit")
  func fromMePromotion() async {
    let machine = makeMachine(clock: ManualSearchClock(), stub: SuggestionStub())
    await machine.type("cats from:me")
    await machine.submit()
    #expect(await machine.model.fromMe)
    if case .results(let state) = await machine.model.state {
      // The `from:me` token is stripped from the committed query text.
      #expect(state.query == "cats")
      #expect(state.fromMe)
    } else {
      Issue.record("expected results")
    }
  }

  @Test("a failing suggestion reports the cleaned error")
  func failureState() async {
    let clock = ManualSearchClock()
    let stub = SuggestionStub()
    struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
    await stub.setFailure(Boom())
    let machine = makeMachine(clock: clock, stub: stub)

    await machine.type("cat")
    clock.advance(milliseconds: 500)
    try? await Task.sleep(nanoseconds: 50_000_000)
    if case .suggesting(.failed(let query, let message)) = await machine.model.state {
      #expect(query == "cat")
      #expect(message == "boom")
    } else {
      Issue.record("expected failed, got \(await machine.model.state)")
    }
  }

  @Test("a post-only filter hides the People and Feeds tabs")
  func postOnlyFilterHidesTabs() async {
    let machine = makeMachine(clock: ManualSearchClock(), stub: SuggestionStub())
    await machine.type("cats")
    await machine.submit()
    #expect(await machine.model.tabs == SearchTab.allCases)

    await machine.selectTab(.people)
    #expect(await machine.model.tab == .people)

    await machine.setFilters(SearchFilters(author: "alice"))
    #expect(await machine.model.tabs == [.top, .latest])
    // The now-hidden tab falls back to the first tab.
    #expect(await machine.model.tab == .top)
  }

  @Test("selecting an unavailable tab is ignored")
  func ignoresUnavailableTab() async {
    let machine = makeMachine(clock: ManualSearchClock(), stub: SuggestionStub())
    await machine.setFilters(SearchFilters(author: "alice"))
    await machine.selectTab(.feeds)
    #expect(await machine.model.tab == .top)
  }

  @Test("reset returns to idle and cancels pending work")
  func reset() async {
    let clock = ManualSearchClock()
    let stub = SuggestionStub()
    let machine = makeMachine(clock: clock, stub: stub)
    await machine.type("cat")
    await machine.reset()
    clock.advance(milliseconds: 500)
    await Task.yield()
    #expect(await machine.model.state == .idle)
    #expect(await machine.model.query.isEmpty)
    #expect(await stub.queries.isEmpty)
  }
}

@Suite("cleanError")
struct CleanErrorTests {
  @Test("passes a localized description through")
  func localized() {
    struct Boom: LocalizedError { var errorDescription: String? { "specific" } }
    #expect(cleanError(Boom()) == "specific")
  }

  @Test("falls back to Unknown error for an empty description")
  func empty() {
    struct Boom: LocalizedError { var errorDescription: String? { "  " } }
    #expect(cleanError(Boom()) == "Unknown error")
  }
}
