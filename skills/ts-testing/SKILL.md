---
name: ts-testing
description: >
  Write and configure tests for cubicecho TypeScript projects — Vitest (or
  node:test), schema-derived fixtures from @vantreeseba/graphql-mocks,
  per-test in-memory PGLite databases, drift tests that pin two sources of truth
  together, env isolation, and coverage gates. Use when adding a test, setting
  up a test runner, debugging a failing or flaky suite, or deciding what is worth
  testing.
version: 0.0.1
license: MIT
---

# TS Testing

How cubicecho projects test. If a `ts-house-style` skill is available, read it
for the shared TypeScript conventions; this skill stands on its own without it.

## Runner

**Vitest** is the default. `node --test --experimental-strip-types` is the
alternative for packages that want zero test dependencies (published libraries,
MCP servers) — the `describe`/`it` shape is the same, so the choice is per-repo
and not worth relitigating inside one.

```bash
npm test                                    # whole suite, once
npm test -- server/test/services/x.test.ts  # one file
npm test -- -t "schedules a todo"           # one test by name
npm run test:watch
npm run coverage
```

**Codegen runs before tests, always** — as a `pretest` hook or inline
(`"test": "npm run codegen && …"`). A stale `__generated__/` makes a suite fail
on type errors that do not exist, or pass against a schema that no longer
exists.

## Layout

`test/` sits parallel to `src/`, mirroring its structure; integration tests go
under `test/integration/`. Some repos put tests beside the source instead —
follow whichever the repo already does.

```
server/
├── src/
└── test/
    ├── test-mocks.ts          # schema-derived fixtures
    ├── auth.test.ts
    ├── schema/
    │   ├── validator-drift.test.ts
    │   └── resolvers/
    │       ├── test-helpers.ts   # PGLite + schema + gql() harness
    │       └── scope.test.ts
    └── services/
```

## Runner config

Three variants — workspace (alias `graphql` to one path), published library
(`dedupe` + `deps.inline`), and minimal.

**The `graphql` single-instance problem is the one that will cost you an hour.**
`graphql` throws *"another module or realm"* when loaded more than once, and
under vitest's SSR loader it can arrive as both CJS and ESM — an externalized
dependency gets the CJS build while inlined source gets the ESM one.

→ **[`references/vitest.config.ts`](references/vitest.config.ts)** — all three
variants, plus the `node:test` alternative with its coverage flags.

## Fixtures come from the schema

Build mocks **once at module load** from the printed `schema.graphql`, fixed
seed, wrapped in per-entity `make*` helpers that take overrides. A fixture
derived from the schema **cannot drift from it** — add a required column and
every hand-written literal is silently missing it.

Set only the fields the test is *about*; everything else being
arbitrary-but-stable is the point.

## Database tests use their own PGLite

**Never import the `db` singleton in a test.** Each test file builds its own
in-memory instance, migrated from the real migration folder, and blanking
`DATABASE_URL` in the runner config is the backstop that makes an accidental
import fail loudly.

PGLite is a devDependency of `server`, **not** a dependency of `db` — a
production install cannot pull it in.

For resolver tests, build the **real schema** the server serves and execute
against it. A resolver called directly skips schema validation, argument
coercion, the scoping wrappers, and the generated relation resolvers — which is
most of what is worth testing.

→ **[`references/test-helpers.ts`](references/test-helpers.ts)** — `createTestDb`,
`buildTestSchema`, the `gql()` harness, and the seed-helper conventions.

→ **[`references/fixtures.md`](references/fixtures.md)** — the mock builder and
why each of its three options is load-bearing, env and module isolation
(`vi.unstubAllEnvs`, `vi.hoisted`, fake timers), what is worth testing, and the
coverage gate.

## Drift tests

**Write one wherever two things describe the same shape and nothing but habit
keeps them in step.** The SDL and the zod validators both describe every
mutation input; a field added to one but not the other type-checks, resolves,
and reaches the database unvalidated, because zod strips unknown keys silently.
The symptom is a setting that does nothing, which nobody reports.

Where both sides are TypeScript, prefer an exhaustive `Record` — a compile error
beats a test.

→ **[`references/drift-tests.md`](references/drift-tests.md)** — the full SDL ↔
zod check, the six-point shape to copy for any other pair, and the table of
candidates in this stack.
