# Architecture

## Package graph

```
App/                    (thin xcodeproj/SPM shell; macOS-CI-only)
Packages/
  ATSyntax       🌐  AtUri/DID/NSID/handle/rkey validators
  Lexicons       🌐  GENERATED Codable types (tools/lexicon-codegen) -> vendored swift-atproto runtime
  ATProtoClient  🌐  XRPC transport, PasswordSession, proxy/labeler headers (deps: ATSyntax)
  RichText       🌐  UnicodeString (UTF-8 byte offsets), facet detection
  Moderation     🌐  label interpretation, decisions, muted words
  Preferences    🌐  app.bsky.actor prefs read-modify-write engine
  Domain         🌐  FeedTuner/slicing, url-helpers, link-meta, formatting
  QueryStore     🌐  TanStack-Query-equivalent store
  Persistence    🌐  Keychain + file/SQLite storage
  TestSupport    🌐  fixtures, fake XRPC server, in-memory stores
  DesignSystem   ❌  ALF port (SwiftUI wiring) [Phase 4]
  UIComponents   ❌  shared UI components [Phase 4]
  Features/*/    ❌  one package per feature: Logic 🌐 + Views ❌ [Phase 5]
tools/
  lexicon-codegen/      vendored swift-atproto generator + pinned lexicon snapshot
dev-env-mock/           vendored RN dev-env mock server [Phase 1]
```

🌐 = `swift build && swift test` on Linux (enforced by CI boundary lint: no `import SwiftUI`/`UIKit`).
❌ = macOS-CI-only (ios.yml).

## Dependency rules

- 🌐 packages never import SwiftUI/UIKit, never assume MainActor.
- ❌ packages may depend on 🌐 packages; never the reverse.
- Lexicons is generated — never hand-edit.
- ATProtoClient owns the only `#if canImport(FoundationNetworking)` shim.
