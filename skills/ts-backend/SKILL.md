---
name: ts-backend
description: >
  Build a TypeScript GraphQL backend the cubicecho way: Drizzle tables as the
  source of truth, a schema generated from them and narrowed by declarative
  tenant scoping, hand-written scoped mutations with zod validation, Express +
  Apollo, and DataLoader. Use when creating or extending a server workspace,
  adding a table, a query, a mutation, or a subscription.
version: 0.0.1
license: MIT
---

# TypeScript Backend

If a `ts-house-style` skill is available, read it for the shared conventions
(ESM, Biome, workspace layout, git). If not, this skill stands on its own.

## Loadout

| Concern | Choice |
| --- | --- |
| Runtime | Node 22+, ESM, `node --experimental-strip-types` |
| HTTP | Express 5 + `@as-integrations/express5` |
| GraphQL | Apollo Server 5, or GraphQL Yoga on newer repos |
| Schema | `@vantreeseba/drizzle-graphql` — reads generated from Drizzle tables |
| ORM | Drizzle ORM 1.0-rc over `postgres.js` |
| Database | Postgres, always. No fallback backend. |
| Validation | zod, at the resolver boundary only |
| Batching | DataLoader, created per request |
| Auth | JWT magic links + hashed API keys; better-auth on newer repos |
| Permissions | `@vantreeseba/graphql-casl` where declarative rules are wanted |
| Subscriptions | `graphql-ws` over `ws` |
| Tests | Vitest + PGLite |

## Workspace layout

```
db/       Drizzle tables, relations, migrations, the connected `db` instance
server/   schema build, resolvers, auth, services, HTTP + WS wiring
app/      client (see simple-ts-frontend or expo-frontend)
```

The arrow only points one way: `db → server → app`.

```
server/src/
  index.ts                  express + apollo + ws wiring, buildContext
  context.ts                Context interface, createLoaders
  errors.ts                 GraphQLError factories, requireUser/requireOwner
  auth.ts, api-keys.ts      credential issuance and verification
  schema/
    index.ts                buildSchema(tables, buildSchemaConfig) → applyCustomResolvers
    build-config.ts         the shared BuildSchemaConfig
    scope.ts                TABLE_SCOPE, QUERY_SCOPE, UNEXPOSED
    validators.ts           zod input schemas
    resolvers/
      index.ts              extensionSDL, attach(), finalizeSchema()
      types.ts              QueryMap / MutationMap / FieldMap
      <domain>.ts           one file per domain
  __generated__/            resolver types — gitignored, never edited
```

## The database

Tables are the source of truth for everything above them. One table per file,
`$inferSelect`/`$inferInsert` for every row type, const-tuple enums shared with
the validators, and `db/src/index.ts` **throws at import if `DATABASE_URL` is
unset** — there is no fallback backend, deliberately.

→ **[`references/db-package.md`](references/db-package.md)** — model file
template, relations, the `exports` subpath split (`@app/db` connects,
`@app/db/schema` does not), migrations.

## The schema

Generated from the tables, then narrowed and extended — in a fixed order:

```
buildSchema → scopeRootFields → extendSchema(extensionSDL) → attach → finalizeSchema
```

Key decisions: **every generated mutation is disabled** (all writes are
hand-written and scoped), which means `Mutation` must be *declared* in the
extension SDL and wired as a root operation; secrets are removed with
`exclude.columns`, not by stripping the output field, because a filter or an
ordering on a secret is an oracle; and presentation order is declared once in
`defaults` rather than by each caller.

→ **[`references/schema-pipeline.md`](references/schema-pipeline.md)** — the
annotated `build-config.ts`, what `extensionSDL` must contain, and why the
assembly order is not negotiable.

## Tenant scoping

**The most load-bearing pattern in the backend.** Three maps in `scope.ts` and
three boot-time invariants that turn a class of data leak into a startup crash:

- `TABLE_SCOPE` — a per-table predicate the library ANDs on *last*, so a caller's
  `where` can only narrow it. Table-level, not field-level, so it covers relation
  fields that no root-field wrapper can reach.
- `QUERY_SCOPE` / `UNEXPOSED` — every generated root field is in exactly one.
- `assertEveryTableScoped` at boot; a generated field in neither map throws; a
  surviving root query that is not `my`-prefixed throws.

→ **[`references/scoping.md`](references/scoping.md)** — the full maps,
`scopeRootFields`, `finalizeSchema`, and the add-a-table checklist.

## Resolvers

Domain files export typed maps — `MutationMap<'myCreateTodo' | ...>` — that are
`Required<Pick<>>` of the generated resolver types, so a field-name typo is a
compile error rather than a silent no-op.

The shape is always: **auth → validate → ownership → write → publish → return the
row.** Guard order is fixed (authentication, then existence, then ownership).
Resolvers return plain Drizzle rows and never reshape them — the codegen
`mappers` and the generated relation resolvers both depend on it.

→ **[`references/resolver-authoring.md`](references/resolver-authoring.md)** —
`types.ts` in full, a worked mutation, the error factories, zod conventions,
partial-update spreads, field resolvers, and DataLoader patterns.

## Auth

One `buildContext` resolves a raw token into a `Context`, and both the HTTP and
WebSocket paths call it through the same `extractToken` normalizer. Chain: session
JWT → hashed API key → `BYPASS_AUTH_UUID` → bare UUID in dev. No match yields an
unauthenticated context, not an error; `requireUser` raises that at the resolver.

→ **[`references/auth.md`](references/auth.md)** — the full chain, JWT issuance,
API key generation and hashing, and the transport wiring.

## Generated files — never edit, never commit

| Path | Produced by |
| --- | --- |
| `schema.graphql` | `npm run generate:schema` |
| `server/src/__generated__/` | `npm run codegen:server` |
| `client/src/__generated__/` | `npm run codegen:client` |
| `db/drizzle/` | `npm run db:generate` |

If a codegen skill is available (`graphql-codegen`), use it for the pipeline
details; otherwise the short version is that `generate:schema` must not connect
to anything, and resolver types must be imported type-only to avoid a bootstrap
cycle.

## Tests

Per-file in-memory PGLite migrated from the real migrations, schema-derived
fixtures with a fixed seed, and drift tests asserting the zod validators and the
SDL still agree. If a `ts-testing` skill is available, follow it; otherwise the
essentials are: build the test schema with the same `buildSchemaConfig` the
server uses, set `env: { DATABASE_URL: '' }` in the Vitest config as a backstop
against a test reaching the real database, and negative-test every guard — the
positive path passing proves nothing about the scope.

## Deployment

Two-stage Docker: bundle the client, then ship a `--omit=dev` server image with
the built bundle copied in. Codegen runs **inside** the image, because
`__generated__/` is gitignored and a stale committed artifact must not be able to
ship.

→ **[`references/dockerfile.md`](references/dockerfile.md)** — the annotated
Dockerfile and the compose file, including why `condition: service_healthy` is
required.

## After changing anything

```bash
npm run codegen && npm run check && npm test
```

Codegen first — a stale `__generated__/` makes `typecheck` report errors that do
not exist.
