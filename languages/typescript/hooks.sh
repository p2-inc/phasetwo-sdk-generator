# TypeScript SDK hooks, sourced by scripts/generate.sh.
# shellcheck disable=SC2034  # GENERATOR_NAME / GENERATED_PATHS are read by generate.sh
GENERATOR_NAME=typescript-fetch
# Generated code lives in src/openapi; src/index.ts and any helpers are hand-written.
GENERATED_PATHS="src/openapi"

sync_generated() { # <generator-output> <sdk>
  local out=$1 sdk=$2
  mkdir -p "$sdk/src/openapi"
  rsync -a --delete \
    --include='/apis/***' --include='/models/***' \
    --include='/runtime.ts' --include='/index.ts' --exclude='*' \
    "$out/src/" "$sdk/src/openapi/"
}

format_generated() { # <sdk>
  npx --yes "prettier@$PRETTIER_VERSION" --log-level warn --write "$1/src/openapi"
}

build_sdk() { # <sdk>
  (cd "$1" && npm ci --no-audit --no-fund && npm run build)
}
