# Lexicon codegen

Generates `Packages/Lexicons` (Swift Codable types for the atproto/Bluesky XRPC API) from canonical lexicon JSON.

## Components

- **`swift-atproto/`** — vendored copy of [nnabeyang/swift-atproto](https://github.com/nnabeyang/swift-atproto) (MIT), pinned at commit `087fa02620d529733c40e5d5b07b7a3fed1987b2` (2026-08-26). Pure Swift (swift-syntax based); builds and runs on Linux. The generated types depend on its small `SwiftAtproto` runtime module (protocols, `FormatString` wrappers, `UnknownRecord` for open unions), vendored alongside.
- **`lexicon-deps/atproto-repo/`** — **pinned snapshot** of canonical lexicon JSON from [bluesky-social/atproto](https://github.com/bluesky-social/atproto), extracted with `git archive` at commit `2e1787c2bf5bd47b55c3df930d688bb40b5ae63d`. Lexicon JSON is CC-BY (Bluesky PBC); attribution preserved here.
- **`regenerate.sh`** — resolves the config, builds the generator, regenerates output.

## Regenerating

```bash
tools/lexicon-codegen/regenerate.sh
```

Then review `git diff Packages/Lexicons` and commit. **Never hand-edit `Packages/Lexicons`.**

CI enforces idempotency: re-running generation must produce a diff-clean tree.

## Bumping the pinned snapshot

1. In a local checkout of `bluesky-social/atproto`, note the target commit `C`.
2. `git -C /path/to/atproto archive C lexicons | tar -x -C lexicon-deps/atproto-repo` (replacing the existing tree).
3. Update the `state.revision` in `regenerate.sh`'s embedded config (`.atproto.json` content) to `C` — note the script writes `.atproto.resolved.json` at run time; the revision string is documentation of the pin. Keep the two in sync.
4. Run `regenerate.sh`, review the diff (schema changes are often breaking — expect downstream compile fixes in dependent packages), commit.
5. Record the new pin commit in this README.

Current pins:

| Component | Repo | Commit |
|---|---|---|
| Generator | nnabeyang/swift-atproto | `087fa02620d529733c40e5d5b07b7a3fed1987b2` |
| Lexicons | bluesky-social/atproto | `2e1787c2bf5bd47b55c3df930d688bb40b5ae63d` |

## Notes

- **Client-relevant allowlist**: the RN app ships its own lexicon manifest at `lexicons.json` (266 entries) — the authoritative client-relevant set. `regenerate.sh` selects the namespaces covering every entry in that manifest: `app.bsky.*`, `chat.bsky.*`, `com.atproto.*`, `com.germnetwork.*` (only `com.germnetwork.declaration`, read/written as a record by the Germ profile button), and `tools.ozone.report.*` (used by the report dialog) — plus the **transitive closure of cross-namespace refs** (e.g. `tools.ozone.report.defs` refs `tools.ozone.team.defs#member`, so that schema is pulled in automatically). Generating the full snapshot is not possible today: server-side lexicons trip generator bugs (a malformed cross-schema array ref in `tools.ozone.moderation.getAccountPreferences`), and the client never uses them.
- Verified equivalence (2026-09): all 266 RN-manifest NSIDs exist in the pinned snapshot, and the allowlist selects 336 schemas, superset of all 266. The 70 extra schemas are `app.bsky.auth*` permission-set lexicons, the `app.bsky.unspecced.*`/`app.bsky.video.*`/`com.atproto.temp.*` client endpoints, and transitive ref-closure additions (`tools.ozone.moderation.defs`, `tools.ozone.queue.defs`, `tools.ozone.team.defs`).
- `app.bsky.video.uploadPart` is excluded: its `application/octet-stream` input mimetype the vendored generator's lexicon decoder rejects; blob upload goes through `ATProtoClient`'s raw multipart transport instead of a typed procedure.
- Generated output: two files — `XRPCAPIClient.swift` (all types + client method surface) and `UnknownATPValue.swift`. The generated client method surface (the `XRPCCallable` protocol + extensions) is *not* the transport — that's `ATProtoClient`'s job; the generated code provides typed request/response structs.
- **Idempotency** is verified (regenerate → identical hashes) and enforced by CI.
