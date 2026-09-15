import Foundation
import QueryStore
import Testing

@testable import StarterPacksLogic

/// Asserts the query keys against the RN roots.
@Suite("StarterPackKeys")
struct StarterPackKeyTests {
  @Test("the key roots are the RN roots")
  func roots() {
    #expect(StarterPackKeys.packRoot == "starter-pack")
    #expect(StarterPackKeys.actorStarterPacksRoot == "actor-starter-packs")
    #expect(
      StarterPackKeys.actorStarterPacksWithMembershipRoot
        == "actor-starter-packs-with-membership")
    #expect(StarterPackKeys.searchRoot == "starter-pack-search")
    #expect(StarterPackKeys.listMembersRoot == "list-members")
    #expect(StarterPackKeys.listMembersAllRoot == "list-members-all")
  }

  @Test("a pack key from a URI keys on the parsed name and rkey")
  func packKeyFromURI() {
    let key = StarterPackKeys.pack(uri: Fixtures.packURI())
    #expect(key.keyRoot == "starter-pack")
    #expect(key.description.contains(Fixtures.authorDID))
    #expect(key.description.contains(Fixtures.packRkey))
  }

  @Test("a pack key from a DID and rkey matches the URI form")
  func packKeyFormsAgree() {
    let fromURI = StarterPackKeys.pack(uri: Fixtures.packURI())
    let fromDid = StarterPackKeys.pack(name: Fixtures.authorDID, rkey: Fixtures.packRkey)
    #expect(fromURI == fromDid)
  }

  @Test("an http pack URI keys on the parsed handle, as RN's does")
  func packKeyFromHTTPURI() {
    let key = StarterPackKeys.pack(uri: "https://bsky.app/starter-pack/joshuajfriedman.com/3abc")
    #expect(key.description.contains("joshuajfriedman.com"))
    #expect(key.description.contains("3abc"))
  }

  @Test("an unparseable URI falls back to a raw key, distinct from other bad inputs")
  func packKeyUnparseable() {
    let first = StarterPackKeys.pack(uri: "garbage-one")
    let second = StarterPackKeys.pack(uri: "garbage-two")
    #expect(first != second)
    #expect(first.keyRoot == "starter-pack")
  }

  @Test("two different packs get two different keys")
  func packKeyDistinctness() {
    let first = StarterPackKeys.pack(name: Fixtures.authorDID, rkey: "3a")
    let second = StarterPackKeys.pack(name: Fixtures.authorDID, rkey: "3b")
    let third = StarterPackKeys.pack(name: Fixtures.otherDID, rkey: "3a")
    #expect(first != second)
    #expect(first != third)
    #expect(second != third)
  }

  @Test("an actor key with no actor matches the empty-actor key RN builds")
  func actorKeyDisabled() {
    #expect(
      StarterPackKeys.actorStarterPacks(actor: nil)
        == StarterPackKeys.actorStarterPacks(actor: ""))
  }

  @Test("the two actor roots do not collide")
  func actorRootsDistinct() {
    let plain = StarterPackKeys.actorStarterPacks(actor: "did:plc:a")
    let withMembership = StarterPackKeys.actorStarterPacksWithMembership(actor: "did:plc:a")
    #expect(plain != withMembership)
    #expect(plain.keyRoot != withMembership.keyRoot)
  }

  @Test("the search key carries the query and the limit, as RN's does")
  func searchKey() {
    let first = StarterPackKeys.search(query: "art", limit: 25)
    let second = StarterPackKeys.search(query: "art", limit: 10)
    let third = StarterPackKeys.search(query: "music", limit: 25)
    #expect(first != second)
    #expect(first != third)
    #expect(first.keyRoot == "starter-pack-search")
  }

  @Test("the member keys separate the paged and exhaustive reads")
  func memberKeys() {
    let paged = StarterPackKeys.listMembers(uri: Fixtures.listURI())
    let all = StarterPackKeys.listMembersAll(uri: Fixtures.listURI())
    #expect(paged != all)
    #expect(paged.keyRoot == "list-members")
    #expect(all.keyRoot == "list-members-all")
  }

  @Test("a scope separates two accounts' entries")
  func scopeSeparatesAccounts() {
    let first = StarterPackKeys.pack(uri: Fixtures.packURI(), scope: "did:plc:one")
    let second = StarterPackKeys.pack(uri: Fixtures.packURI(), scope: "did:plc:two")
    #expect(first != second)
    #expect(first.scope == "did:plc:one")
  }

  @Test("no starter-pack key is persisted, matching RN")
  func noPersistedVersion() {
    // RN declares no `persistedVersion` on any starter-pack key; only the
    // starter-pack view is written to the cache optimistically (`precache`).
    #expect(StarterPackKeys.pack(uri: Fixtures.packURI()).persistedVersion == nil)
    #expect(StarterPackKeys.actorStarterPacks(actor: "did:plc:a").persistedVersion == nil)
    #expect(StarterPackKeys.listMembers(uri: Fixtures.listURI()).persistedVersion == nil)
  }
}
