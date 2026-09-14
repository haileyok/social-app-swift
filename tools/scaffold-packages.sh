#!/bin/bash
# Scaffold the SPM package graph per the Phase 0 plan.
# Idempotent: creates missing packages only, never overwrites existing content.
#
# The Linux/UI boundary is the module boundary:
#   Linux-verifiable: ATSyntax, Lexicons, ATProtoClient, RichText, Moderation,
#     Preferences, Domain, QueryStore, Persistence, TestSupport,
#     Features/*/Logic targets
#   macOS-CI-only: DesignSystem, UIComponents, Features/*/Views targets, App/
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

mkpkg() { # name, target-deps (comma string), [package-deps lines...]
  local name="$1"
  local target_deps="$2"; shift 2
  local dir="Packages/$name"
  if [ -d "$dir/Sources" ] && ls "$dir"/Sources/*/ >/dev/null 2>&1 && [ -n "$(ls -A "$dir"/Sources/*/ 2>/dev/null | grep -v Placeholder)" ]; then
    echo "skip $name (has sources)"
    return
  fi
  mkdir -p "$dir/Sources/$name" "$dir/Tests/${name}Tests"
  {
    echo '// swift-tools-version: 6.3'
    echo 'import PackageDescription'
    echo ''
    echo 'let package = Package('
    echo "  name: \"$name\","
    echo '  defaultLocalization: "en",'
    echo '  products: ['
    echo "    .library(name: \"$name\", targets: [\"$name\"])"
    echo '  ],'
    if [ "$#" -gt 0 ]; then
      echo '  dependencies: ['
      for d in "$@"; do echo "    $d"; done
      echo '  ],'
    fi
    echo '  targets: ['
    echo "    .target(name: \"$name\", dependencies: [$target_deps]),"
    echo "    .testTarget(name: \"${name}Tests\", dependencies: [\"$name\"]),"
    echo '  ]'
    echo ')'
  } > "$dir/Package.swift"
  { echo '// Placeholder so the empty package builds; replaced in implementation phases.'
    echo "public enum ${name}Placeholder {}"
  } > "$dir/Sources/$name/Placeholder.swift"
  echo "created $name"
}

P() { echo ".package(path: \"../$1\")"; }

# --- leaf packages ---
mkpkg ATSyntax ""
mkpkg Domain ""
mkpkg QueryStore ""
mkpkg Persistence ""
mkpkg RichText ""
mkpkg Moderation ""
mkpkg Preferences ""

# --- transport (Lexicons already exists from the codegen milestone) ---
mkpkg ATProtoClient "\"ATSyntax\"" "$(P ATSyntax)"

# --- test support (depends on the packages it provides fakes for) ---
mkpkg TestSupport ""

echo "package graph scaffolded."
