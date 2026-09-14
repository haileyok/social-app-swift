# AGENTS.md — social-app-swift

Agent conventions for this repo. Read alongside the global `~/.config/` AGENTS.md; this file wins on conflict.

## What this repo is

A native Swift/SwiftUI rewrite of the Bluesky social app (the React Native repo at `~/bluesky/social-app` is **read-only reference** — never modify it). Everything here is developed and verified from a Linux workstation, with free GitHub Actions macOS runners for UI builds.

## The Linux/UI boundary

The package boundary *is* the platform boundary:

- **🌐 packages** (Linux-verifiable): ATSyntax, Lexicons, ATProtoClient, RichText, Moderation, Preferences, Domain, QueryStore, Persistence, DesignTokens, TestSupport, and all `Features/*/Logic` targets. These must:
  - build and test with `swift build && swift test` on Linux
  - never `import SwiftUI` or `import UIKit` (CI boundary-lint enforces this)
  - stay `defaultIsolation: nonisolated` (no MainActor dependency)
- **❌ packages** (macOS-CI-only): DesignSystem, UIComponents, all `Features/*/Views` targets, and `App/`. SwiftUI allowed here. Verified by `ios.yml` only.

The ONE `#if canImport(FoundationNetworking)` shim lives in ATProtoClient. No other package does platform networking shims.

## Toolchain (Linux)

**Method (recorded after Phase 0 spike): TBD — fill in once the spike lands.**

CI runs the exact same Swift major.minor in a pinned `swift:6.3` Docker container. Version pairing local↔CI must be recorded here; if you bump one, bump both.

## Workflow conventions

- **Worktrees**: work from `~/worktrees/social-app-swift/<slug>` on branch `hailey/<slug>`. Never leave the primary checkout dirty. Branch from freshly fetched `origin/main`.
- **Definition of done for a push**: Linux CI green (build + tests + lint for touched 🌐 packages). macOS CI is async; failures spawn follow-up fixes, never merge blockers.
- **One feature package per branch at a time** — no parallel agents on the same package.
- **`Packages/Lexicons` is generated code.** Never hand-edit it. Regeneration is a dedicated task: bump the pinned lexicon snapshot, re-run `tools/lexicon-codegen`, commit the diff. CI re-runs codegen and fails on a non-clean diff.
- **Golden files** (`tools/golden-gen` outputs) are generated from the TS engines, never hand-written. Same idempotency discipline as lexicons.
- **Screenshots**: every `ios.yml` run uploads simulator screenshots as artifacts. These are the visual review loop — check them when a Views target changes.
- **pbxproj rule**: `App/*.xcodeproj` changes only for targets/schemes/build-settings. All source files live in packages — no agent ever hand-edits pbxproj to add code files.
- **License hygiene**: IcySky is AGPL-3.0 — read for reference, never copy. ATProtoKit/Petrel are MIT — read, don't depend. Codegen from CC-BY lexicon JSON is fine.

## CI

- `linux.yml` (required): pinned `swift:6.3` container — per-🌐-package build+test, swiftlint, swift-format lint, jq validation of `.xcstrings`, boundary-lint (no SwiftUI/UIKit imports under 🌐 paths), lexicon codegen idempotency (`git diff --exit-code Packages/Lexicons` after regeneration).
- `ios.yml` (non-blocking): `macos-26`, pinned `DEVELOPER_DIR`, single pinned iPhone simulator, `CODE_SIGNING_ALLOWED=NO`, path-filtered to `App/`, `DesignSystem/`, `UIComponents/`, `Features/**/Views`, `.xcodeproj`, and the workflow itself. Uploads `.xcresult` + screenshots.

## Testing philosophy

- Port TS test files 1:1 wherever they exist in the RN repo (`*.test.ts` under `src/lib/api/`, `src/lib/strings/`, etc.).
- Golden-file tests are ground truth for ported engines (moderation decisions, richtext byte math, feed slicing).
- Each feature package keeps a `tests-ported.md` manifest mapping TS test cases to named Swift tests.

## Useful paths

| Purpose | Location |
|---|---|
| Reference RN app | `~/bluesky/social-app` (read-only) |
| @bsky/sdk source (moderation/richtext engines) | `node_modules/@bsky/sdk` in the RN repo or npm |
| Lexicon JSON snapshot (pinned) | `tools/lexicon-codegen/lexicons/` |
| Generated Swift lexicon types | `Packages/Lexicons` |
| Parity audit | `docs/parity-audit.md` (Phase 6) |
