#!/usr/bin/env bash
# Regenerate one SDK's generated code inside a checkout of that SDK.
#
#   scripts/generate.sh <java|typescript|python> <path-to-sdk-checkout>
#
# Steps: fetch spec -> apply overlays -> openapi-generator (with template overrides)
# -> sync into the SDK's generated-only paths -> format -> apply patches
# -> write sdk-generator.json. Nothing outside the language's GENERATED_PATHS is
# touched except sdk-generator.json.
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <language> <sdk-dir>"
lang=$1
sdk=$(cd "$2" && pwd)
check_language "$lang"
langdir=$ROOT/languages/$lang
# shellcheck source=/dev/null
. "$langdir/hooks.sh"

"$ROOT/scripts/fetch-spec.sh"
# shellcheck source=/dev/null
. "$WORK/spec/source.env"

build=$WORK/build/$lang
rm -rf "$build" && mkdir -p "$build"

# 1. Overlays: common first, then language-specific.
cp "$WORK/spec/openapi.yaml" "$build/openapi.yaml"
for overlay in "$ROOT/overlays/common.yaml" "$langdir/overlay.yaml"; do
  [ -f "$overlay" ] || continue
  log "overlay: ${overlay#"$ROOT"/}"
  npx --yes "openapi-format@$OPENAPI_FORMAT_VERSION" "$build/openapi.yaml" \
    --overlayFile "$overlay" --no-sort -o "$build/openapi.next.yaml" > "$build/overlay.log" 2>&1 \
    || { cat "$build/overlay.log" >&2; die "applying ${overlay#"$ROOT"/} failed"; }
  mv "$build/openapi.next.yaml" "$build/openapi.yaml"
done

# 2. Generate. A language can bring its own generator by defining run_generator in
#    hooks.sh; otherwise openapi-generator runs (it validates the spec and fails on errors).
if declare -F run_generator > /dev/null; then
  log "generator for $lang"
  run_generator "$build/openapi.yaml" "$build/out" "$langdir" > "$build/generator.log" 2>&1 \
    || { tail -40 "$build/generator.log" >&2; die "generator failed (log: $build/generator.log)"; }
else
  log "openapi-generator $OPENAPI_GENERATOR_VERSION ($GENERATOR_NAME)"
  args=(generate -g "$GENERATOR_NAME"
    -i "$(in_container "$build/openapi.yaml")"
    -o "$(in_container "$build/out")"
    -c "$(in_container "$langdir/config.yaml")")
  if [ -n "$(find "$langdir/templates" -name '*.mustache' 2>/dev/null)" ]; then
    args+=(-t "$(in_container "$langdir/templates")")
  fi
  openapi_generator "${args[@]}" > "$build/generator.log" 2>&1 \
    || { tail -40 "$build/generator.log" >&2; die "openapi-generator failed (log: $build/generator.log)"; }
fi

# 3. Sync into the SDK and format.
log "sync -> $sdk ($GENERATED_PATHS)"
sync_generated "$build/out" "$sdk"
log "format"
format_generated "$sdk"

# 4. Patches: last resort for changes no overlay/template/config can make.
for patch in "$langdir"/patches/*.patch; do
  [ -f "$patch" ] || continue
  log "patch: ${patch#"$ROOT"/}"
  git -C "$sdk" apply --whitespace=nowarn "$patch" \
    || die "patch ${patch#"$ROOT"/} no longer applies; update or remove it"
done

# 5. Record what this was generated from.
cat > "$sdk/sdk-generator.json" <<JSON
{
  "comment": "Written by p2-inc/phasetwo-sdk-generator. Do not edit by hand.",
  "spec": {
    "repo": "$SPEC_REPO",
    "path": "$SPEC_PATH",
    "sha": "$SPEC_SHA"
  },
  "openapiGenerator": "$OPENAPI_GENERATOR_VERSION",
  "generatedPaths": "$GENERATED_PATHS"
}
JSON
log "done: $lang"
