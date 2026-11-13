#!/usr/bin/env bash
# Fail if an SDK's generated code differs from what the generator produces.
# Regenerates from the spec commit recorded in the SDK's sdk-generator.json, so a
# spec change upstream doesn't make this fail; only hand edits to generated paths
# (or a generator change that hasn't been rolled out yet) do.
#
#   scripts/check-drift.sh <language> <sdk-dir>
#   SPEC_FILE=<local openapi.yaml>   use a local spec; its git commit must match
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <language> <sdk-dir>"
lang=$1
sdk=$(cd "$2" && pwd)
[ -f "$sdk/sdk-generator.json" ] || die "$sdk/sdk-generator.json not found; run generate.sh first"
[ -z "$(git -C "$sdk" status --porcelain)" ] || die "$sdk has uncommitted changes"

sha=$(sed -n 's/.*"sha": *"\([^"]*\)".*/\1/p' "$sdk/sdk-generator.json")
[[ $sha =~ ^[0-9a-f]{40}$ ]] || die "recorded spec sha '$sha' isn't a clean commit; regenerate from a committed spec"

if [ -n "${SPEC_FILE:-}" ]; then
  # Local spec (e.g. an unpushed phasetwo-docs branch): it must be the recorded commit.
  "$ROOT/scripts/fetch-spec.sh"
  # shellcheck source=/dev/null
  . "$WORK/spec/source.env"
  [ "$SPEC_SHA" = "$sha" ] || die "SPEC_FILE is at $SPEC_SHA but $sdk was generated from $sha"
  "$ROOT/scripts/generate.sh" "$lang" "$sdk"
else
  SPEC_REF=$sha "$ROOT/scripts/generate.sh" "$lang" "$sdk"
fi

if [ -n "$(git -C "$sdk" status --porcelain)" ]; then
  git -C "$sdk" status --short >&2
  git -C "$sdk" --no-pager diff --stat >&2
  die "generated code in $sdk has drifted. Don't edit generated files: change the spec, an overlay, a template, a config or a patch in phasetwo-sdk-generator instead."
fi
log "no drift: $lang"
