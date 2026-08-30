---
name: graphql-codegen
description: >
  Wire or debug the cubicecho GraphQL codegen pipeline — Drizzle tables to
  printed schema.graphql to typed resolvers to typed client operations — using
  graphql-codegen, the client preset, resolver mappers, and the @vantreeseba
  codegen plugins. Use when adding codegen to a project, changing a codegen
  config, or diagnosing stale, missing, or mistyped generated output.
version: 0.0.1
license: MIT
---

# GraphQL Codegen Pipeline

The contract between `db`, `server`, and every client. If `ts-house-style`,
`ts-backend`, `simple-ts-frontend`, or `expo-frontend` skills are available they
describe what produces and consumes this output; this skill stands on its own
without them.

## The pipeline

```
Drizzle tables
  → generate:schema   →  server/src/__generated__/schema.graphql   (print the built schema)
  → codegen:server    →  server/src/__generated__/resolvers.ts     (+ permissions, mocks maps)
  → codegen:client    →  client/src/__generated__/                 (client preset)
```

`npm run codegen` runs all three, in that order. Each step reads the previous
step's **file** — not a running server and not a database.

**Step 1 must not connect to anything.** It runs the schema module directly —
`buildSchema` then `applyCustomResolvers` then `printSchema` — so the printed SDL
is *exactly* the surface the server serves, and so codegen works in a Docker
build stage and in CI with no Postgres. It constructs its own `drizzle()` over an
unresolved DSN rather than importing the runtime `db` singleton, which throws at
import without `DATABASE_URL`.

→ **[`references/generate-schema.ts`](references/generate-schema.ts)** — the
script, why no connection is made, and the base-builder escape from the
permissions bootstrap cycle.

## When to run what

| Changed | Run |
| --- | --- |
| A Drizzle table | `npm run db:generate && npm run db:migrate && npm run codegen` |
| Custom SDL (`extensions.graphql` / `extensionSDL`) | `npm run codegen` |
| A client query, mutation, or fragment | `npm run codegen` (or `codegen:client`) |
| Nothing schema-shaped | nothing |

**Always run codegen before `typecheck`, `test`, or `build`.** A stale
`__generated__/` reports type errors that do not exist and hides ones that do.
Wire it into `pre*` hooks rather than relying on memory.

## Server config

`graphql-codegen-esm --config codegen.server.ts`. Emits `resolvers.ts`, and
optionally the CASL `permissions.ts` and the mocks `schema-type-map.ts`.

Every option in it is load-bearing — `mappers` (aliased `*Row`, so resolvers can
return plain Drizzle rows), `enumsAsTypes` (TS enums are nominal), `contextType`,
`avoidOptionals.field`, `scalars`.

→ **[`references/codegen.server.ts`](references/codegen.server.ts)** — the full
annotated config.

## Client config

`graphql-codegen --config codegen.ts`. The `client` preset, emitting into a
directory (the trailing `/` is required).

Operations **must** use the generated `graphql()` helper against a string
literal. A raw `gql` template, or an interpolated document, is invisible to
codegen and produces an untyped document — it typechecks and fails at runtime.

Include every tree that holds operations. On Expo that means `client/app/**` as
well as `client/src/**`; leaving routes out silently generates their operations
as `unknown`. Always exclude the generated directory, or codegen reads its own
output.

→ **[`references/codegen.ts`](references/codegen.ts)** — the full annotated
config, scalar mapping, and the fragment-masking decision.

## Plugins, wiring, and debugging

The four additional generators, the plugin combinations that collide, the `pre*`
hooks and Dockerfile step that make codegen unskippable, `@0no-co/graphqlsp` for
in-editor diagnostics, the commit-the-schema decision, and a symptom → cause
table.

→ **[`references/plugins.md`](references/plugins.md)**
