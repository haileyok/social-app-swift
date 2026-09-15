import Foundation
import Testing

@testable import OnboardingLogic

@Suite("Profile validation rules")
struct ProfileValidationTests {

  @Test(
    "display names that are accepted",
    arguments: ["Alice", "  Bob  ", "я", "Alice 👩‍🚀", String(repeating: "a", count: 64)]
  )
  func validDisplayNames(raw: String) {
    guard case .valid(let name) = ProfileValidation.validateDisplayName(raw) else {
      Issue.record("expected \(raw.debugDescription) to be valid")
      return
    }
    #expect(name == raw.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  @Test("a blank display name is empty, not invalid")
  func blankDisplayName() {
    #expect(ProfileValidation.validateDisplayName("   ") == .empty)
    #expect(ProfileValidation.validateDisplayName("") == .empty)
  }

  @Test("a display name over 64 UTF-16 units is rejected")
  func tooLongDisplayName() {
    let name = String(repeating: "a", count: 65)
    #expect(ProfileValidation.validateDisplayName(name) == .tooLong)
  }

  @Test("length is counted in UTF-16 units, matching the RN counter")
  func utf16LengthCounting() {
    // 33 emoji are 66 UTF-16 units but only 33 graphemes.
    let name = String(repeating: "🚀", count: 33)
    #expect(name.count == 33)
    #expect(name.utf16.count == 66)
    #expect(ProfileValidation.validateDisplayName(name) == .tooLong)
  }

  @Test(
    "handles that are accepted",
    arguments: ["alice.bsky.social", "ALICE.bsky.social", "alice-smith.test.com", "abc.xyz"]
  )
  func validHandles(raw: String) {
    guard case .valid(let handle) = ProfileValidation.validateHandle(raw) else {
      Issue.record("expected \(raw.debugDescription) to be valid")
      return
    }
    #expect(handle == raw.lowercased())
  }

  @Test("an empty handle is empty")
  func emptyHandle() {
    #expect(ProfileValidation.validateHandle("  ") == .empty)
  }

  @Test(
    "handles that are rejected",
    arguments: [
      "alice",  // no domain
      "alice.",  // empty trailing segment
      ".alice.test",  // empty leading segment
      "alice..test",  // empty interior segment
      "al.test",  // name segment too short
      "this-name-is-way-too-long.test",  // name segment over 18
      "al ice.test",  // space
      "alice_1.test",  // underscore
      "alicé.test",  // non-ASCII
      "-alice.test",  // leading hyphen in a segment
      "alice-.test",  // trailing hyphen in a segment
    ]
  )
  func invalidHandles(raw: String) {
    guard case .invalid = ProfileValidation.validateHandle(raw) else {
      Issue.record("expected \(raw.debugDescription) to be rejected")
      return
    }
  }

  @Test("a handle over 253 characters is rejected")
  func overlyLongHandle() {
    let longSegment = String(repeating: "a", count: 60)
    let handle = (0..<5).map { _ in longSegment }.joined(separator: ".")
    #expect(handle.count > 253)
    guard case .invalid = ProfileValidation.validateHandle(handle) else {
      Issue.record("expected an over-long handle to be rejected")
      return
    }
  }

  @Test("fullHandle composes name and domain")
  func fullHandleComposition() {
    #expect(
      ProfileValidation.fullHandle(name: "Alice", domain: "bsky.social") == "alice.bsky.social")
    #expect(
      ProfileValidation.fullHandle(name: "alice.", domain: ".bsky.social") == "alice.bsky.social")
    #expect(
      ProfileValidation.fullHandle(name: " alice ", domain: " BSKY.SOCIAL ") == "alice.bsky.social")
  }
}

@Suite("Interest taxonomy")
struct InterestsTests {

  @Test("the taxonomy matches the RN interests list")
  func taxonomyMatches() {
    #expect(Interests.all.count == 24)
    #expect(Interests.all == Interests.all.sorted())
    #expect(Interests.all.contains("dev"))
    #expect(Interests.all.contains("writers"))
  }

  @Test("popular interests are a subset of the taxonomy")
  func popularSubset() {
    for tag in Interests.popular {
      #expect(Interests.isValid(tag))
    }
    #expect(
      Interests.popular == [
        "art", "gaming", "sports", "comics", "music", "politics",
        "photography", "science", "news",
      ])
  }

  @Test("display names cover every tag")
  func displayNamesComplete() {
    for tag in Interests.all {
      #expect(Interests.displayNames[tag] != nil)
    }
    #expect(Interests.displayNames["dev"] == "Software Dev")
    #expect(Interests.displayNames["gaming"] == "Video Games")
  }

  @Test("known filters off-vocabulary tags, preserving order")
  func knownFilter() {
    #expect(Interests.known(["art", "not-a-tag", "music"]) == ["art", "music"])
    #expect(Interests.known([]) == [])
  }

  @Test("orderedForTabs follows the strongest boost first")
  func tabOrder() {
    let ordered = Interests.orderedForTabs(selected: ["animals", "art"])
    // The chained calls make the *selection* sort the primary key, and
    // boostInterests ranks by position, so selection order is preserved; the
    // popular list then orders everything else.
    #expect(
      ordered.prefix(5) == ["animals", "art", "gaming", "sports", "comics"])
    #expect(ordered.count == 24)
    #expect(Set(ordered) == Set(Interests.all))
  }

  @Test("orderedForTabs is stable with no selection")
  func tabOrderNoSelection() {
    let ordered = Interests.orderedForTabs(selected: [])
    #expect(ordered.prefix(5) == ["art", "gaming", "sports", "comics", "music"])
  }
}
