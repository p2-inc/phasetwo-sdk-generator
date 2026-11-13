# Go SDK hooks, sourced by scripts/generate.sh.
# shellcheck disable=SC2034  # GENERATOR_NAME / GENERATED_PATHS are read by generate.sh
GENERATOR_NAME=oapi-codegen
# Generated code is the openapi package; the root phasetwo package is hand-written.
GENERATED_PATHS="openapi"

# Uses oapi-codegen instead of openapi-generator (see README: Go).
run_generator() { # <spec> <out-dir> <lang-dir>
  mkdir -p "$2/openapi"
  go run "github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@$OAPI_CODEGEN_VERSION" \
    -config "$3/config.yaml" -o "$2/openapi/openapi.gen.go" "$1"
}

sync_generated() { # <generator-output> <sdk>
  mkdir -p "$2/openapi"
  rsync -a --delete "$1/openapi/" "$2/openapi/"
}

format_generated() { # <sdk>
  gofmt -s -w "$1/openapi"
}

build_sdk() { # <sdk>  vet, unit tests, then the integration test against Phase Two Keycloak (needs Docker)
  (cd "$1" && go vet ./... && go test ./... && go test -tags integration -count=1 ./...)
}
