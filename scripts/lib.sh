# Shared helpers for the generator scripts. Source, don't execute.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-$ROOT/.work}
mkdir -p "$WORK"

# shellcheck source=../versions.env
. "$ROOT/versions.env"
# shellcheck source=../sdks.env
. "$ROOT/sdks.env"

LANGUAGES="java typescript python go"

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

check_language() {
  case " $LANGUAGES " in
    *" $1 "*) ;;
    *) die "unknown language '$1' (expected one of: $LANGUAGES)" ;;
  esac
}

sdk_repo_for() { # <lang> -> owner/repo
  case $1 in
    java) echo "$JAVA_REPO" ;;
    typescript) echo "$TYPESCRIPT_REPO" ;;
    python) echo "$PYTHON_REPO" ;;
    go) echo "$GO_REPO" ;;
  esac
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Download google-java-format once into .work/tools and verify its checksum.
tool_google_java_format() {
  local jar=$WORK/tools/google-java-format-$GOOGLE_JAVA_FORMAT_VERSION.jar
  if [ ! -f "$jar" ]; then
    mkdir -p "$WORK/tools"
    curl -fsSL -o "$jar.tmp" \
      "https://github.com/google/google-java-format/releases/download/v$GOOGLE_JAVA_FORMAT_VERSION/google-java-format-$GOOGLE_JAVA_FORMAT_VERSION-all-deps.jar"
    [ "$(sha256_of "$jar.tmp")" = "$GOOGLE_JAVA_FORMAT_SHA256" ] \
      || die "google-java-format checksum mismatch"
    mv "$jar.tmp" "$jar"
  fi
  echo "$jar"
}

# Run openapi-generator in Docker with the repo root mounted at /local.
# Paths passed in must be inside $ROOT (the .work dir is).
openapi_generator() {
  docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT:/local" -w /local \
    "openapitools/openapi-generator-cli:$OPENAPI_GENERATOR_VERSION" "$@"
}

in_container() { # absolute host path under $ROOT -> path inside the container
  case $1 in
    "$ROOT"/*) echo "/local/${1#"$ROOT"/}" ;;
    *) die "$1 is not under $ROOT" ;;
  esac
}

# The API version from a spec's info.version, e.g. 0.2.0. The SDKs are released as
# <major>.<minor>.<patch> of it: every SDK release 0.X.* implements API 0.X.
spec_api_version() { # <openapi.yaml>
  awk '/^info:/ { i = 1; next }
       i && /^[^ #]/ { exit }
       i && /^  version:/ { sub(/^  version:[ ]*/, ""); gsub(/["'"'"' ]/, ""); print; exit }' "$1"
}

