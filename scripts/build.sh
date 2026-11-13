#!/usr/bin/env bash
# Build (and, where the SDK has them, test) an SDK checkout.
#
#   scripts/build.sh <language> <sdk-dir>
. "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "usage: $0 <language> <sdk-dir>"
check_language "$1"
# shellcheck source=/dev/null
. "$ROOT/languages/$1/hooks.sh"
log "build $1"
build_sdk "$(cd "$2" && pwd)"
