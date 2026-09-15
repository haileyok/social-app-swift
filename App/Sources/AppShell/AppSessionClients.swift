import ATProtoClient
import Foundation
import Lexicons
import QueryStore

/**
 The query plumbing a signed-in shell needs: the app's `QueryStore`, the two
 proxy-routed XRPC clients the feature packages expect, and the DID that scopes
 every query key.

 `SessionStore` holds the credentials and `AppSession` owns its lifetime, but
 neither of them knows anything about queries or proxy routing - deliberately,
 so the session layer stays UI-free and dependency-light. The shell, by
 contrast, is exactly the layer that knows the app's clients: the RN app builds
 the same three-client bundle (`appview`, `chat`, and the plain PDS client) in
 `clients.ts` once per account and hands them to every feature.

 Built once per session, lazily, on the main actor the first time the shell
 renders. Rebuilding it would be expensive (a fresh `QueryStore` drops every
 cache) and pointless (the clients are value types over one transport), so the
 shell stores the bundle it built next to the session and reuses it for every
 tab. A sign-out or an account switch tears it down by simply building a new
 shell.

 - Note: labeler headers are not set here. The RN app subscribes the account's
   labelers into every client; until the preferences wiring that reads them
   lands, the clients run with the appview's default posture, which is what the
   fixture and demo paths render today. TODO: feed `Preferences.moderationPrefs`
   labelers into these clients once the shell hydrates preferences.
 */
@MainActor
final class AppSessionClients {
  /// The signed-in account's DID: the scope every query key and moderation
  /// decision is keyed by.
  let did: String

  /// The app's query cache. One store for the whole shell, so every feature
  /// shares entries and subscriptions the way the RN app's one TanStack Query
  /// client does.
  let store: QueryStore

  /// The signed-in appview client (`atproto-proxy` to `#bsky_appview`).
  ///
  /// Feed reads, search, notifications and profile reads all go through it.
  let appview: XrpcClient

  /// The chat client (`atproto-proxy` to `#bsky_chat`), for the messages
  /// feature's XRPC calls.
  let chat: XrpcClient

  /// The plain PDS client (no proxy, no labeler header), for preference reads.
  let pds: XrpcClient

  /**
   Builds the bundle from the session's live `PasswordSession`.

   Async because `PasswordSession` is an actor: the client and identity reads
   are actor-isolated, so the bundle awaits them once at construction. The
   session client already carries the bearer token and points at the
   account's PDS; the routed clients are copies of it with the proxy header the
   RN app's `clients.ts` sets (`SessionClients` builds the same shape, but
   awaits identity resolution at init too - the shell does the same here
   rather than on the render path, since the session has already resolved it).
   */
  init(session: PasswordSession, transport: HTTPTransport) async throws {
    let base = try await session.client()
    let did = try await session.sessionData().did

    self.did = did
    self.store = QueryStore()
    self.appview = base.withProxy(BlueskyAPI.appService)
    self.chat = base.withProxy(BlueskyAPI.chatService)
    self.pds = base
  }
}
