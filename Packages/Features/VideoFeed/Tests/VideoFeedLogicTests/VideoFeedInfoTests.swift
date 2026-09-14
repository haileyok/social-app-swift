import Foundation
import Lexicons
import QueryStore
import SwiftAtproto
import Testing

@testable import VideoFeedLogic

/// The generator metadata read behind the immersive header.
///
/// Ports the `useFeedInfo(feedUri)` read in `src/state/queries/feed.ts` as the
/// video feed's header consumes it.
@Suite("Video feed generator info")
struct VideoFeedInfoTests {
  /// A generator view fixture.
  func generatorView(
    uri: String = VideoFeedConstants.videoFeedURI,
    displayName: String = "The Vids",
    creatorHandle: String = "bsky.app"
  ) -> App.Bsky.FeedDefs_GeneratorView {
    App.Bsky.FeedDefs_GeneratorView(
      cid: FormatString<LexLink>(rawValue: testCID),
      creator: App.Bsky.ActorDefs_ProfileView(
        did: FormatString<SwiftAtproto.DID>(rawValue: "did:plc:creator"),
        handle: FormatString<SwiftAtproto.Handle>(rawValue: creatorHandle)),
      did: FormatString<SwiftAtproto.DID>(rawValue: "did:plc:creator"),
      displayName: displayName,
      indexedAt: FormatString<Date>(rawValue: Fixtures.defaultDate),
      uri: FormatString<ATURI>(rawValue: uri))
  }

  @Test("the model carries the identity, display fields and creator")
  func modelFromView() {
    let info = VideoFeedInfo(generatorView())
    #expect(info.uri == VideoFeedConstants.videoFeedURI)
    #expect(info.displayName == "The Vids")
    #expect(info.creatorHandle == "bsky.app")
    #expect(info.creatorDid == "did:plc:creator")
    #expect(info.isVideoFeedGenerator)
  }

  @Test("an unnamed generator falls back to RN's Feed by <handle> form")
  func displayNameFallback() {
    let info = VideoFeedInfo(generatorView(displayName: ""))
    #expect(info.displayName == "Feed by @bsky.app")
  }

  @Test("a non-video generator is not flagged as a video feed")
  func nonVideoGenerator() {
    let info = VideoFeedInfo(
      generatorView(uri: "at://did:plc:x/app.bsky.feed.generator/cats"))
    #expect(!info.isVideoFeedGenerator)
  }

  @Test("the query reads the generator and holds it under the feedInfo key")
  func queryReadsGenerator() async throws {
    let xrpc = RecordingVideoFeedXrpc()
    xrpc.setGenerators([generatorView()])
    let store = QueryStore()
    let query = VideoFeedInfoQuery(
      store: store, xrpc: xrpc, uri: VideoFeedConstants.videoFeedURI)

    let info = try await query.load()
    #expect(info.displayName == "The Vids")
    #expect(xrpc.calls == [.feedGenerator(feed: VideoFeedConstants.videoFeedURI)])

    // The read is cached: a second load does not refetch.
    _ = try await query.load()
    #expect(xrpc.calls.count == 1)

    // A forced load does.
    _ = try await query.load(force: true)
    #expect(xrpc.calls.count == 2)
  }

  @Test("a missing generator surfaces as the package's error")
  func missingGenerator() async {
    let query = VideoFeedInfoQuery(
      store: QueryStore(), xrpc: RecordingVideoFeedXrpc(), uri: "at://did:plc:x/missing")
    await #expect(throws: (any Error).self) {
      try await query.load()
    }
  }

  @Test("the package error strings describe the failure")
  func errorDescriptions() {
    #expect(
      VideoFeedError.invalidDescriptor("nonsense").errorDescription?.contains("nonsense") == true)
    #expect(
      VideoFeedError.missingGenerator(uri: "at://x").errorDescription?
        .contains("at://x") == true)
  }

  @Test("an invalid descriptor error equals itself and differs by argument")
  func errorEquality() {
    #expect(VideoFeedError.invalidDescriptor("a") == VideoFeedError.invalidDescriptor("a"))
    #expect(VideoFeedError.invalidDescriptor("a") != VideoFeedError.invalidDescriptor("b"))
  }
}
