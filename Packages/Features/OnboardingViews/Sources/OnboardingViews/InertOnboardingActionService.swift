import ATProtoClient
import Foundation
import OnboardingLogic
import Preferences

/// An action service that performs no writes.
///
/// Used when a wizard is rendered without a session: every step's write is a
/// no-op, so the screens can be driven (and captured) without a network. The
/// step runner still runs its validation first, so the local rules behave
/// exactly as they do against the live service.
public struct InertOnboardingActionService: OnboardingActionService {
  /// Creates the service.
  public init() {}

  public func currentDID() async throws -> String { "did:plc:preview" }

  public func uploadAvatar(data: Data, mimeType: String) async throws -> OnboardingBlobRef {
    OnboardingBlobRef(ref: "bafkreipreview", mimeType: mimeType, size: data.count)
  }

  public func upsertProfile(
    avatar: OnboardingBlobRef?, displayName: String, joinedViaStarterPack: StarterPackRef?
  ) async throws {}

  public func createFollows(
    dids: [String], via: StarterPackRef?
  ) async throws -> [String: String] {
    var out: [String: String] = [:]
    for did in dids {
      out[did] = "at://\(did)/app.bsky.graph.follow/preview"
    }
    return out
  }

  public func setInterests(tags: [String]) async throws {}

  public func setAdultContentEnabled(_ enabled: Bool) async throws {}

  public func overwriteSavedFeeds(_ feeds: [SavedFeed]) async throws {}

  public func upsertNux(id: String, completed: Bool, data: String?) async throws {}

  public func getStarterPack(uri: String) async throws -> StarterPackDetail {
    StarterPackDetail(
      ref: StarterPackRef(uri: uri, cid: "bafkreipreview"), listURI: nil, feedURIs: [])
  }

  public func getListMemberDIDs(listURI: String) async throws -> [String] { [] }
}

extension OnboardingViewDependencies {
  /// A preferences engine with no session, for a wizard rendered without one.
  ///
  /// The onboarding step runner requires a ``PreferencesEngine`` even for steps
  /// that never touch preferences, so the debug entry point and the previews
  /// build one over an inert transport rather than carrying the real one.
  public static func defaultPreferencesEngine() -> PreferencesEngine {
    PreferencesEngine(
      client: XrpcClient(baseURL: "https://preview.invalid", transport: InertTransport()))
  }
}

/// A transport that fails every request.
///
/// The preferences engine built over it is never used for a write in the
/// preview path, so failing loudly is the correct behaviour: a screen that
/// unexpectedly needs preferences surfaces the mistake rather than silently
/// succeeding against a fake.
public struct InertTransport: HTTPTransport {
  /// Creates the transport.
  public init() {}

  public func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    throw XrpcError(rawCode: nil, message: "no transport in preview", status: -1)
  }
}
