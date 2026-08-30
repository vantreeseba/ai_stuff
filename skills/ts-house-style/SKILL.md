---
name: ts-house-style
description: >
  The baseline TypeScript house style for cubicecho projects: npm workspaces,
  ESM + Node type stripping, Biome, the AGENTS.md / .agents/ documentation
  convention, conventional commits, and git rules. Load this whenever writing
  or reviewing TypeScript in a cubicecho repo, and alongside ts-backend,
  simple-ts-frontend, expo-frontend, ts-testing, ts-library, or mcp-server.
version: 0.0.1
license: MIT
---

# TypeScript House Style

The conventions every cubicecho TypeScript project shares, regardless of whether
it is a server, a client, a library, or an MCP server.

Stack-specific skills build on top of this one where they exist —
`ts-backend`, `simple-ts-frontend`, `expo-frontend`, `graphql-codegen`,
`ts-testing`, `ts-library`, `mcp-server`. Each of them stands alone, so none of
them is a prerequisite for this one or for each other.

## Non-negotiables

- **ESM only.** `"type": "module"` in every `package.json`. No CJS source.
- **Node 22+.** Server and tool code runs `.ts` directly via
  `node --experimental-strip-types` (or `tsx`). When type stripping is used,
  **every relative import carries a `.ts` extension** — `import { db } from './db.ts'`.
  A `tsc` build for `dist/` uses `rewriteRelativeImportExtensions`.
- **Biome** is the only formatter and linter. No ESLint, no Prettier.
- **npm workspaces.** No pnpm, no yarn, no Turborepo, no Nx.
- **Strict TypeScript.** `strict: true`, no implicit `any`, `unknown` over `any`.
- **Never hand-write a type a tool can infer.** Drizzle `$inferSelect`,
  zod `z.infer`, graphql-codegen resolver types. A duplicated type is a bug
  waiting for a schema change.

## Repository layout

A monorepo splits by *layer*, not by feature, and the dependency arrow only ever
points one way:

```
db  →  server  →  app/client
```

Root scripts follow a fixed vocabulary so any repo can be driven without reading
its `package.json`:

| Script | Meaning |
| --- | --- |
| `npm run dev` | everything, concurrently |
| `npm run dev:server` / `dev:app` | one half |
| `npm run build` | codegen, then build every workspace |
| `npm run typecheck` | `tsc --noEmit` across all workspaces |
| `npm run lint` / `lint:fix` | `biome check .` / `biome check --write .` |
| `npm run check` | lint + typecheck together (CI's gate) |
| `npm test` | the whole suite, once |
| `npm run codegen` | the full generate pipeline |
| `npm run db:generate` / `db:migrate` / `db:studio` | drizzle-kit |

**Prefer `package.json` scripts over ad-hoc `npx`.** The scripts wrap env-file
loading, workspace targeting, and flag conventions; an `npx drizzle-kit generate`
run by hand usually misses the `.env`.

→ **[`references/workspace-layout.md`](references/workspace-layout.md)** — root
and workspace `package.json` templates, the `db` subpath-exports pattern, why
`overrides` on `graphql`/`drizzle-orm` is load-bearing, env files, worktrees.

## Code style

Biome-enforced: single quotes, semicolons always, trailing commas everywhere,
2-space indent, LF, arrow parens always, 120-char width (80 in older repos —
follow the repo's config).

Naming: files `kebab-case.ts(x)`, components `PascalCase`, variables and
functions `camelCase`, types and interfaces `PascalCase`, true constants
`SCREAMING_SNAKE_CASE`. Unused parameters prefixed `_`. `interface` for object
shapes, `type` for unions, intersections, and utilities.

`__generated__/`, `dist/`, `drizzle/`, `*.gen.ts` are excluded from linting and
formatting. Generated code is never hand-edited and never reviewed.

→ **[`references/biome.json`](references/biome.json)** — the canonical config,
copy-paste ready.
→ **[`references/biome-notes.md`](references/biome-notes.md)** — why each rule is
escalated (`useImportType` is a *runtime* concern under type stripping), and the
v1↔v2 schema differences.

## Recurring patterns

**Always use curly braces.** No single-line `if` bodies.

```typescript
// bad
if (!user) throw new Error('Not found');

// good
if (!user) {
  throw new Error('Not found');
}
```

**Const-tuple enums, never TS `enum`.** TS enums are nominal, which breaks
anything that has to return the plain string.

```typescript
export const FREQUENCY_UNITS = ['week', 'month'] as const;
export type FrequencyUnit = (typeof FREQUENCY_UNITS)[number];
```

**Never swallow an error — rethrow with context.**

```typescript
try {
  await client.connect(transport);
} catch (cause) {
  throw new Error(`Failed to connect to server "${name}"`, { cause });
}
```

**Validate at boundaries, trust inside.** Zod at the resolver argument, the
request body, the env, the config file. Never re-validate mid-stack.

**Path alias `@/`** maps to the frontend workspace's `src/`. Cross-workspace
imports use the package name (`@auto-cal/db`), never `../../db`.

## Documentation

`AGENTS.md` at the root is the single source of truth; `CLAUDE.md` is a one-line
pointer at it. Everything deeper goes in `.agents/*.md`, and **every new
`.agents/` file is added to the reference list in `AGENTS.md`** — a file nothing
links to will not be read.

Planning documents live in `.agents/`, never at the repo root.

→ **[`references/agents-md-template.md`](references/agents-md-template.md)** —
the fill-in template, the standard `.agents/` file set, and the convention for
recording ideas you decided *against* building.

## Git

- **`git pull --no-rebase`** — merge, never rebase.
- **Do not add `Co-Authored-By` trailers** to commit messages.
- **Conventional Commits**: `type(scope): summary`, imperative, under ~72 chars,
  one logical change per commit. On library repos these drive semantic-release:
  `feat:` minor, `fix:` patch, `BREAKING CHANGE:` major; `chore:`/`docs:`/
  `test:`/`ci:` do not publish.
- **Run `npm run check` and `npm test` before every commit.**

## After every chunk of work

```bash
npm run lint:fix && npm run typecheck
```

If lint errors survive `lint:fix`, run `npx biome check --write --unsafe .`.
Run codegen first if anything touched a schema — a stale `__generated__/` makes
`typecheck` report errors that do not exist.
