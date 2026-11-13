#!/usr/bin/env bash
# Fetch the Phase Two Admin API spec into .work/spec/openapi.yaml and record where it
# came from in .work/spec/source.env.
#
#   SPEC_FILE=path/to/openapi.yaml   use a local file (e.g. a phasetwo-docs branch)
#   SPEC_REF=<sha|branch>            fetch from GitHub at this ref (default: $SPEC_BRANCH)
. "$(dirname "$0")/lib.sh"

dest=$WORK/spec
mkdir -p "$dest"

if [ -n "${SPEC_FILE:-}" ]; then
  [ -f "$SPEC_FILE" ] || die "SPEC_FILE $SPEC_FILE not found"
  cp "$SPEC_FILE" "$dest/openapi.yaml"
  dir=$(cd "$(dirname "$SPEC_FILE")" && pwd)
  if sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null); then
    [ -z "$(git -C "$dir" status --porcelain -- "$(basename "$SPEC_FILE")")" ] || sha="$sha-dirty"
  else
    sha=unknown
  fi
  log "spec: local file $SPEC_FILE ($sha)"
else
  ref=${SPEC_REF:-$SPEC_BRANCH}
  if [[ $ref =~ ^[0-9a-f]{40}$ ]]; then
    sha=$ref
  else
    sha=$(git ls-remote "https://github.com/$SPEC_REPO.git" "refs/heads/$ref" | cut -f1)
    [ -n "$sha" ] || die "branch $ref not found in $SPEC_REPO"
  fi
  curl -fsSL -o "$dest/openapi.yaml" "https://raw.githubusercontent.com/$SPEC_REPO/$sha/$SPEC_PATH"
  log "spec: $SPEC_REPO@$sha:$SPEC_PATH"
fi

cat > "$dest/source.env" <<ENV
SPEC_SHA=$sha
ENV
