# The `db` package

The bottom of the dependency arrow. It owns the Drizzle table definitions, the
relation graph, the migrations, and the single connected `db` instance. Nothing
in it imports from `server/` or `app/`.

## Layout

```
db/
  drizzle/                 # generated migrations — never hand-edited
  src/
    models/
      index.ts             # export * from every model file
      enums.ts             # const-tuple enums shared by tables
      users.ts
      todos.ts
      ...                  # one file per table
    schema.ts              # export * from './models/index.ts'
    relations.ts           # defineRelations over the whole schema
    index.ts               # connects, migrates, exports `db` and `DB`
    migrator.ts            # standalone migrate entry point
  package.json
```

**One table per file.** `models/index.ts` re-exports them all, `schema.ts`
re-exports that. Codegen, `drizzle.config.ts`, and `assertEveryTableScoped` all
consume `schema.ts` as `import * as tables`, so a table that isn't re-exported
is invisible to every one of them.

## A model file

```typescript
import { boolean, integer, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';
import { todoLists } from './todo_lists.ts';
import { users } from './users.ts';

export const todos = pgTable('todos', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id')
    .notNull()
    .references(() => users.id, { onDelete: 'cascade' }),
  listId: uuid('list_id')
    .notNull()
    .references(() => todoLists.id, { onDelete: 'restrict' }),
  title: text('title').notNull(),
  description: text('description'),
  priority: integer('priority').notNull().default(0),
  dueAt: timestamp('due_at'),
  completedAt: timestamp('completed_at'),
  createdAt: timestamp('created_at').notNull().defaultNow(),
  updatedAt: timestamp('updated_at').notNull().defaultNow(),
});

export type Todo = typeof todos.$inferSelect;
export type NewTodo = typeof todos.$inferInsert;
```

Rules that hold across every model file:

- **Table keys are regular plurals** (`todos`, `apiKeys`, `todoLists`). The
  GraphQL `typeNameMapper` strips a trailing `s` to get the singular type name,
  so an irregular plural produces a wrong type name silently.
- **Columns are `snake_case` in the DB, `camelCase` in TS.** The string argument
  is the DB name; the object key is the TS name. Drizzle does not infer this.
- **Every table exports `$inferSelect` and `$inferInsert` types.** Never
  hand-write a row shape. `Todo` and `NewTodo` are what resolvers, loaders, and
  codegen `mappers` all refer to.
- **`onDelete` is always explicit.** `cascade` for rows owned by the deleted
  parent, `restrict` for references that should block the delete.
- **`createdAt` / `updatedAt` on every table**, both `notNull().defaultNow()`.
  `updatedAt` is set by hand in update resolvers (`updatedAt: new Date()`).

## Enums

Never `enum`. A const tuple, in `models/enums.ts`, reused by both the column and
the zod validator:

```typescript
export const PROJECT_STATUSES = ['active', 'archived'] as const;
export type ProjectStatus = (typeof PROJECT_STATUSES)[number];
```

```typescript
status: text('status', { enum: PROJECT_STATUSES }).notNull().default('active'),
```

```typescript
status: z.enum(PROJECT_STATUSES).optional(),   // validators.ts
```

One source, three consumers. Adding a status is a one-line change that a drift
test will confirm reached the SDL.

## Relations

`relations.ts` declares the whole graph in one `defineRelations` call. This is
what drizzle-graphql turns into relation fields, and what the relation-form
scope predicates (`{ habit: { userId: { eq } } }`) traverse.

```typescript
import { defineRelations } from 'drizzle-orm';
import * as schema from './schema.ts';

export const relations = defineRelations(schema, (r) => ({
  users: {
    todos: r.many.todos({ from: r.users.id, to: r.todos.userId }),
    projects: r.many.projects({ from: r.users.id, to: r.projects.userId }),
  },
  todos: {
    user: r.one.users({ from: r.todos.userId, to: r.users.id }),
    list: r.one.todoLists({ from: r.todos.listId, to: r.todoLists.id }),
  },
}));
```

## `index.ts` — connect, migrate, export

```typescript
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { drizzle } from 'drizzle-orm/postgres-js';
import { migrate } from 'drizzle-orm/postgres-js/migrator';
import postgres from 'postgres';
import { relations } from './relations.ts';
import * as schema from './schema.ts';

const databaseUrl = process.env.DATABASE_URL;

// Postgres is the only runtime backend. PGLite (WASM) used to be the
// zero-config fallback, but it drives PostgreSQL's event loop with
// `setTimeout(fn, 0)` — a busy-wait that burns CPU at idle — so a deploy that
// lost its DATABASE_URL silently degraded instead of failing. Fail loudly.
// Tests still use PGLite, but they construct it themselves and never reach
// this module.
if (!databaseUrl) {
  throw new Error(
    'DATABASE_URL is required. Postgres is the only supported backend — ' +
      'run `npm run db:up` for a local instance, or see .agents/deployment.md.',
  );
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const migrationsFolder = path.resolve(__dirname, '../drizzle');

const client = postgres(databaseUrl);
const db = drizzle({ client, relations });

await migrate(db, { migrationsFolder });

export { db };
export type DB = typeof db;
export { schema };
export * from './schema.ts';
```

**Throw at import time if `DATABASE_URL` is missing.** No fallback backend. The
rationale is in the comment and it is the whole reason the rule exists: a silent
fallback turns a broken deploy into a slow one, which is much harder to notice.

**Top-level `await migrate(...)`.** The module is ESM, so importing `@app/db`
guarantees a migrated database. Nothing needs to remember to migrate first.

## `package.json`

```json
{
  "name": "@auto-cal/db",
  "version": "1.0.0",
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./schema": "./src/schema.ts",
    "./relations": "./src/relations.ts"
  },
  "scripts": {
    "migrate": "env-cmd -f ../.env node --experimental-strip-types src/migrator.ts",
    "db:generate": "env-cmd -f ../.env drizzle-kit generate",
    "db:migrate": "npm run migrate",
    "db:studio": "env-cmd -f ../.env drizzle-kit studio"
  },
  "dependencies": { "postgres": "^3.4.9" },
  "peerDependencies": { "drizzle-orm": "1.0.0-rc.5-ab785fc" },
  "devDependencies": {
    "@types/node": "^25.6.0",
    "drizzle-kit": "1.0.0-rc.5-ab785fc",
    "env-cmd": "^10.1.0"
  }
}
```

**Three subpaths, and the split matters.** `@app/db` connects; `@app/db/schema`
does not. Anything that only needs table definitions — codegen, tests, build
config, scope maps — imports `/schema` and stays connection-free. Importing the
root from those would drag a live Postgres connection into a codegen run.

**`drizzle-orm` is a `peerDependency`.** Two copies of Drizzle in one process
produce the same class-identity failures two copies of `graphql` do. See the
root `overrides` block in the workspace layout reference.

**`exports` point at `.ts` source.** No build step; consumers run type stripping.

## Migrations

```bash
npm run db:generate    # after any schema.ts change — writes db/drizzle/
npm run db:migrate     # apply
npm run db:studio      # browse
```

Generated SQL in `db/drizzle/` is committed and never hand-edited. Change the
model file and regenerate. `drizzle.config.ts` lives at the repo root:

```typescript
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: 'db/src/schema.ts',
  out: 'db/drizzle',
  dialect: 'postgresql',
  dbCredentials: {
    url: process.env.DATABASE_URL ?? 'postgresql://localhost:5432/autocal',
  },
});
```

Always drive drizzle-kit through the npm scripts — they wrap `env-cmd -f ../.env`,
and a bare `npx drizzle-kit generate` runs without the connection string.
