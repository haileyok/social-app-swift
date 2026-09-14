# golden-gen

Generates **golden fixture files** by running the pinned TypeScript moderation
and richtext engines over checked-in fixture inputs. Output is committed to
`Packages/TestSupport/Fixtures/Golden/` and consumed by the Swift
`Moderation` and `RichText` port test suites (plan AC.4).

## Why

The Swift ports of the moderation decision engine and the richtext facet
engine must behave exactly like the TypeScript originals. To make that
verifiable, we run the real TS engine (`@bsky/sdk`) over a shared set of
fixtures and commit its outputs. The Swift suites then replay the inputs
through the Swift engine and compare against the golden outputs — proving
parity with something stronger than hand-written expectations.

## Pin

`package.json` pins `@bsky/sdk` to **1.1.0** — the exact version the RN
social-app pins in its own `package.json`. Do not bump it casually: bumping
changes engine behavior and should be a deliberate regeneration that ships
together with the matching Swift changes.

## Layout

- `fixtures/moderation.mjs` — moderation cases built with the SDK's own
  `mock.*` subject builders (valid lexicon shapes) plus hand-built
  `ModerationOpts`. All timestamps/DIDs are fixed; nothing here may use
  `Date.now()` or randomness, or output stops being reproducible.
- `fixtures/richtext.mjs` — plain strings, heavy on emoji/CJK/combining
  characters (UTF-8 byte-offset math is the point).
- `generate.mjs` — runs the engines, projects decisions (`causes`,
  per-context `ui()` for every `ModerationBehavior` context, downgrade
  before/after) and facet output (`byteStart`/`byteEnd`, features, segments,
  grapheme/utf16 lengths), writes deterministic JSON.

Each golden case contains **both** the serialized engine input and the
expected output, so the Swift tests are self-contained and need no TS
tooling at test time.

## Regenerate

```sh
cd tools/golden-gen
npm ci
npm run generate
git diff -- Packages/TestSupport/Fixtures/Golden   # from repo root
```

CI (`golden-idempotency` job in `linux.yml`) regenerates and requires a
diff-clean tree, so the golden files always provably come from the TS engine
— never hand-edited, never drifting from the fixtures.

## Adding cases

Add a case to the relevant `fixtures/*.mjs` file, run `npm run generate`,
and commit both the fixture change and the regenerated goldens together.
Golden files are never edited by hand.
