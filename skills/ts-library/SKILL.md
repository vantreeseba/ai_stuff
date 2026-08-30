---
name: ts-library
description: >
  Create or maintain a publishable cubicecho npm package — ESM (or dual ESM/CJS)
  TypeScript, peer-dependency-first, semantic-release from conventional commits,
  Biome, TypeDoc to the GitHub wiki, and coverage thresholds. Use when starting
  a new library, adding an entry point or subpath export, setting up releases, or
  preparing a package for publish.
version: 0.0.1
license: MIT
---

# TS Library

The loadout for packages published to npm (`@vantreeseba/*`, `@cubicecho/*`).
If a `ts-house-style` skill is available, read it for the shared TypeScript
conventions, and a `ts-testing` skill for the suite; neither is required here.

## Shape

Single package, or an npm-workspaces monorepo under `packages/*` when a runtime
and its codegen plugin ship together. The root `package.json` is
`private: true` and stays at `0.0.0`; only sub-packages publish.

```
packages/<name>/
├── src/
│   ├── index.ts        # the public API entry point — ALL exports go through it
│   ├── <subpath>.ts    # one file per subpath export
│   └── internal.ts     # shared, not exported
├── test/               # parallel to src/, integration tests in test/integration/
├── tsconfig.json       # typecheck (noEmit)
├── tsconfig.build.json # emit to dist/
├── tsconfig.tests.json # typecheck the tests
└── typedoc.json
```

Root scripts fan out with `--workspaces --if-present`; one package is targeted
with `-w packages/<name>`.

## package.json and dependencies

**Peer-dependency-first.** Anything the consumer already has — `graphql`,
`@modelcontextprotocol/sdk`, `@casl/ability`, `graphql-middleware`,
`@graphql-codegen/plugin-helpers` — is a `peerDependency` with a **range**, plus
a devDependency at a concrete version for the tests. Two copies of `graphql` in
one process is a silent cross-realm failure; a hard dependency guarantees it.

Aim for **zero runtime dependencies**. Where one subpath genuinely needs a
package the others do not, make it an *optional* peer via
`peerDependenciesMeta` — and never let the main entry import that subpath, or
the optional peer becomes a required one npm does not install.

`prepack` builds, `files: ["dist"]`, `types` first in every export condition.

→ **[`references/package-json.md`](references/package-json.md)** — the full
manifest, subpath layout, the dual ESM/CJS build (two `tsc` passes plus the
`postbuild.mjs` type markers), and the monorepo root.

## API design

- **All exports go through `src/index.ts`**, which carries the package overview
  docblock TypeDoc renders as the front page.
- **Stay domain-agnostic.** Type helpers derive from the *consumer's* generated
  types (`Resolvers`, `ResolversTypes`) — never hardcode a domain type name.
- Factories bound to the consumer's context shape, rather than configuration
  objects, keep the consumer's auth and domain logic out of the library core.
- Ship **recipes, not exports**, for adapter code specific to one other library:
  a tested `test/recipes/drizzleGraphql.ts` meant to be copy-pasted, not a
  public surface you now have to version.

## Tests

> If a `ts-testing` skill is available, follow it for runner setup, fixtures, the
> `graphql` single-instance problem, and coverage.

Vitest (`vitest run`), tests in `test/`, integration tests in
`test/integration/`. Coverage is a **gate, not a report** — 90 lines / 80
branches / 85 functions. `typecheck:tests` is a separate script and a separate
CI step, because the build tsconfig excludes tests.

Keep one `example.test.ts` that is a runnable worked example: it doubles as
reference documentation and cannot rot.

## Docs

`README.md` (usage, not internals), `AGENTS.md` at the root with `CLAUDE.md`
pointing at it, TypeDoc → `docs/api/` → the GitHub Wiki via CI, and
`llms.txt` / `context7.json` where agents are the consumer.

`CHANGELOG.md` is written by semantic-release. Never edit it by hand.

→ **[`references/docs-setup.md`](references/docs-setup.md)** — the `typedoc.json`
(including `entryPoints` per subpath and `intentionallyNotExported`) and the
wiki-publish CI step.

## Releases

`semantic-release` at the repo root, driven by conventional commits. A monorepo
releases **one repo-wide version** — a single `v${version}` tag and one GitHub
release, with `@semantic-release/exec` bumping and publishing every workspace, so
cross-package peer ranges stay trivially satisfiable.

Two workflows: `test.yml` on every push (lint, build, typecheck,
typecheck:tests, test, coverage, docs), and `release.yml` on `workflow_run` after
it succeeds on `main`.

Validate with `npx semantic-release --dry-run` at the root before wiring it up,
and keep the existing tag format so the tag history stays continuous.

→ **[`references/release-setup.md`](references/release-setup.md)** — both
`.releaserc.json` variants, both workflows, the four checkout settings that
break a release silently, and the OIDC trusted-publishing filename rule.
