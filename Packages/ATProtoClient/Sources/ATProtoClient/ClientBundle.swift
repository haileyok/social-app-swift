import Foundation

/// Addresses of Bluesky-operated services (port of @bsky/sdk api.js).
public enum BlueskyAPI {
  public static let appDid = "did:web:api.bsky.app"
  public static let appService = "did:web:api.bsky.app#bsky_appview"
  public static let appURL = "https://api.bsky.app"
  public static let appURLPublic = "https://public.api.bsky.app"
  public static let chatDid = "did:web:api.bsky.chat"
  public static let chatService = "did:web:api.bsky.chat#bsky_chat"
  public static let chatURL = "https://api.bsky.chat"
  public static let moderationDid = "did:plc:ar7c4by46qjdydhdevvrndac"
  public static let moderationService =
    "did:plc:ar7c4by46qjdydhdevvrndac#atproto_labeler"
  public static let notifService = "did:web:api.bsky.app#bsky_notif"
}

/// Per-country additional labeler DIDs (port of
/// additional-moderation-authorities.ts; used by Moderation too).
public enum CountryLabelers {
  public static let br = "did:plc:ekitcvx7uwnauoqy5oest3hm"
  public static let de = "did:plc:r55ow3tocux5kafs5dq445fy"
  public static let ru = "did:plc:crm2agcxvvlj6hilnjdc4hox"
  public static let gb = "did:plc:gvkp7euswjjrctjmqwhhfzif"
  public static let au = "did:plc:dsynw7isrf2eqlhcjx3ffnmt"
  public static let tr = "did:plc:cquoj7aozvmkud2gifeinkda"
  public static let jp = "did:plc:vhgppeyjwgrr37vm4v6ggd5a"
  public static let es = "did:plc:zlbbuj5nov4ixhvgl3bj47em"
  public static let pk = "did:plc:zrp6a3tvprrsgawsbswbxu7m"
  public static let `in` = "did:plc:srr4rdvgzkbx6t7fxqtt6j5t"
  public static let eu = "did:plc:z57lz5dhgz2dkjogoysm3vut"

  /// Country code -> labeler DIDs (nil = default all).
  public static func labelers(forCountry country: String?) -> [String] {
    guard let country else {
      return allCountryLabelers
    }
    switch country {
    case "BR": return [br]
    case "RU": return [ru]
    case "GB": return [gb]
    case "AU": return [au]
    case "TR": return [tr]
    case "JP": return [jp]
    case "PK": return [pk]
    case "IN": return [`in`]
    case "DE": return [eu, de]
    case "ES": return [eu, es]
    case "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "GR",
      "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO",
      "SK", "SI", "SE":
      return [eu]
    default: return []
    }
  }

  static let allCountryLabelers: [String] = [
    br, de, ru, gb, au, tr, jp, es, pk, `in`, eu,
  ]
}

/// Assembles `atproto-accept-labelers` values.
public enum LabelerHeader {
  /// The app labeler, always listed with `;redact` (the global static
  /// posture: `Client.appLabelers` emits redacted entries).
  public static func appLabelers(country: String?) -> [String] {
    var out = [BlueskyAPI.moderationDid + ";redact"]
    for did in CountryLabelers.labelers(forCountry: country) {
      out.append(did + ";redact")
    }
    return out
  }

  /// Account-subscribed labelers (unredacted), with the Bluesky moderation
  /// DID filtered out — it already flows through the global redacted list
  /// and duplicating it would key differently (port of
  /// applyLabelersToClient's filter).
  public static func subscribedLabelers(_ dids: [String]) -> [String] {
    dids.filter { $0 != BlueskyAPI.moderationDid }
  }
}

/// The per-account client bundle: session + the three routed clients
/// (port of clients.ts session bundle).
public struct SessionClients: Sendable {
  public let session: PasswordSession
  public let transport: HTTPTransport

  /// The signed-in appview client (`atproto-proxy: <did>#bsky_appview`).
  public let appview: XrpcClient
  /// The account-host PDS client (no proxy, labelers suppressed).
  public let pds: XrpcClient
  /// The chat client (`atproto-proxy: <did>#bsky_chat`), carries labelers.
  public let chat: XrpcClient

  public init(
    session: PasswordSession, transport: HTTPTransport,
    appviewProxyService: String = BlueskyAPI.appService,
    chatProxyService: String = BlueskyAPI.chatService,
    appLabelers: [String], subscribedLabelers: [String]
  ) async {
    self.session = session
    self.transport = transport
    let base = try? await session.client()
    let baseURL = base?.baseURL ?? ""
    let auth = base?.extraHeaders ?? [:]

    let labelerList =
      appLabelers + LabelerHeader.subscribedLabelers(subscribedLabelers)

    self.appview = XrpcClient(
      baseURL: baseURL, proxyService: appviewProxyService,
      labelers: labelerList, extraHeaders: auth, transport: transport)
    self.pds = XrpcClient(
      baseURL: baseURL, proxyService: nil, labelers: nil,
      extraHeaders: auth, transport: transport)
    self.chat = XrpcClient(
      baseURL: baseURL, proxyService: chatProxyService,
      labelers: labelerList, extraHeaders: auth, transport: transport)
  }
}

/// The logged-out public client (public appview, app labelers incl.
/// `;redact` on the Bluesky authority).
public struct PublicClients: Sendable {
  public let appview: XrpcClient

  public init(transport: HTTPTransport, country: String? = nil) {
    self.appview = XrpcClient(
      baseURL: BlueskyAPI.appURLPublic, proxyService: nil,
      labelers: LabelerHeader.appLabelers(country: country),
      transport: transport)
  }
}

/// Thrown when a write/auth-only client is used with no active session
/// (port of NotAuthenticatedError).
public struct NotAuthenticatedError: Error, Sendable {
  public let operation: String
  public init(_ operation: String) {
    self.operation = operation
  }
}
