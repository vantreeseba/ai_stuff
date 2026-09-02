# Tenant scoping

Every generated read is confined to rows the caller owns, and the confinement is
declared in one file that the boot sequence checks for completeness. This is the
single most load-bearing pattern in the backend: get it wrong and the API serves
other people's rows.

Three artifacts, all in `server/src/schema/scope.ts`:

| Export | Answers |
| --- | --- |
| `TABLE_SCOPE` | which rows of each table the caller may see |
| `QUERY_SCOPE` | which generated root queries are served, and under what name |
| `UNEXPOSED` | which generated root queries are deliberately not served |

## `TABLE_SCOPE` — the tenant boundary

A predicate per table, passed to `buildSchema` as `scope`. The library **ANDs it
on last**, after the caller's `where`, so a caller-supplied filter can only ever
narrow it.

```typescript
import type { ScopeConfig } from '@vantreeseba/drizzle-graphql';
import type { Context } from '../context.ts';
import { requireUser } from '../errors.ts';

/** Scopes a table to rows belonging to the caller, by their own `userId`. */
const ownedByUser = (context: Context) => ({
  userId: { eq: requireUser(context) },
});

export const TABLE_SCOPE: ScopeConfig<Context> = {
  users: (context) => ({ id: { eq: requireUser(context) } }),
  activityTypes: ownedByUser,
  todoLists: ownedByUser,
  todos: ownedByUser,
  habits: ownedByUser,
  projects: ownedByUser,
  apiKeys: (context) => ({
    userId: { eq: requireUser(context) },
    revokedAt: { isNull: true },
  }),
  habitCompletions: (context) => ({
    habit: { userId: { eq: requireUser(context) } },
  }),
  projectNotes: (context) => ({
    project: { userId: { eq: requireUser(context) } },
  }),
};
```

**Why table-level and not field-level.** A root-field wrapper can only scope what
passes through a root resolver, and a nested relation field never does. Before
this existed, `Habit.completions` and `Project.notes` were confined only by the
foreign-key predicate the relation loader happened to AND in — correct, but
incidental, and true only for as long as the dependency kept doing it. Table
scoping covers *every* path that reads a table: list and single queries, relation
fields batched or eager, cursor pages.

**The rules are deliberately not uniform:**

- `users` has no `userId` column. The caller *is* the row, so it scopes by `id`.
- `apiKeys` also hides revoked keys. They are not "the caller's keys" for any
  purpose the API has, and folding it in here keeps a revoked key from being
  resurrected by a caller-supplied `where`.
- `habitCompletions` has no owner column at all, and `projectNotes` owns none
  either; both scope **through the relation** to the parent that does. This is
  why `relations.ts` has to be complete — the relation form resolves through it.

**Writes are unaffected.** `build-config.ts` disables every generated mutation,
so the only writes are hand-written resolvers going through Drizzle directly,
which enforce ownership with their own guard clauses.

## `QUERY_SCOPE` and `UNEXPOSED`

Everything drizzle-graphql generates is in exactly one of these two. A generated
field named in neither throws at boot.

```typescript
export type ScopedField = {
  /** Always `my`-prefixed. */
  as: string;
  /** Key in the Drizzle schema, so the scope can be checked to exist. */
  table: keyof typeof TABLE_SCOPE;
};

export const QUERY_SCOPE: Record<string, ScopedField> = {
  user: { as: 'myProfile', table: 'users' },
  todos: { as: 'myTodos', table: 'todos' },
  projects: { as: 'myProjects', table: 'projects' },
  project: { as: 'myProject', table: 'projects' },
  apiKeys: { as: 'myApiKeys', table: 'apiKeys' },
};

export const UNEXPOSED: ReadonlySet<string> = new Set([
  'habit',
  'habitCompletion',
  'habitCompletions',
  'projectNote',
  'projectNotes',
  'todo',
  'todoList',
  'users',
]);
```

`QUERY_SCOPE` entries carry **no filter** — `TABLE_SCOPE` holds it. `table` names
the entry that must exist for the field to be safe to serve.

**What goes in `UNEXPOSED`.** Single-row variants are redundant with their list
form plus a `where`. `users` is the plural of the one table that scopes by `id`.
Leaves owned by a parent (`Project.notes`, `Habit.completions`) are already
reachable — correctly scoped — by traversing the relation. Adding an entry here
is a deliberate choice not to serve a table.

## `scopeRootFields` — rename, guard, remove

```typescript
export function scopeRootFields(schema: GraphQLSchema): GraphQLSchema {
  return mapSchema(schema, {
    [MapperKind.QUERY_ROOT_FIELD]: (field, fieldName) => {
      const rule = QUERY_SCOPE[fieldName];
      if (!rule) {
        if (!UNEXPOSED.has(fieldName)) {
          throw new Error(
            `Generated query "${fieldName}" is neither exposed in QUERY_SCOPE nor listed in UNEXPOSED`,
          );
        }
        return null;
      }

      if (!TABLE_SCOPE[rule.table]) {
        throw new Error(
          `Query "${rule.as}" reads table "${rule.table}", which has no row scope`,
        );
      }

      const inner = field.resolve;
      if (!inner) {
        throw new Error(`Generated query "${fieldName}" has no resolver`);
      }

      return [
        rule.as,
        {
          ...field,
          resolve: (parent, args, context: Context, info) => {
            requireUser(context);
            return inner(parent, args, context, info);
          },
        },
      ];
    },
  });
}
```

**Rewrap, never re-implement.** The generated resolvers already do filtering,
ordering, limit/offset, and relation loading, and since the tenant predicate
moved into `TABLE_SCOPE` they do the scoping too. Wrapping the resolver already
attached to the field keeps all of it: no second schema, no delegation, and the
field still returns plain Drizzle rows — which the codegen `mappers` and the
`FieldMap` field resolvers both depend on.

**The wrapper's only remaining job** is failing unauthenticated calls at the
root, so `myTodos` without a caller is one `UNAUTHENTICATED` error rather than
whatever the scope hook raises further in.

**Unknown fields are removed, not guarded.** A generated field with no rule is
deleted from the schema, so naming it fails *validation* rather than execution —
and never appears in introspection or client codegen.

**Do not prune here.** The `extensionSDL` applied afterwards references generated
input types that are unreferenced at this point. `finalizeSchema` prunes last.

## Three boot-time invariants

These are what make the pattern hold as the schema grows. Each one converts a
class of silent data leak into a startup crash.

**1. Every Drizzle table has a scope.** Called from `build-config.ts` with the
schema keys, at module scope, so it runs before anything can serve a request:

```typescript
export function assertEveryTableScoped(tableKeys: readonly string[]): void {
  const missing = tableKeys.filter((key) => !(key in TABLE_SCOPE));
  if (missing.length > 0) {
    throw new Error(
      `Drizzle tables with no row scope: ${missing.join(', ')} — add them to TABLE_SCOPE`,
    );
  }
}
```

```typescript
assertEveryTableScoped(
  Object.entries(tables)
    .filter(([, value]) => is(value, PgTable))
    .map(([key]) => key),
);
```

**2. Every generated query is classified.** `scopeRootFields` throws on a field
in neither `QUERY_SCOPE` nor `UNEXPOSED`, and on a `QUERY_SCOPE` entry whose
table has no `TABLE_SCOPE` entry.

**3. Every surviving root field is `my`-prefixed.** `finalizeSchema` is the
backstop — it asserts that `scopeRootFields` and the hand-written `extensionSDL`
between them left nothing unscoped:

```typescript
function finalizeSchema(schema: GraphQLSchema): GraphQLSchema {
  const mapped = mapSchema(schema, {
    // Queries have no public exemption: `PUBLIC_MUTATIONS` is not consulted
    // here, so a query borrowing one of those names still fails the assertion.
    [MapperKind.QUERY_ROOT_FIELD]: (_field, fieldName) => {
      if (!fieldName.startsWith('my')) {
        throw new Error(
          `Query.${fieldName} is not scoped to the caller — every query must be \`my\`-prefixed`,
        );
      }
      return undefined;
    },
    [MapperKind.MUTATION_ROOT_FIELD]: (_field, fieldName) =>
      fieldName.startsWith('my') || PUBLIC_MUTATIONS.has(fieldName)
        ? undefined
        : null,
  });

  // The removed root fields were the only reference to a chunk of the generated
  // input types; prune drops those.
  return pruneSchema(mapped);
}
```

```typescript
/**
 * Mutations reachable without authentication, and so without the `my` prefix.
 * Every other mutation must be `my`-prefixed or `finalizeSchema` removes it.
 */
export const PUBLIC_MUTATIONS = new Set(['requestMagicLink', 'verifyMagicLink']);
```

Note the asymmetry: an unscoped *query* throws (it is always a mistake), an
unscoped *mutation* is removed (drizzle-graphql may still emit some). Queries
have no public exemption at all.

## Adding a table — the checklist

1. `db/src/models/<table>.ts`, re-exported from `models/index.ts`
2. relations in `db/src/relations.ts`
3. `npm run db:generate && npm run db:migrate`
4. `TABLE_SCOPE` entry — **boot fails without it**
5. `QUERY_SCOPE` or `UNEXPOSED` for each generated root field — **boot fails
   without it**
6. `defaults` ordering in `build-config.ts` if it has a natural presentation order
7. `npm run codegen`

Steps 4 and 5 are not optional discipline; they are enforced. That is the design.
