# Going live: setup guide

Everything needed to go from today's local branches to SDKs that regenerate and release automatically when `openapi.yaml` changes on `main` in `p2-inc/phasetwo-docs`.

Do the steps in order. Later steps depend on earlier ones, and the docs workflow (step 7) should be the last switch you flip.

## How the automation works once it's live

```
p2-inc/phasetwo-docs
  PR changes openapi.yaml
    └─ openapi-sdks.yml (check job)
         validate · Spectral lint (one tag per op, operationIds, Location on 201s)
         · oasdiff changelog comment, flagged if it breaks SDK users
  merge to main
    └─ openapi-sdks.yml (dispatch job)
         POST /repos/p2-inc/phasetwo-sdk-generator/dispatches
              event_type=openapi-updated, client_payload.sha=<merge commit>
                    │
p2-inc/phasetwo-sdk-generator                ▼
  regenerate.yml, one job per SDK (java, typescript, python, go)
    1. skip if the SDK's bot branch has human commits (comments on the PR instead)
    2. scripts/generate.sh at that spec commit: overlays → generator → sync
       generated paths → format → patches → sdk-generator.json
    3. scripts/spec-diff.sh: changelog + semver label (minor if breaking)
    4. open or update PR "Regenerate from phasetwo-docs@<sha>" on bot/openapi-update
                    │
SDK repos                                     ▼
  PR checks: build + tests (+ integration tests against Phase Two Keycloak)
             + openapi-drift (generated code matches the generator)
  a maintainer reviews; if the hand-written layer broke, pushes a fix to the PR branch
  merge to main → release.yml publishes:
    Java → Maven Central   TypeScript → npm   Python → PyPI   Go → git tag (pkg.go.dev)
    version: minor bump if the PR has semver:minor, otherwise patch
```

The same `regenerate.yml` also runs when generator inputs change on `main` here (overlays, templates, configs, `versions.env`, e.g. a Renovate bump of openapi-generator), weekly as a safety net, and manually (Actions → regenerate → Run workflow, optionally for one language or spec ref).

## 0. Before you start

- Owner access to the `p2-inc` GitHub org.
- Access to the `@p2-inc` npm scope, a PyPI account that will own `phasetwo-sdk`, and the existing Maven Central/OSSRH setup for `phasetwo-java` (its secrets are already in place).
- The local work, all inside `phasetwo-sdk-generator/.work/` (gitignored):

  | Where | Branch | What |
  |---|---|---|
  | `.work/phasetwo-docs` | `openapi-sdk-tags` | one tag per operation, "Organization Invitations", tag descriptions, the four missing operationIds (+ page renames and redirects) |
  | `.work/sdks/java` | `regenerate-openapi-7.27` | regenerated with 7.27, wrapper fixes, testcontainers bump |
  | `.work/sdks/typescript` | `regenerate-openapi-7.27` | regenerated into `src/openapi`, Account API dropped, TS 5, 0.1.0 |
  | `.work/sdks/python` | `regenerate-openapi-7.27` | pydantic generator, `phasetwo-sdk` packaging |
  | `.work/sdks/go` | `main` | new Go SDK |

## 1. Create the GitHub App

Org settings → Developer settings → GitHub Apps → New GitHub App, e.g. **phasetwo-sdk-bot**.

- Webhook: off.
- Repository permissions: **Contents: read and write**, **Pull requests: read and write**, Metadata: read (default). Nothing else; the bot never edits workflow files.
- Install it on the `p2-inc` org for these repositories only: `phasetwo-docs`, `phasetwo-sdk-generator`, `phasetwo-java`, `phasetwo-js`, `phasetwo-python`, `phasetwo-go` (create the last two repos in step 2 first, or add them to the installation afterwards).
- Generate a private key.
- Org settings → Secrets and variables → Actions:
  - variable `SDK_BOT_APP_ID` = the App ID
  - secret `SDK_BOT_PRIVATE_KEY` = the private key (`.pem` contents)
  - Limit both to `phasetwo-docs` and `phasetwo-sdk-generator`.

Why an App rather than `GITHUB_TOKEN` or a PAT: `GITHUB_TOKEN` can't push to other repos, and PRs it opens don't trigger CI. App tokens are short-lived, scoped to the repos above, and PRs opened with them do run CI. (`shared-github-actions` uses a `GH_PAT`, which would also work if you'd rather reuse it.)

## 2. Create the two new repos

```sh
gh repo create p2-inc/phasetwo-sdk-generator --public --description "Generates the Phase Two API SDKs from the OpenAPI spec"
gh repo create p2-inc/phasetwo-go --public --description "Phase Two API Go SDK"
```

`phasetwo-sdk-generator` should be public: the SDK repos' drift check clones it, and the SDK READMEs link to it. (If it must be private, give the drift workflow a token that can read it.)

Push the generator, but **don't enable Actions yet** (Settings → Actions → Disable), so `regenerate.yml` can't open PRs before the SDK repos are ready:

```sh
cd phasetwo-sdk-generator
git remote add origin git@github.com:p2-inc/phasetwo-sdk-generator.git
git push -u origin main
```

Hold off on `phasetwo-go` until step 5.

## 3. Registries

- **npm:** on npmjs.com, `@p2-inc/js-sdk` → Settings → Trusted publishing → GitHub Actions: org `p2-inc`, repo `phasetwo-js`, workflow `release.yml`. (Needs npm ≥ 11.5 in the workflow; Node 24 has it.)
- **PyPI:** pypi.org → Your projects → Publishing → Add a pending publisher: project `phasetwo-sdk`, owner `p2-inc`, repo `phasetwo-python`, workflow `release.yml`, environment `pypi`. This reserves the name until the first upload. Then in `phasetwo-python` create the `pypi` environment (Settings → Environments). Optionally require a reviewer on it.
- **Maven Central:** nothing new; `phasetwo-java` already releases (0.1.16 is on Central).
- **Go:** nothing; releases are git tags, and pkg.go.dev picks them up.

## 4. Merge the spec changes in phasetwo-docs

```sh
cd .work/phasetwo-docs
git push -u origin openapi-sdk-tags
gh pr create --title "openapi: one tag per operation, add missing operationIds" --fill
```

Check the preview deploy: the four renamed API pages, their redirects, and the "Organization Invitations" sidebar label. The `api/*.api.mdx` files were renamed by hand; running `pnpm regen-api-docs` should produce the same file names (it refreshes their embedded API data, which doesn't mention the new operationIds yet).

Don't add the docs workflow yet (step 7). Merge.

## 5. Land the SDK foundation PRs

Each SDK branch records the spec commit it was generated from in `sdk-generator.json`. That's currently the unmerged docs branch commit, which a squash merge won't keep. So first regenerate from the merge commit on `main` (only `sdk-generator.json` should change), then push.

```sh
cd phasetwo-sdk-generator
for l in java typescript python go; do
  SPEC_REF=main scripts/generate.sh $l .work/sdks/$l
  git -C .work/sdks/$l commit -am "Record phasetwo-docs main as the spec source"
done
```

For each SDK, add its workflows from `other-repos/` on the same branch, then push and open a PR:

| Repo | Add / replace |
|---|---|
| phasetwo-java | `other-repos/sdks/openapi-drift.yml` (`LANGUAGE: java`); replace `.github/workflows/release.yml` with `other-repos/phasetwo-java/release.yml` |
| phasetwo-js | `openapi-drift.yml` (`LANGUAGE: typescript`); `other-repos/phasetwo-js/release.yml`; `other-repos/phasetwo-js/ci.yml` (the repo has no CI) |
| phasetwo-python | `openapi-drift.yml` (`LANGUAGE: python`); `other-repos/phasetwo-python/release.yml`; `other-repos/phasetwo-python/ci.yml` |
| phasetwo-go | already has `ci.yml`, `release.yml`, `openapi-drift.yml` |

```sh
cd .work/sdks/java   # likewise typescript, python
git push -u origin regenerate-openapi-7.27
gh pr create --fill --label semver:minor

cd ../go
git remote add origin git@github.com:p2-inc/phasetwo-go.git
git push -u origin main   # first push; its release workflow tags v0.1.0
```

Label each PR `semver:minor`: they all contain breaking changes. Merging them should release:

| SDK | Release |
|---|---|
| Java | 0.2.0 (the Maven release action bumps the minor from 0.1.17-SNAPSHOT) |
| TypeScript | 0.1.0 (npm is at 0.0.11) |
| Python | 0.3.0 (first PyPI release) |
| Go | v0.1.0 |

Then, in each SDK repo, Settings → Branches → protect `main` and require the CI and `openapi-drift` checks.

## 6. Turn on the generator

In `phasetwo-sdk-generator`:

1. Enable Actions.
2. Install Renovate on the repo (it reads `renovate.json`).
3. Run **Actions → regenerate → Run workflow** (language `all`). Every SDK is already current, so it should open no PRs. Any PR it does open shows a gap to look at.
4. Run **Actions → ci** (or open a trivial PR) to see every SDK regenerate and build/test from the generator.

## 7. Turn on the docs trigger

In `phasetwo-docs`, add `other-repos/phasetwo-docs/openapi-sdks.yml` as `.github/workflows/openapi-sdks.yml`, and `other-repos/phasetwo-docs/.spectral.yaml` at the repo root, in one PR. That PR touches `.spectral.yaml`, so the check job runs on it, which is a good first test.

From now on, every merge to `main` that changes `openapi.yaml` dispatches `regenerate.yml`, and the SDK PRs appear within a few minutes.

## 8. README banners and docs

- In `p2-inc/shared-github-actions`, `readme/repos.json`:
  - add `p2-inc/phasetwo-go` (`kind: general`, `license: Apache-2.0`, `docs: https://phasetwo.io/docs/api/sdks/`);
  - set `workflow` for phasetwo-js, phasetwo-python and phasetwo-go to their CI workflow;
  - add a PyPI badge for phasetwo-python (a new `pypi` key in `sync_readme.py`).
- In `phasetwo-docs`, add Go to the SDK table in `docs/api/sdks.md` and in the `info.description` of `openapi.yaml`. See PLAN.md §5 for the larger README/docs rework.

## 9. Check it end to end

Make a harmless spec change, e.g. reword one operation's `description` in `openapi.yaml`:

1. The docs PR gets a changelog comment, with no breaking warning.
2. After merge, `regenerate` runs four jobs, and each SDK gets a "Regenerate from phasetwo-docs@…" PR labelled `semver:patch` with green checks.
3. Merging one releases a patch version.

## Day-to-day

| Situation | What to do |
|---|---|
| Spec change merged, SDK PR is green | Review the diff and changelog, merge. It releases. |
| SDK PR fails CI because hand-written code broke (e.g. a new parameter) | Push a fix to the `bot/openapi-update` branch. The bot won't overwrite it; it comments instead. Merge when green. |
| The generator output is wrong | Fix it in phasetwo-sdk-generator: spec upstream → overlay → template → config → patch (see README). Merging that regenerates all SDKs. |
| openapi-generator / oapi-codegen bump (Renovate PR) | `ci` shows each SDK's diff and test results. Check the `GENERATOR BUG` overlay actions and the template overrides, then merge. |
| A human PR in an SDK fails `openapi-drift` | Someone edited generated code. Move the change into the generator. If the generator changed since the SDK was last regenerated, merge the pending bot PR first. |
| Need to regenerate without a spec change | Actions → regenerate → Run workflow. |
| Don't want a merge to release | Put `[ci skip]` in the merge commit message. |
