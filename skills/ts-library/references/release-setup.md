# Releases and CI

`semantic-release` at the **repo root**, driven by conventional commits. Nobody
edits a version number or a changelog by hand.

```
feat:               → minor
fix:                → patch
BREAKING CHANGE:    → major   (in the commit body/footer)
chore/docs/test/ci  → no release
```

## `.releaserc.json` — single package

```json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    "@semantic-release/npm",
    [
      "@semantic-release/git",
      {
        "assets": ["CHANGELOG.md", "package.json"],
        "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }
    ],
    [
      "@semantic-release/github",
      { "successComment": false, "failComment": false, "releasedLabels": false }
    ]
  ]
}
```

`[skip ci]` in the release commit message is load-bearing — without it the
release commit retriggers CI, which retriggers release.

The `github` plugin's three `false`s turn off the comment-on-every-closed-issue
and label behaviour, which is noise on a small repo.

## `.releaserc.json` — monorepo, one repo-wide version

A monorepo releases **one version for every package**: a single `v${version}`
tag and one GitHub release, even for packages that did not change. This is
deliberate — it keeps cross-package peer ranges trivially satisfiable and means
there is exactly one number to reason about.

`@semantic-release/npm` is replaced by `@semantic-release/exec`, because npm's
plugin only knows how to publish the package it sits in:

```json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    [
      "@semantic-release/exec",
      {
        "prepareCmd": "npm version ${nextRelease.version} --workspaces --no-git-tag-version --allow-same-version",
        "publishCmd": "npm publish -w packages/graphql-casl && npm publish -w packages/graphql-casl-codegen"
      }
    ],
    [
      "@semantic-release/git",
      {
        "assets": ["CHANGELOG.md", "package-lock.json", "packages/*/package.json"],
        "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }
    ],
    [
      "@semantic-release/github",
      { "successComment": false, "failComment": false, "releasedLabels": false }
    ]
  ]
}
```

- `--no-git-tag-version` — semantic-release owns the tag.
- `--allow-same-version` — a package already at that version must not fail.
- `git.assets` must include `packages/*/package.json` and `package-lock.json`,
  or the bump is published but never committed and the next release recomputes
  from a stale tree.
- `publishCmd` names each package explicitly. Adding a package means adding it
  here; `npm publish --workspaces` also works but silently tries to publish the
  private root in some npm versions.

## `.github/workflows/test.yml`

```yaml
name: Test

on:
  push:

jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 24
      - run: npm ci
      - name: Lint
        run: npx biome check .
      - name: Build
        run: npm run build
      - name: Type check
        run: npm run typecheck
      - name: Type check tests
        run: npm run typecheck:tests
      - name: Test
        run: npm test
      - name: Coverage
        run: npm run coverage
```

`typecheck:tests` is a separate step from `typecheck` because the build tsconfig
excludes tests; without it, a test file that no longer compiles still passes.

## `.github/workflows/release.yml`

```yaml
name: Release

on:
  workflow_run:
    workflows: ["Test"]
    branches: [main]
    types: [completed]

jobs:
  release:
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    permissions:
      contents: write
      issues: write
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
          persist-credentials: false
          ref: ${{ github.event.workflow_run.head_sha }}

      - uses: actions/setup-node@v5
        with:
          node-version: 24
          registry-url: "https://registry.npmjs.org"

      - run: npm ci
      - run: npm run build

      - name: Release
        run: npx semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Four details that each break the release silently if wrong:

- **`fetch-depth: 0`** — semantic-release derives the next version from the tag
  history. A shallow clone has none, so every release computes as `1.0.0`.
- **`persist-credentials: false`** — semantic-release pushes with its own token;
  the checkout credentials interfere.
- **`ref: head_sha`** — `workflow_run` checks out the default branch tip by
  default, which may already be ahead of the commit that passed CI.
- **`id-token: write`** — required for npm OIDC trusted publishing.

## Publishing auth

Prefer **OIDC trusted publishing**: `id-token: write` in the job, no token
secret at all.

> Every package needs its own trusted-publisher entry on npm, and npm matches
> the entry's workflow filename against this file's name **exactly**. An entry
> naming anything but `release.yml` will not match, and the publish falls back
> to token auth and fails.

Otherwise set the `NPM_ACCESS_TOKEN` secret and pass it as `NODE_AUTH_TOKEN`.
`GITHUB_TOKEN` always comes from Actions.

## Before wiring it up

```bash
npx semantic-release --dry-run
```

at the root. It prints the version it would release and the notes it would
write, and does nothing. If you are adding semantic-release to a package that
already has releases, **keep the existing tag format** so the tag history stays
continuous — otherwise the first automated release jumps back to `1.0.0`.
