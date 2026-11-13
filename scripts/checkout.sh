#!/usr/bin/env bash
# Clone (or update) the SDK repos into .work/sdks/ for local generation.
#
#   scripts/checkout.sh [language...]     default: all
. "$(dirname "$0")/lib.sh"

langs=${*:-$LANGUAGES}
mkdir -p "$WORK/sdks"
for lang in $langs; do
  check_language "$lang"
  repo=$(sdk_repo_for "$lang")
  dir=$WORK/sdks/$lang
  if [ -d "$dir/.git" ]; then
    log "update $repo"
    git -C "$dir" fetch --quiet origin
  else
    log "clone $repo -> ${dir#"$ROOT"/}"
    git clone --quiet "https://github.com/$repo.git" "$dir"
  fi
done
