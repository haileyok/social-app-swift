import Foundation
import QueryStore
import Testing

@testable import OnboardingLogic

@Suite("Query keys")
struct OnboardingQueryKeyTests {

  @Test("suggested-users key root matches the RN root")
  func usersRoot() {
    let key = OnboardingQueryKeys.suggestedUsers()
    #expect(key.root == "unspecced-suggested-onboarding-users")
  }

  @Test("starter-packs key root matches the RN root")
  func starterPacksRoot() {
    let key = OnboardingQueryKeys.suggestedStarterPacks()
    #expect(key.root == "onboarding-suggested-starter-packs")
  }

  @Test("interests are joined, so order-insensitivity is by construction")
  func interestsJoined() {
    let args = OnboardingQueryKeys.SuggestedUsersArgs(overrideInterests: ["art", "music"])
    #expect(args.overrideInterests == "art,music")
  }

  @Test("different categories produce different keys")
  func categoryDistinguishes() {
    let a = OnboardingQueryKeys.suggestedUsers(category: "art")
    let b = OnboardingQueryKeys.suggestedUsers(category: "music")
    #expect(a != b)
  }

  @Test("different interest sets produce different keys")
  func interestsDistinguish() {
    let a = OnboardingQueryKeys.suggestedStarterPacks(overrideInterests: ["art"])
    let b = OnboardingQueryKeys.suggestedStarterPacks(overrideInterests: ["music"])
    #expect(a != b)
  }

  @Test("the same inputs produce an equal key")
  func stableKeys() {
    #expect(
      OnboardingQueryKeys.suggestedUsers(category: "art", limit: 10, overrideInterests: ["art"])
        == OnboardingQueryKeys.suggestedUsers(
          category: "art", limit: 10, overrideInterests: ["art"]))
  }

  @Test("a key round-trips through its rendered args")
  func persistedRoundTrip() {
    let key = OnboardingQueryKeys.suggestedUsers(category: "art", limit: 10)
    let rebuilt = QueryKey(
      root: key.root, argsText: key.argsDebugDescription, options: key.options)
    #expect(rebuilt == key)
  }

  @Test("scope separates two accounts")
  func scope() {
    let a = OnboardingQueryKeys.suggestedUsers(scope: "did:plc:a")
    let b = OnboardingQueryKeys.suggestedUsers(scope: "did:plc:b")
    #expect(a != b)
  }

  @Test("the topics header joins interests")
  func topicsHeader() {
    #expect(OnboardingQueryKeys.topicsHeader(["art", "music"]) == ["X-Bsky-Topics": "art,music"])
    #expect(OnboardingQueryKeys.topicsHeader([]) == ["X-Bsky-Topics": ""])
  }

  @Test("limits match the RN call sites")
  func limits() {
    #expect(OnboardingQueryKeys.suggestedUsersLimit == 10)
    #expect(OnboardingQueryKeys.suggestedStarterPacksLimit == 6)
  }
}
