# phasetwo-sdk-generator

Generates the Phase Two Admin API SDKs from the [OpenAPI spec](https://github.com/p2-inc/phasetwo-docs/blob/main/openapi.yaml) in `p2-inc/phasetwo-docs`, and opens a PR in each SDK repo when the spec or the generator changes.

| Language | SDK repo | Package | Generator |
|---|---|---|---|
| Java | [phasetwo-java](https://github.com/p2-inc/phasetwo-java) | `io.phasetwo:phasetwo-admin-client` | `jaxrs-spec` (interfaces used as RESTEasy proxies via the Keycloak admin client) |
| TypeScript | [phasetwo-js](https://github.com/p2-inc/phasetwo-js) | `@p2-inc/js-sdk` | `typescript-fetch` |
| Python | [phasetwo-python](https://github.com/p2-inc/phasetwo-python) | `phasetwo-sdk` (import `phasetwo`) | `python` (pydantic v2) |

All three use [OpenAPI Generator](https://openapi-generator.tech), version pinned in [`versions.env`](versions.env).

## How it works

```
phasetwo-docs: openapi.yaml changes on main
  └─ dispatch ─▶ this repo: regenerate.yml (one job per SDK)
       scripts/generate.sh <language> <sdk checkout>
         1. fetch the spec at a commit
         2. apply overlays/common.yaml, then languages/<language>/overlay.yaml
         3. openapi-generator with languages/<language>/config.yaml and templates/
         4. sync into the SDK's generated-only paths (everything else is untouched)
         5. format (google-java-format, prettier, ruff)
         6. apply languages/<language>/patches/*.patch
         7. write sdk-generator.json (spec commit, generator version)
       scripts/spec-diff.sh: oasdiff changelog + semver label
       └─ PR "Regenerate from phasetwo-docs@<sha>" on bot/openapi-update in the SDK repo
SDK repo: CI builds/tests the PR; a person reviews, fixes hand-written code if
needed (on the same branch), merges, and the SDK's release workflow publishes.
```

### Generated vs hand-written code

Each SDK keeps generated code in its own directory. Never edit it by hand: the drift check ([`other-repos/sdks/openapi-drift.yml`](other-repos/sdks/openapi-drift.yml)) regenerates it and fails the PR if it differs.

| SDK | Generated (owned by this repo) | Hand-written |
|---|---|---|
| Java | `src/gen/java/io/phasetwo/client/openapi/{api,model}`, `RestResourceRoot.java`, `src/main/openapi/openapi.yaml` | `src/main` (`PhaseTwo`, `*Resource` wrappers), `pom.xml`, README |
| TypeScript | `src/openapi/` | `src/index.ts` (re-exports `./openapi`), `package.json`, README |
| Python | `phasetwo/openapi/` | `phasetwo/__init__.py` (re-exports `phasetwo.openapi`), `pyproject.toml`, README |

### Where a change goes

When the generator's output isn't what we want, don't fix it in the SDK. Use the first of these that works:

1. **The spec is wrong or missing something** → fix `openapi.yaml` in phasetwo-docs. Until that merges, an action in [`overlays/common.yaml`](overlays/common.yaml) marked `UPSTREAM:`.
2. **An SDK-only change to the spec** → `languages/<language>/overlay.yaml` ([OpenAPI Overlay 1.0](https://spec.openapis.org/overlay/v1.0.0.html)). Example: the Java overlay marks the operations whose methods must return `jakarta.ws.rs.core.Response` (for the `Location` header or the status code) with `x-p2-return-response: true`.
3. **How code is rendered** → override just that template in `languages/<language>/templates/`. Get the stock templates with `docker run --rm -v $PWD:/local openapitools/openapi-generator-cli:<version> author template -g <generator> -o /local/tpl`. Example: [`languages/java/templates/apiInterface.mustache`](languages/java/templates/apiInterface.mustache) reads `x-p2-return-response`.
4. **Names and options** → `languages/<language>/config.yaml`.
5. **Anything else** → a patch in `languages/<language>/patches/`, made against the formatted output and applied with `git apply`. Generation fails if a patch stops applying. Keep this empty if you can.

Hand-written code that breaks because the generated API changed (a new parameter, a renamed class) is fixed in the SDK repo, on the bot's PR branch.

## Running locally

Needs Docker, Java 21+, Node, [uv](https://docs.astral.sh/uv/), `rsync`, `git`, `curl`.

```sh
make checkout            # clone the SDK repos into .work/sdks/<language>
make all                 # regenerate all three from phasetwo-docs main
make java                # or one at a time
make build               # build/test every SDK checkout (Java runs Testcontainers)
make drift               # confirm the checkouts match what the generator produces
```

Options (environment variables):

- `SPEC_FILE=../phasetwo-docs/openapi.yaml`: use a local spec, e.g. an unmerged phasetwo-docs branch. Its git commit is recorded.
- `SPEC_REF=<sha|branch>`: fetch the spec at this ref (default: `main`).
- `SDK_DIR=<dir>`: where the SDK checkouts are (default: `.work/sdks`).

`scripts/generate.sh <language> <sdk-dir>` works on any checkout, e.g. your own working copy of an SDK.

## Upgrading OpenAPI Generator

Renovate opens a PR bumping `OPENAPI_GENERATOR_VERSION` in `versions.env`. CI on that PR regenerates every SDK from its default branch and builds and tests it. Generator upgrades often change the generated API, so check:

- the diff of each SDK (CI prints it), especially method and class names;
- the `GENERATOR BUG` actions in the overlays: drop any the new version fixes;
- each template override in `languages/*/templates/` against the new stock template.

After merging, `regenerate.yml` opens the SDK PRs.

## Setup

**This repo**
- A GitHub App (e.g. "phasetwo-sdk-bot") installed on `phasetwo-java`, `phasetwo-js`, `phasetwo-python` and this repo, with *Contents* and *Pull requests* read/write.
- `vars.SDK_BOT_APP_ID` and `secrets.SDK_BOT_PRIVATE_KEY` for that App.
- Renovate enabled.

**phasetwo-docs:** copy [`other-repos/phasetwo-docs/openapi-sdks.yml`](other-repos/phasetwo-docs/openapi-sdks.yml) to `.github/workflows/` and [`.spectral.yaml`](other-repos/phasetwo-docs/.spectral.yaml) to the repo root, and add the same App variable/secret. PRs that change `openapi.yaml` then get validation, SDK-focused lint (one tag per operation, operationIds, `Location` on 201s) and an API-changelog comment; merges trigger regeneration.

**Each SDK repo:** copy [`other-repos/sdks/openapi-drift.yml`](other-repos/sdks/openapi-drift.yml) to `.github/workflows/` and set `LANGUAGE`. Releases stay in each SDK repo's own release workflow.

## Layout

```
versions.env                 pinned tool versions (Renovate-managed)
sdks.env                     spec location and SDK repos
overlays/common.yaml         spec fixes for every SDK (UPSTREAM: / GENERATOR BUG:)
languages/<language>/
  config.yaml                openapi-generator options
  overlay.yaml               SDK-specific spec changes
  templates/                 template overrides (only the files we change)
  patches/                   last-resort patches (ideally empty)
  hooks.sh                   generator name, generated paths, sync/format/build
scripts/                     generate, check-drift, spec-diff, build, checkout, fetch-spec
other-repos/                 workflows to install in phasetwo-docs and the SDK repos
.github/workflows/           regenerate (open SDK PRs), ci (test generator changes)
```

## License

Apache License 2.0, see [COPYING](COPYING).
