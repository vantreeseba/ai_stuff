# Workspace layout

## The dependency arrow

```
db  →  server  →  app/client
```

It points one way and never the other. `db` knows nothing about GraphQL,
`server` knows nothing about React. A "shared types" package that both ends
import is a sign the arrow has been broken — the shared thing is either a DB
row (belongs in `db`) or a generated type (belongs in `__generated__/`).

Flat for three or four packages; `apps/*` + `packages/*` once there are agents,
a desktop app, and a web client sharing a core.

```
<repo>/
├── db/                  @scope/db
├── server/              @scope/server
├── app/  or  client/    @scope/app
├── codegen.ts
├── codegen.server.ts
├── biome.json
├── vitest.config.ts
├── docker-compose.dev.yml
├── AGENTS.md
├── CLAUDE.md            # one line: "Use AGENTS.md instead."
└── .agents/
```

## Root package.json

```jsonc
{
  "name": "auto-cal",
  "version": "1.0.0",
  "type": "module",
  "private": true,
  "workspaces": ["client", "db", "server"],
  "scripts": {
    "dev": "npm run codegen && concurrently \"npm:dev:server\" \"npm:dev:client\"",
    "dev:server": "npm run dev -w @auto-cal/server",
    "dev:client": "cd client && npx expo start --port 3000",

    "build": "npm run codegen && npm run build:client && npm run build:server",
    "typecheck": "npm run typecheck --workspaces --if-present",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "test": "vitest",

    "codegen": "npm run generate:schema && npm run codegen:server && npm run codegen:client",

    "db:generate": "npm run db:generate -w @auto-cal/db",
    "db:migrate": "npm run db:migrate -w @auto-cal/db",
    "db:studio": "npm run db:studio -w @auto-cal/db",
    "db:up": "docker compose -f docker-compose.dev.yml up -d",
    "db:down": "docker compose -f docker-compose.dev.yml down"
  },
  "devDependencies": { "@biomejs/biome": "^2.4.6", "concurrently": "^9.1.2", "typescript": "~5.9.2" },
  "overrides": { "graphql": "16.13.2", "drizzle-orm": "1.0.0-rc.4" }
}
```

Two patterns worth copying:

- **`--workspaces --if-present`** for anything every package might implement
  (`typecheck`, `test`). No list to keep in sync.
- **`concurrently "npm:dev:server" "npm:dev:client"`** — the `npm:` shorthand
  names sibling scripts, so the dev command stays readable.

## The `overrides` block is load-bearing

```jsonc
"overrides": { "graphql": "16.13.2", "drizzle-orm": "1.0.0-rc.4" }
```

Two copies of `graphql` in one process throws *"another module or realm"* on
the first `instanceof` check, and it surfaces as a schema that will not build
rather than as a version conflict. Two copies of `drizzle-orm` silently produce
rows that fail the ORM's own type guards. Pin both repo-wide the moment a second
package depends on either.

Older npm and some Expo trees need `resolutions` as well as `overrides`; where a
repo has both, keep them at the same version.

## The `db` package

`db` is imported **by package name**, never by relative path, and exposes
subpaths so `server` can take the schema without the connection:

```jsonc
{
  "name": "@auto-cal/db",
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./schema": "./src/schema.ts",
    "./relations": "./src/relations.ts"
  },
  "peerDependencies": { "drizzle-orm": "~1.0.0-rc.2" },
  "devDependencies": { "drizzle-kit": "~1.0.0-rc.2", "env-cmd": "^10.1.0" }
}
```

`drizzle-orm` is a **peerDependency**, not a dependency — the consumer supplies
it, so there is exactly one copy. `postgres` (the driver) is a real dependency.

Pointing `exports` at `src/*.ts` rather than `dist/` is what lets the server run
the workspace source directly under type stripping, with no build step for `db`.
Packages that do build (philotes' `db`) point at `dist/` and add a `build`
script the root `dev` runs first.

## Env files

One `.env` at the repo root; workspaces reach it with `--env-file=../.env`
(Node 22+) or `env-cmd -f ../.env` (for tools that spawn their own process, like
`drizzle-kit`). Never a `.env` per workspace — the same `DATABASE_URL` in three
files is how a migration lands in the wrong database.

## Worktrees

```bash
npm ci --prefer-offline --no-audit
```

Prefers the local npm cache, which makes a fresh worktree install in seconds
rather than minutes.
