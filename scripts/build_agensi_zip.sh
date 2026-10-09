#!/usr/bin/env bash
#
# Builds the agensi.io upload: one top-level dataforge/ folder with
# packaging/agensi/SKILL.md at its root and the four skills, the manifest
# assets, and the support-desk example beneath it, laid out as in this repo so
# every relative link between skills still resolves.
#
# The tree comes from `git archive`, not the working copy, so local DuckDB
# files, bytecode, build state, and .DS_Store cannot leak into the upload.
#
#   scripts/build_agensi_zip.sh [ref]    # ref defaults to HEAD
#
# Writes dist/dataforge-agensi-<skill_version>.zip.

set -euo pipefail

ref="${1:-HEAD}"
cd "$(dirname "$0")/.."

fail() {
  echo "build-agensi: $1" >&2
  exit 1
}

command -v zip >/dev/null 2>&1 || fail "zip not found on PATH"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bundle="$work/dataforge"
mkdir -p "$bundle"

git archive "$ref" -- \
  skills assets examples/support-desk packaging/agensi/SKILL.md \
  README.md LICENSE CHANGELOG.md \
  | tar -x -C "$bundle"

mv "$bundle/packaging/agensi/SKILL.md" "$bundle/SKILL.md"
rm -rf "$bundle/packaging"

# Agensi rejects binaries; the README image is the only one tracked.
rm -f "$bundle/assets/demo-pr.png"
rm -f "$bundle/skills/forge-builder/.build-state/.gitkeep"

links="$(find "$bundle" -type l)"
[ -z "$links" ] || fail "symlinks in bundle: $links"

stray="$(find "$bundle" -name .DS_Store)"
[ -z "$stray" ] || fail ".DS_Store in bundle: $stray"

binaries=""
while IFS= read -r -d '' file; do
  if [ -s "$file" ] && ! grep -Iq '' "$file"; then
    binaries+="${file#"$work"/}"$'\n'
  fi
done < <(find "$bundle" -type f -print0)
[ -z "$binaries" ] || fail "binary files in bundle:"$'\n'"$binaries"

frontmatter="$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1 { print }' "$bundle/SKILL.md")"
grep -q '^name: dataforge$' <<<"$frontmatter" || fail "root SKILL.md frontmatter has no 'name: dataforge'"
grep -q '^description:' <<<"$frontmatter" || fail "root SKILL.md frontmatter has no description"

version="$(sed -n 's/^skill_version:[[:space:]]*"\([^"]*\)".*/\1/p' "$bundle/assets/dataforge.manifest.seed.example.yaml")"
[ -n "$version" ] || fail "skill_version not found in the seed example manifest"

mkdir -p dist
out="$PWD/dist/dataforge-agensi-$version.zip"
rm -f "$out"
(cd "$work" && zip -rqX "$out" dataforge)

count="$(find "$bundle" -type f | wc -l | tr -d ' ')"
echo "build-agensi: wrote dist/dataforge-agensi-$version.zip ($count files from $(git rev-parse --short "$ref"))"
