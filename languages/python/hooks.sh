# Python SDK hooks, sourced by scripts/generate.sh.
# shellcheck disable=SC2034  # GENERATOR_NAME / GENERATED_PATHS are read by generate.sh
GENERATOR_NAME=python
GENERATED_PATHS="phasetwo/openapi"

sync_generated() { # <generator-output> <sdk>
  local out=$1 sdk=$2
  mkdir -p "$sdk/phasetwo/openapi"
  rsync -a --delete "$out/phasetwo/openapi/" "$sdk/phasetwo/openapi/"
}

format_generated() { # <sdk>
  uvx --quiet "ruff@$RUFF_VERSION" format --quiet "$1/phasetwo/openapi"
}

build_sdk() { # <sdk>  build the wheel and check that it imports
  (cd "$1" && rm -rf dist && uv build -q \
    && uv run -q --no-project --with dist/*.whl python -I -c 'import phasetwo; print("phasetwo", phasetwo.__version__)')
}
