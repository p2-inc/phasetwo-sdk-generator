#!/usr/bin/env bash
# Describe how the spec changed since an SDK was last generated, for the bot PR.
#
#   scripts/spec-diff.sh <sdk-dir> <out-dir>
#
# Run after generate.sh. Compares the spec commit recorded in the SDK's
# sdk-generator.json on its default branch (i.e. before this regeneration) with the
# spec in .work/spec/openapi.yaml. Writes <out-dir>/changelog.md and
# <out-dir>/semver (minor if oasdiff finds breaking changes, otherwise patch).
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <sdk-dir> <out-dir>"
sdk=$(cd "$1" && pwd)
out=$2
mkdir -p "$out" "$WORK/diff"

oasdiff() {
  docker run --rm -v "$WORK/diff:/specs" "tufin/oasdiff:$OASDIFF_VERSION" "$@"
}

old_sha=$(git -C "$sdk" show HEAD:sdk-generator.json 2>/dev/null \
  | sed -n 's/.*"sha": *"\([^"]*\)".*/\1/p' || true)
cp "$WORK/spec/openapi.yaml" "$WORK/diff/new.yaml"

if [[ ! $old_sha =~ ^[0-9a-f]{40}$ ]]; then
  echo "No previous spec commit recorded in sdk-generator.json, so there is no spec diff." > "$out/changelog.md"
  echo minor > "$out/semver"
  exit 0
fi

curl -fsSL -o "$WORK/diff/old.yaml" "https://raw.githubusercontent.com/$SPEC_REPO/$old_sha/$SPEC_PATH"
{
  echo "Spec changes since [\`${old_sha:0:7}\`](https://github.com/$SPEC_REPO/blob/$old_sha/$SPEC_PATH):"
  echo
  oasdiff changelog /specs/old.yaml /specs/new.yaml --format markdown || true
} > "$out/changelog.md"

# Breaking for the API, or a removed tag (tags become SDK class names, so removing
# or renaming one breaks SDK users even though the HTTP API is unchanged).
if ! oasdiff breaking /specs/old.yaml /specs/new.yaml --fail-on ERR > /dev/null \
  || grep -Eq "API tag \`[^\`]+\` removed" "$out/changelog.md"; then
  echo minor > "$out/semver"
else
  echo patch > "$out/semver"
fi
log "spec diff: $(cat "$out/semver") ($old_sha -> new)"
