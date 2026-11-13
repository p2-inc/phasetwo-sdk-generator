#!/usr/bin/env bash
# Describe how the spec changed since an SDK was last generated, for the bot PR.
#
#   scripts/spec-diff.sh <sdk-dir> <out-dir>
#
# Run after generate.sh. Compares the SDK's sdk-generator.json on its default branch
# (i.e. before this regeneration) with the regenerated one, and the old spec with
# .work/spec/openapi.yaml. Writes:
#   <out-dir>/changelog.md  oasdiff changelog
#   <out-dir>/semver        minor if the API version's major.minor changed (the SDK
#                           releases <major>.<minor>.0), otherwise patch
#   <out-dir>/release       the version line for the PR body
#   <out-dir>/breaking      "true" if the change breaks SDK users
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <sdk-dir> <out-dir>"
sdk=$(cd "$1" && pwd)
out=$2
mkdir -p "$out" "$WORK/diff"

oasdiff() {
  docker run --rm -v "$WORK/diff:/specs" "tufin/oasdiff:$OASDIFF_VERSION" "$@"
}

json_field() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\\1/p"; }
old_json=$(git -C "$sdk" show HEAD:sdk-generator.json 2>/dev/null || true)
old_sha=$(json_field sha <<< "$old_json")
old_api=$(json_field apiVersion <<< "$old_json")
new_api=$(json_field apiVersion < "$sdk/sdk-generator.json")
cp "$WORK/spec/openapi.yaml" "$WORK/diff/new.yaml"

if [ "${old_api%.*}" != "${new_api%.*}" ]; then
  echo minor > "$out/semver"
  echo "Releases **${new_api%.*}.0** (API version ${old_api:-none} → $new_api)." > "$out/release"
else
  echo patch > "$out/semver"
  echo "Releases the next **${new_api%.*}.x** patch (API version unchanged at $new_api)." > "$out/release"
fi

echo false > "$out/breaking"
if [[ ! $old_sha =~ ^[0-9a-f]{40}$ ]]; then
  echo "No previous spec commit recorded in sdk-generator.json, so there is no spec diff." > "$out/changelog.md"
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
  echo true > "$out/breaking"
fi
log "spec diff: $(cat "$out/semver"), breaking=$(cat "$out/breaking") ($old_api -> $new_api)"
