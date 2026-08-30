# Writing resolvers

## Typed resolver maps

Each domain file exports plain objects keyed by field name, typed with helpers
that are `Pick`s of the resolver types graphql-codegen derives from the SDL.

`server/src/schema/resolvers/types.ts`:

```typescript
/**
 * Note the import is type-only. `__generated__/resolvers.ts` is produced *from*
 * the SDL that `generate_schema.ts` prints by importing this module's siblings,
 * so a value import would be a cycle — Node's type stripping erases this one
 * before it can bite, which is what lets codegen bootstrap from a clean tree.
 */
import type {
  MutationResolvers,
  QueryResolvers,
  Resolvers,
  SubscriptionResolvers,
} from '../../__generated__/resolvers.ts';

export type QueryMap<K extends keyof QueryResolvers> = Required<Pick<QueryResolvers, K>>;

export type MutationMap<K extends keyof MutationResolvers> = Required<Pick<MutationResolvers, K>>;

export type SubscriptionMap<K extends keyof SubscriptionResolvers> = Required<
  Pick<SubscriptionResolvers, K>
>;

/**
 * The same thing for a field on an object type — `FieldMap<'Todo', 'activityType'>`.
 *
 * The parent argument comes from `codegen.server.ts`'s `mappers`, so it is the
 * Drizzle row the resolver above actually returned (`TodoRow`, not the GraphQL
 * `Todo`).
 */
export type FieldMap<
  T extends keyof Resolvers,
  K extends keyof NonNullable<Resolvers[T]>,
> = Required<Pick<NonNullable<Resolvers[T]>, K>>;
```

This buys three things the older `queryFields.myThing!.resolve = ...` pattern
could not:

- a typo in a field name is a **compile error**, not a silent no-op resolver
- `args` and the return value are checked against the SDL, instead of being
  hand-annotated at each call site (`args: { id: string }`)
- no `!` assertions, so no lint suppressions

`Required<Pick<…>>` rather than `Pick<…>`: every key named in the type parameter
must actually be implemented.

**The type-only import is load-bearing.** `__generated__/resolvers.ts` is
produced *from* the SDL that the schema-generation script prints by importing
this module's siblings. A value import would be a genuine cycle; type stripping
erases this one before it can bite, which is what lets codegen bootstrap from a
clean tree.

## A mutation resolver

```typescript
import { todos } from '@auto-cal/db/schema';
import { eq } from 'drizzle-orm';
import { requireUser } from '../../errors.ts';
import { CreateTodoInput, UpdateTodoInput } from '../validators.ts';
import { loadOwned } from './load.ts';
import { publishTodoEvent } from './subscriptions.ts';
import type { MutationMap } from './types.ts';

export const todoMutations: MutationMap<'myCreateTodo' | 'myUpdateTodo' | 'myDeleteTodo'> = {
  myCreateTodo: async (_parent, args, context) => {
    const userId = requireUser(context);
    const input = CreateTodoInput.parse(args.input);

    // Validate list ownership before insert
    await loadOwned(context, 'todoLists', input.listId, userId);

    const [todo] = await context.db
      .insert(todos)
      .values({
        userId,
        listId: input.listId,
        title: input.title,
        description: input.description,
        priority: input.priority,
        dueAt: input.dueAt ? new Date(input.dueAt) : null,
      })
      .returning();
    if (!todo) throw new Error('Failed to create todo');

    publishTodoEvent(userId, { type: 'created', entity: todo });
    return todo;
  },
};
```

The shape is always the same: **auth → validate → ownership → write → publish →
return the row**.

## Guard-clause order

Fixed, and in this order:

1. **Authentication** — `const userId = requireUser(context);`
2. **Existence** — `if (!row) throw notFound('Todo', id);`
3. **Ownership** — `if (row.userId !== userId) throw forbidden();`

`requireOwner` collapses 2 and 3:

```typescript
export function requireOwner<T extends { userId: string }>(
  row: T | undefined,
  entity: string,
  id: string,
  userId: string,
): T {
  if (!row) throw notFound(entity, id);
  if (row.userId !== userId) throw forbidden();
  return row;
}
```

The order carries a documented tradeoff: a row owned by someone else answers
`FORBIDDEN` rather than `NOT_FOUND`, which confirms the id exists. Answering
`NOT_FOUND` for both would close that, but it is a behaviour change with its own
debugging cost. It is a deliberate choice, not an oversight — don't "fix" it
silently as part of unrelated work.

## Errors

Never throw a bare `Error` from a resolver. Everything the client needs to
distinguish gets a code in `extensions.code`, because the client branches on it
structurally rather than matching message text.

`server/src/errors.ts`:

```typescript
export const ErrorCode = {
  Unauthenticated: 'UNAUTHENTICATED',
  Forbidden: 'FORBIDDEN',
  NotFound: 'NOT_FOUND',
  BadUserInput: 'BAD_USER_INPUT',
} as const;

/** No usable credentials on the request. The client should re-authenticate. */
export function unauthenticated(): GraphQLError {
  return new GraphQLError('Not authenticated', {
    extensions: { code: ErrorCode.Unauthenticated },
  });
}

/** Authenticated, but the row belongs to someone else. */
export function forbidden(message = 'Forbidden'): GraphQLError {
  return new GraphQLError(message, { extensions: { code: ErrorCode.Forbidden } });
}

/** Row does not exist. */
export function notFound(entity: string, id: string): GraphQLError {
  return new GraphQLError(`${entity} ${id} not found`, {
    extensions: { code: ErrorCode.NotFound, entity, id },
  });
}

/** Caller-fixable input problem: failed validation, an illegal state change. */
export function badUserInput(
  message: string,
  extensions: Record<string, unknown> = {},
): GraphQLError {
  return new GraphQLError(message, {
    extensions: { code: ErrorCode.BadUserInput, ...extensions },
  });
}

/**
 * Narrow an unauthenticated context to a user id. Returning the id (rather than
 * asserting) means callers stop reaching for `context.userId!` afterwards.
 */
export function requireUser(context: { userId?: string }): string {
  if (!context.userId) throw unauthenticated();
  return context.userId;
}
```

Codes are what let `formatError` scrub the messages of genuinely unexpected
errors without breaking the client's auth handling.

## Validation with zod

Every mutation parses `args.input` through a zod schema at the top of the
resolver, and nothing re-validates deeper in.

`server/src/schema/validators.ts`:

```typescript
import { PROJECT_STATUSES } from '@auto-cal/db/schema';
import { z } from 'zod';

export const CreateProjectInput = z.object({
  name: z.string().min(1).max(100),
  parentActivityTypeId: z.string().uuid().nullable().optional(),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/, 'Must be a valid hex color').optional(),
  createList: z.boolean().default(true),
});

export const UpdateProjectInput = z.object({
  id: z.string().uuid(),
  name: z.string().min(1).max(100).optional(),
  status: z.enum(PROJECT_STATUSES).optional(),
});
```

Rules:

- **Enums come from the db package's const tuples** (`z.enum(PROJECT_STATUSES)`),
  never re-listed. One source for the column, the validator, and the SDL.
- **Bound every string.** `.max(100)` on a name, `.max(50000)` on a body.
- **Defaults live here**, not in the resolver body (`createList: z.boolean().default(true)`).
- The zod schema and the SDL input type say the same thing twice, in two
  languages. A **drift test** asserts they agree — see the `ts-testing` skill if
  it is available.

`ZodError` is mapped to `BAD_USER_INPUT` centrally in the Apollo `formatError`
hook, so resolvers just let `.parse()` throw.

## Partial updates

`.set()` with spread guards, so an omitted field is left alone and an explicit
`null` clears it:

```typescript
.set({
  ...(input.title !== undefined && { title: input.title }),
  ...(input.priority !== undefined && { priority: input.priority }),
  ...('dueAt' in input && { dueAt: input.dueAt ? new Date(input.dueAt) : null }),
  updatedAt: new Date(),
})
```

Note the two forms: `!== undefined` for "was it supplied", `'x' in input` for
fields where `null` is a meaningful value distinct from absent. And `updatedAt`
is always set by hand.

## Return plain Drizzle rows

Resolvers return `.returning()` rows and nothing else — no mapping, no
reshaping, no `{ ...row, computed }`. Two things depend on it:

- codegen `mappers` type the parent of every field resolver as the `*Row` type
- drizzle-graphql's relation resolvers read the row's foreign keys to batch-load
  relation fields

Returning a reshaped object breaks both, and the second one breaks *silently* —
relation fields just resolve to null.

## Field resolvers

Only for what the generated machinery can't do: custom SDL fields, derived hops,
and relations needing specific handling. Everything that is a plain Drizzle
relation already has a working resolver.

```typescript
export const todoFields: FieldMap<'Todo', 'activityType'> = {
  activityType: async (parent, _args, context) => {
    const list = await context.loaders.todoList.load(parent.listId);
    if (!list) return null;
    return context.loaders.activityType.load(list.activityTypeId);
  },
};
```

`parent` is the Drizzle row, so `parent.listId` is checked against the actual
column. Hand-written parent shapes like `parent: { listId: string }` were
approximating this: correct until the column is renamed, and unchecked either way.

## Context and DataLoader

```typescript
export interface Context {
  db: DB;
  userId?: string; // undefined = not authenticated
  apiKey?: { id: string; scopes: ApiKeyScope[] };
  loaders: ReturnType<typeof createLoaders>;
  appBaseUrl: string;
}
```

`loaders` is typed as `ReturnType<typeof createLoaders>` — adding a loader needs
no second edit.

**Loaders are created per request.** A DataLoader is a request-scoped cache; a
module-level one would serve stale rows across requests and across users.

One-to-one:

```typescript
activityType: new DataLoader<string, ActivityType | null>(async (ids) => {
  const rows = (await db.query.activityTypes.findMany({
    where: { id: { in: [...ids] } },
  })) as ActivityType[];
  const byId = new Map(rows.map((r) => [r.id, r]));
  return ids.map((id) => byId.get(id) ?? null);
}),
```

One-to-many — group into buckets, return `[]` for a miss:

```typescript
// to-many: lists grouped by projectId (one-per-project business rule, but
// batched to-many so Project.list resolves without an N+1).
todoListsByProject: new DataLoader<string, TodoList[]>(async (projectIds) => {
  const rows = (await db.query.todoLists.findMany({
    where: { projectId: { in: [...projectIds] } },
    orderBy: { createdAt: 'asc' },
  })) as TodoList[];
  const byProject = new Map<string, TodoList[]>();
  for (const row of rows) {
    if (!row.projectId) continue;
    const bucket = byProject.get(row.projectId) ?? [];
    bucket.push(row);
    byProject.set(row.projectId, bucket);
  }
  return projectIds.map((id) => byProject.get(id) ?? []);
}),
```

The return array must be the same length as `ids` and in the same order.
DataLoader matches by position, not by key — a filtered result silently pairs
rows with the wrong ids.
