# social-app-swift

A native Swift/SwiftUI rewrite of the [Bluesky social app](https://github.com/bluesky-social/social-app) (React Native). Work in progress.

## Status

Early. Follow the phase plan in `docs/plan.md` (when present) — Phase 0 (repo, toolchain, CI bootstrap) is underway.

## Development model

- **All non-UI code builds and tests on Linux.** The Linux/UI boundary is the SPM package boundary: packages marked 🌐 in `docs/architecture.md` must never import SwiftUI/UIKit and must stay `swift build`/`swift test` clean on Linux.
- **UI code is verified in CI only**, on free GitHub Actions `macos-26` runners, via XCUITest + simulator screenshot artifacts. Nobody has a Mac; screenshots in the artifacts are the visual review loop.
- **CI gates**: `linux.yml` is the only required check. `ios.yml` is path-filtered, retryable, and never blocks a merge.

## Dev setup (Linux)

Toolchain installation method is recorded in [AGENTS.md](AGENTS.md). Quick start:

```bash
git clone git@github.com:haileyok/social-app-swift.git
cd social-app-swift
swift build  # requires local Swift toolchain — see AGENTS.md
```

## License notes

- Lexicon JSON sources are CC-BY (Bluesky PBC); generated code from them is fine with attribution (see `tools/lexicon-codegen/README.md`).
- Design tokens are ported from `@bsky.app/alf` (MIT-licensed).
- Inter font is SIL OFL; attribution lives in `Packages/DesignSystem/` docs when vendored.
- **IcySky is AGPL-3.0 — never copy its code into this repo.** Reading it for reference is fine.
