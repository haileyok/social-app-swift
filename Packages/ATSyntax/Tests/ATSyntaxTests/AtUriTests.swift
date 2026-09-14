import Testing
import FoundationEssentials
@testable import ATSyntax

@Suite struct AtUriTests {
  @Test func validAtUriFixtures() throws {
    let lines = try fixtureLines("aturi_valid")
    #expect(lines.count == 23)
    for line in lines {
      let uri = try AtUri(line)
      // round-trip: the serialized form must itself be parseable
      _ = try AtUri(uri.description)
    }
  }

  @Test func invalidAtUriFixtures() throws {
    let lines = try fixtureLines("aturi_invalid")
    #expect(lines.count == 72)
    for line in lines {
      #expect(throws: (any Error).self) {
        _ = try AtUri(line)
      }
    }
  }

  @Test func makeAndDecompose() throws {
    let uri = try AtUri.make(
      "did:plc:abcdef", collection: "app.bsky.feed.post", rkey: "3jz7e4l2kx5r")
    #expect(uri.host == "did:plc:abcdef")
    #expect(uri.collectionSafe == "app.bsky.feed.post")
    #expect(uri.rkeySafe == "3jz7e4l2kx5r")
    #expect(
      uri.description == "at://did:plc:abcdef/app.bsky.feed.post/3jz7e4l2kx5r")
  }

  @Test func makeWithHandleHost() throws {
    let uri = try AtUri.make("alice.example", collection: "app.bsky.feed.post")
    #expect(uri.host == "alice.example")
    #expect(uri.rkeySafe == "")
    #expect(uri.description == "at://alice.example/app.bsky.feed.post")
  }

  @Test func didAccessorThrowsForHandleHost() throws {
    let uri = try AtUri("at://alice.example")
    #expect(throws: ATSyntaxError.self) {
      _ = try uri.did
    }
  }

  @Test func strictModeRejectsQuery() {
    #expect(throws: ATSyntaxError.self) {
      _ = try AtUri("at://did:plc:abc/com.example.record/1?foo=bar")
    }
  }

  @Test func nonStrictModeAcceptsQuery() throws {
    let uri = try AtUri(
      "at://did:plc:abc/com.example.record/1?foo=bar&baz=qux", strict: false)
    #expect(uri.searchParams.count == 2)
    #expect(uri.searchParams[0].name == "foo")
    #expect(uri.searchParams[0].value == "bar")
    #expect(uri.search == "foo=bar&baz=qux")
    #expect(uri.description.contains("?foo=bar&baz=qux"))
  }

  @Test func strictModeRejectsTrailingSlash() {
    #expect(throws: ATSyntaxError.self) {
      _ = try AtUri("at://alice.example/com.example.record/1/")
    }
  }

  @Test func nonStrictModeKeepsTrailingSlash() throws {
    let uri = try AtUri("at://alice.example/com.example.record/1/", strict: false)
    #expect(uri.hadTrailingSlash)
    #expect(uri.description == "at://alice.example/com.example.record/1/")
  }

  @Test func hashKept() throws {
    let uri = try AtUri("at://did:plc:abc/com.example.record/1#/frag")
    #expect(uri.hash == "/frag")
    #expect(uri.description == "at://did:plc:abc/com.example.record/1#/frag")
  }

  @Test func bareHostOnly() throws {
    let uri = try AtUri("at://alice.example")
    #expect(uri.host == "alice.example")
    #expect(uri.pathname == "")
    #expect(uri.collectionSafe == "")
    #expect(uri.description == "at://alice.example")
  }

  @Test func protocolPrefixRequired() {
    // bare did:... is not an at-uri in strict semantics (legacy class
    // accepted it; the validation module requires at://)
    #expect(throws: ATSyntaxError.self) {
      _ = try AtUri("did:plc:abcdef/app.bsky.feed.post/3jz7e4l")
    }
  }

  @Test func invalidRkeyRejectedInStrict() {
    #expect(throws: ATSyntaxError.self) {
      _ = try AtUri("at://did:plc:abc/com.example.record/..")
    }
  }

  @Test func invalidCollectionRejected() {
    #expect(throws: ATSyntaxError.self) {
      _ = try AtUri("at://did:plc:abc/not_a_nsid/1")
    }
  }
}
