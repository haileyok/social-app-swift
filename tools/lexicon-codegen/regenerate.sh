#!/bin/bash
# Regenerate Packages/Lexicons/Sources/Lexicons from the pinned lexicon snapshot.
# NEVER hand-edit generated output. Run this, review the diff, commit.
set -euo pipefail
cd "$(dirname "$0")"

REPO_ROOT="$(cd ../.. && pwd)"
OUT_DIR="$REPO_ROOT/Packages/Lexicons/Sources/Lexicons"

# Resolve the local dependency to an absolute file:// URL (required for local
# deps) and apply the client-relevant namespace allowlist.
#
# Allowlist curated from the RN app's actual lexicon usage. Two sources agree:
# (1) the app's own generated manifest (bluesky/social-app `lexicons.json`,
#     266 entries), which is the authoritative client-relevant set, and
# (2) a grep of src/ for `client.call(app.bsky.*)`-style method references.
# Roots below cover every manifest entry except com.germnetwork.declaration,
# which is listed explicitly. Server-side namespaces (the rest of tools.ozone.*,
# internal.*, site.*) are excluded - the full set also trips a generator bug on
# tools.ozone.moderation.getAccountPreferences' cross-schema array reference, so
# the allowlist is required, not optional.
#
# Also excluded: app.bsky.video.uploadPart - its "application/octet-stream"
# input mimetype the vendored generator's lexicon decoder rejects; blob upload
# goes through ATProtoClient's raw multipart transport instead.
#
# .atproto.json keeps the relative location + pinned revision as documentation;
# .atproto.resolved.json is the runnable artifact (gitignored).
DEP_DIR="$(cd lexicon-deps/atproto-repo && pwd)"
python3 - "$DEP_DIR" <<'PY' > .atproto.resolved.json
import json, pathlib, re, sys

dep_dir = sys.argv[1]
root = pathlib.Path(dep_dir, 'lexicons')
# Roots mirror the RN app's own lexicon manifest (bluesky/social-app
# lexicons.json, 266 entries): every namespace the client ships. The only
# out-of-root entry there is com.germnetwork.declaration (read/written as a
# record by the Germ profile button), so that namespace is listed explicitly.
allowed_roots = (
    "app.bsky",
    "chat.bsky",
    "com.atproto",
    "com.germnetwork",
    "tools.ozone.report",
)
exclude = {"app.bsky.video.uploadPart"}

cfg = json.load(open('.atproto.json'))
cfg['dependencies'][0]['location'] = 'file://' + dep_dir

# Load all schemas, then select the allowed set plus the transitive closure of
# cross-namespace refs (a lexicon may ref defs in schemas outside the allowlist
# roots, e.g. tools.ozone.report.defs -> tools.ozone.team.defs#member).
schemas = {}
for p in sorted(root.rglob('*.json')):
    d = json.load(open(p))
    schemas[d['id']] = d

def refs_out(schema):
    """Collect nsid#def refs that point outside this schema."""
    out = set()
    def walk(node):
        if isinstance(node, dict):
            r = node.get('ref')
            if isinstance(r, str) and '#' in r:
                out.add(r.split('#')[0])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(schema)
    return out

selected = set()
queue = []
for nsid, d in schemas.items():
    if nsid in exclude:
        continue
    if nsid.startswith(allowed_roots):
        queue.append(nsid)
while queue:
    nsid = queue.pop()
    if nsid in selected:
        continue
    d = schemas.get(nsid)
    if d is None:
        continue  # ref to a schema not in the snapshot; generator tolerates
    selected.add(nsid)
    for dep in refs_out(d):
        if dep not in selected:
            queue.append(dep)

cfg['dependencies'][0]['lexicons'][0]['nsIds'] = sorted(selected)
json.dump(cfg, sys.stdout, indent=2)
PY

# Build the vendored generator (first run takes a few minutes; cached after).
export PATH="$HOME/swift-toolchains/bin:$PATH"
swift build --package-path swift-atproto --product swift-atproto \
  --scratch-path "$REPO_ROOT/.build/lexicon-codegen"

BIN="$REPO_ROOT/.build/lexicon-codegen/debug/swift-atproto"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
# Install step + generation run against the resolved config.
"$BIN" --atproto-configuration .atproto.resolved.json --outdir "$OUT_DIR"

echo "Generated:"
find "$OUT_DIR" -name '*.swift' | wc -l
echo "Review with: git -C $REPO_ROOT diff Packages/Lexicons"
