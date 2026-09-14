# check-test-manifest

Verifies that every `Packages/*/tests-ported.md` manifest points at Swift tests
that actually exist.

Each package that ports behavior from the React Native app carries a
`tests-ported.md` that maps ported TS test cases (or upstream semantics) to
*named* Swift tests. Those names are documentation, and documentation rots: a
test gets renamed, a suite is split, a case is deleted, and the manifest keeps
claiming coverage that is no longer there. This script turns the manifest into
something CI can hold the code to.

It checks the **names**. It does not check that a named test really covers the
TS case it claims to cover - that is a human judgement. What it guarantees is
that every name in the manifest resolves to a real test, so the manifest cannot
silently drift into fiction.

## Usage

```sh
# Check every manifest (fast - no build, no test run). This is the CI default.
tools/check-test-manifest

# Check one or more packages
tools/check-test-manifest Domain RichText

# Check one manifest directly
tools/check-test-manifest --manifest Packages/Domain/tests-ported.md

# Show every extracted reference and how it resolved
tools/check-test-manifest --list

# Also run `swift test` per checked package and fail on test failures
tools/check-test-manifest --run

# Treat unresolved bare identifiers as errors too (see "Bare identifiers")
tools/check-test-manifest --strict

# Only print problems and the summary
tools/check-test-manifest --quiet
```

Exit status is `0` when every reference resolves and `1` when any does not.

`--run` needs a Swift toolchain on PATH. If yours lives in the conventional
per-machine location the script finds it automatically; otherwise:

```sh
export PATH="$HOME/swift-toolchains/bin:$PATH"
tools/check-test-manifest --run
```

`--run` is slow (a full `swift test` per package, cold builds included). Use the
default name check in CI on every PR and `--run` on a slower schedule or before
release.

## What it checks

For each manifest, the script:

1. Extracts Swift test-name candidates from the manifest's tables (see below).
2. Builds an index of the package's real tests by scanning `Packages/<Pkg>/Tests`
   for `@Test` functions and the suite types that own them.
3. Resolves each candidate against that index.
4. Reports unresolved candidates as `manifest:line` with the reason, and exits
   nonzero if there are any.

The index is built from the suite *type name* and its `@Suite("display name")`,
not from the file name - a suite's tests often live in a file named after the
behavior rather than the suite (for example `RichTextManipTests` lives in
`RichTextBehaviorTests.swift`). Renaming a file does not break the check;
renaming a suite or a test does, which is the point.

## Manifest conventions

The script reads **markdown tables**. Each table's header row decides which
columns are scanned: a column whose header is `Test`, `Tests`, `Suite`,
`Suites`, `Swift test`, or `Swift suite` (case-insensitive) is a test column.
Every backticked span in that column is treated as a reference.

Tables whose header has no such column are ignored. That is deliberate, so
reference tables like `| TypeScript module | Swift source |` do not produce
noise. It also means a table must have a recognizable test column to be
checked - a manifest whose tables are all unrecognized yields zero references
and **fails** rather than passing vacuously.

### Reference forms

All of these are understood:

| Form | Example | Resolves against |
|---|---|---|
| `Suite.member` | `DateDiffTests.worksWithNumbers` | the named `@Test` func in that suite |
| `Suite.*` | `HydrationTests.*` | suite exists and owns at least one test |
| `Suite.prefix*` | `RichTextManipTests.shortenLinks*` | at least one test in the suite matches |
| `prefix*` | `setContentLabelPref*` | at least one test anywhere in the package matches |
| `Suite` | `URLHelpersTests` | the suite exists |
| `member` | `worksWithNumbers` | a test of that name exists in the package |

A cell may carry several references separated by commas, e.g.
`` `a`, `b`, `c*` `` or `` `FooTests.a`, `b` ``.

### Bare identifiers

Manifests legitimately mention things that are not Swift tests: upstream TS
symbols (`filterAccountLabels`), golden case names (`clean-post`, which are
lowercase and not matched as identifiers), and file names. A bare identifier
with no `.` that does not name a test in the package is therefore a **warning**,
not an error, by default.

`--strict` promotes those to errors. It currently passes across all manifests,
so it is safe to adopt; it is not the default only because it makes the check
brittle against prose that happens to mention an upstream symbol.

Qualified references (`Suite.member`) are always errors when unresolved - there
is no reason for a manifest to name a dotted Swift test that does not exist.

### Keeping the checker honest

Two failure modes are guarded explicitly, because a checker that silently
checks nothing is worse than no checker:

- A manifest that yields **zero** references fails, with a message suggesting
  the format changed.
- A manifest with no recognizable test column in any table also yields zero
  references, and so fails the same way.

If you add a manifest with a different table shape, either give it a `Swift
test` column or teach `is_test_header` in `extract_candidates` the new wording.

## Scope

- Only `Packages/*/tests-ported.md` is discovered by default.
- The script never edits anything; it only reads manifests and package sources.
- `--run` invokes `swift test` in each checked package directory.

## Keeping manifests green

When a manifest reference goes stale the fix is almost always to update the
manifest, not the test. Two honest options:

- The test was renamed: update the name in the manifest.
- The test no longer exists: say so plainly, e.g.
  `**not covered** - no test calls it`, rather than deleting the row. A row that
  records a real coverage gap is more useful than a missing row.

Do not "fix" a stale manifest by editing or renaming Swift tests to match it.
The tests are the ground truth; the manifest describes them.
