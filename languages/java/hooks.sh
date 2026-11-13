# Java SDK hooks, sourced by scripts/generate.sh.
# shellcheck disable=SC2034  # GENERATOR_NAME / GENERATED_PATHS are read by generate.sh
GENERATOR_NAME=jaxrs-spec
# Paths in the SDK repo that the generator owns. Never edit these by hand.
GENERATED_PATHS="src/gen/java/io/phasetwo/client/openapi/api src/gen/java/io/phasetwo/client/openapi/model src/gen/java/io/phasetwo/client/openapi/RestResourceRoot.java src/main/openapi/openapi.yaml"

sync_generated() { # <generator-output> <sdk>
  local out=$1 sdk=$2 pkg=src/gen/java/io/phasetwo/client/openapi
  mkdir -p "$sdk/$pkg/api" "$sdk/$pkg/model" "$sdk/src/main/openapi"
  rsync -a --delete "$out/$pkg/api/" "$sdk/$pkg/api/"
  rsync -a --delete "$out/$pkg/model/" "$sdk/$pkg/model/"
  # Base path constant (from the spec's servers url), used by PhaseTwo.java.
  # RestApplication.java is a server-side class and is deliberately not copied.
  cp "$out/$pkg/RestResourceRoot.java" "$sdk/$pkg/RestResourceRoot.java"
  # The exact spec (after overlays) the code was generated from, for reference.
  cp "$out/src/main/openapi/openapi.yaml" "$sdk/src/main/openapi/openapi.yaml"
}

format_generated() { # <sdk>
  local jar
  jar=$(tool_google_java_format)
  find "$1/src/gen/java/io/phasetwo/client/openapi" -name '*.java' -print0 \
    | xargs -0 java -jar "$jar" --replace
}

build_sdk() { # <sdk>  compile + run the Testcontainers integration test (needs Docker)
  (cd "$1" && mvn -B -q verify)
}
