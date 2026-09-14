import ATProtoClient
import Foundation
import Lexicons

/// A suggested account, reduced to what the onboarding step acts on.
///
/// The generated `App.Bsky.ActorDefs_ProfileView` carries a dozen fields the
/// step does not touch. Projecting it here keeps the step logic free of the
/// generated types and makes the fakes trivial.
public struct SuggestedUser: Sendable, Equatable, Hashable, Identifiable {
  /// The account's DID.
  public let did: String
  /// The account's handle.
  public let handle: String
  /// The account's display name, when set.
  public let displayName: String?
  /// The DID of the viewer's follow record, when the viewer already follows.
  public let viewerFollowing: String?
  /// Whether the viewer has blocked, or is blocked by, this account.
  public let isBlockedOrBlocking: Bool
  /// Whether the viewer has muted this account.
  public let isMuted: Bool

  /// Identity for collections.
  public var id: String { did }

  /// Creates a suggested user.
  public init(
    did: String,
    handle: String,
    displayName: String? = nil,
    viewerFollowing: String? = nil,
    isBlockedOrBlocking: Bool = false,
    isMuted: Bool = false
  ) {
    self.did = did
    self.handle = handle
    self.displayName = displayName
    self.viewerFollowing = viewerFollowing
    self.isBlockedOrBlocking = isBlockedOrBlocking
    self.isMuted = isMuted
  }
}

/// The suggested-users page.
public struct SuggestedUsersPage: Sendable, Equatable {
  /// The suggested accounts.
  public let actors: [SuggestedUser]
  /// The recommendation id, for metrics.
  public let recID: String?

  /// Creates a page.
  public init(actors: [SuggestedUser], recID: String? = nil) {
    self.actors = actors
    self.recID = recID
  }
}

/// A suggested starter pack, reduced to what the step acts on.
public struct SuggestedStarterPack: Sendable, Equatable, Hashable, Identifiable {
  /// The starter pack record's AT URI.
  public let uri: String
  /// The starter pack record's CID.
  public let cid: String
  /// The list the pack follows.
  public let listURI: String?
  /// The pack's name.
  public let name: String
  /// The feed URIs the pack pins.
  public let feedURIs: [String]

  /// Identity for collections.
  public var id: String { uri }

  /// Creates a suggested starter pack.
  public init(
    uri: String, cid: String, listURI: String? = nil, name: String, feedURIs: [String] = []
  ) {
    self.uri = uri
    self.cid = cid
    self.listURI = listURI
    self.name = name
    self.feedURIs = feedURIs
  }
}

/// Fetches onboarding suggestions.
///
/// The seam exists so step orchestration can be tested without scripted HTTP,
/// while ``LiveOnboardingSuggestionService`` remains the thing that actually
/// speaks the endpoints. Both are exercised: the live implementation is tested
/// against a scripted transport (asserting the exact XRPC calls), the fakes
/// against the step logic.
public protocol OnboardingSuggestionService: Sendable {
  /// `app.bsky.unspecced.getSuggestedOnboardingUsers`.
  func suggestedUsers(
    category: String?, limit: Int, interests: [String]
  ) async throws -> SuggestedUsersPage

  /// `app.bsky.unspecced.getSuggestedOnboardingStarterPacks`.
  func suggestedStarterPacks(
    limit: Int, interests: [String]
  ) async throws -> [SuggestedStarterPack]
}

/// The live implementation, over an appview client.
///
/// Both endpoints are appview reads, so the client must be the proxied
/// appview client (RN: `useAppviewClient`). The interest header is applied to
/// a copy of that client rather than to every request, matching RN's
/// per-call `headers` option.
public struct LiveOnboardingSuggestionService: OnboardingSuggestionService {
  private let client: XrpcClient
  /// The `Accept-Language` value RN sends alongside the topics header.
  private let acceptLanguage: String?

  /// Creates the service.
  public init(client: XrpcClient, acceptLanguage: String? = nil) {
    self.client = client
    self.acceptLanguage = acceptLanguage
  }

  public func suggestedUsers(
    category: String?, limit: Int, interests: [String]
  ) async throws -> SuggestedUsersPage {
    let scoped = headerScoped(interests: interests)
    let output: App.Bsky.UnspeccedGetSuggestedOnboardingUsers_Output = try await scoped.get(
      "app.bsky.unspecced.getSuggestedOnboardingUsers",
      params: [("category", category), ("limit", String(limit))])
    let actors = output.actors.map { profile in
      SuggestedUser(
        did: profile.did.rawValue,
        handle: profile.handle.rawValue,
        displayName: profile.displayName,
        viewerFollowing: profile.viewer?.following?.rawValue,
        isBlockedOrBlocking: (profile.viewer?.blocking != nil)
          || (profile.viewer?.blockedBy ?? false),
        isMuted: profile.viewer?.muted ?? false)
    }
    // RN prefers recIdStr and falls back to the deprecated recId.
    return SuggestedUsersPage(actors: actors, recID: output.recIdStr ?? output.recId)
  }

  public func suggestedStarterPacks(
    limit: Int, interests: [String]
  ) async throws -> [SuggestedStarterPack] {
    let scoped = headerScoped(interests: interests)
    let output: App.Bsky.UnspeccedGetOnboardingSuggestedStarterPacks_Output = try await scoped.get(
      "app.bsky.unspecced.getOnboardingSuggestedStarterPacks",
      params: [("limit", String(limit))])
    return output.starterPacks.map { view in
      // RN reads the name only after narrowing the record with `isType`; a
      // pack whose record failed to narrow renders without a name.
      let narrowed = Self.starterPackRecord(view.record)
      return SuggestedStarterPack(
        uri: view.uri.rawValue,
        cid: view.cid.rawValue,
        listURI: view.list?.uri.rawValue,
        name: narrowed?.name ?? "",
        feedURIs: (view.feeds ?? []).map(\.uri.rawValue))
    }
  }

  /// Narrows a starter-pack view's record to the typed record, or nil.
  private static func starterPackRecord(_ value: UnknownATPValue) -> App.Bsky.GraphStarterpack? {
    guard case .record(let record) = value else { return nil }
    return record as? App.Bsky.GraphStarterpack
  }

  /// A copy of the client with the topic (and language) headers merged in.
  ///
  /// `withHeaders` replaces the whole header set, so the session's own headers
  /// (notably `Authorization`) are merged back in rather than dropped.
  private func headerScoped(interests: [String]) -> XrpcClient {
    var headers = client.extraHeaders
    for (key, value) in OnboardingQueryKeys.topicsHeader(interests) {
      headers[key] = value
    }
    if let acceptLanguage {
      headers["Accept-Language"] = acceptLanguage
    }
    return client.withHeaders(headers)
  }
}
