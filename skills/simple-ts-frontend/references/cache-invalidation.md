# Cache invalidation

> **Two conventions exist across the house repos.** Smaller apps pass
> `refetchQueries: [{ query: GET_PERSONS }]` on mutations that change lists.
> Larger ones replaced that with field-level eviction, below. **Follow whatever
> the repo already does; do not mix them.** The eviction approach is the one to
> reach for on anything with more than a handful of pages, and the rationale for
> the switch is worth reading either way.

## What normalization already handles

Apollo normalizes every object carrying an `id`, so **a mutation that returns the
entity it changed already patches every list and detail view holding it** — no
refetch, no round trip. Two things it cannot do:

1. notice that a list **gained or lost a member**
2. notice that a **server-computed field** no longer reflects the data it was
   derived from

Those are the only two cases needing help. Everything else is free — a mutation
returning the updated row needs no cache work at all.

## Why not `refetchQueries`

The older approach named the affected *queries*:

```typescript
refetchQueries: ['GetTodoListsPage', 'GetProjectDetail']
```

That couples every mutation to the set of pages that happened to exist when it
was written. Miss one and it silently shows stale data — which is how one app's
schedule query stopped refreshing when a todo's estimated length changed.
**Naming the schema *field* instead invalidates it for every consumer, including
pages added later.**

## `lib/cache.ts`

```typescript
import type { ApolloCache, Reference } from '@apollo/client';

/**
 * Root `Query` fields these helpers can invalidate.
 *
 * A `const` tuple rather than bare strings, so the helpers take a checked
 * union; `cache.test.ts` asserts the tuple against the SDL, which catches a
 * field that gets renamed or dropped on the server.
 */
export const ROOT_FIELDS = [
  'myActivityTypes',
  'myHabits',
  'myProfile',
  'myProject',
  'myProjects',
  'mySchedule',
  'myStats',
  'myTodoLists',
  'myTodos',
] as const;

export type RootField = (typeof ROOT_FIELDS)[number];

/**
 * The fields the server recomputes rather than stores: the scheduler rebuilds
 * `mySchedule` from scratch on every call, and the stats queries aggregate
 * todos and habit completions. No mutation result can patch these, so any
 * write that could move them has to drop them.
 *
 * Spread it — `invalidate(cache, 'myTodos', ...DERIVED)`.
 */
export const DERIVED: readonly RootField[] = ['mySchedule', 'myStats'];

/**
 * Forget the cached results of the named root fields.
 *
 * Eviction is by field name, so it covers every argument variation at once —
 * `mySchedule` for all weeks, not just the one on screen. Active queries
 * reading an evicted field re-fetch (the default `cache-and-network` policy);
 * queries for screens that aren't mounted simply have no cached value to go
 * stale.
 */
export function invalidate(cache: ApolloCache, ...fields: readonly RootField[]): void {
  for (const fieldName of fields) {
    cache.evict({ id: 'ROOT_QUERY', fieldName });
  }
  cache.gc();
}

/**
 * Add a newly-created entity to a list field on its parent — `Project.notes`
 * after adding a note.
 *
 * `invalidate` only reaches root fields; a nested list has no `ROOT_QUERY`
 * entry to evict. Splicing the reference in is also better than re-fetching
 * here: the new item is in the cache by the time the mutation promise
 * resolves, so a caller that wants to select or focus it can do so without
 * waiting for a round trip.
 *
 * Appends, which matches every list the server returns in insertion or
 * position order. A list ordered any other way needs its own `cache.modify`.
 */
export function appendToField(
  cache: ApolloCache,
  parent: { __typename: string; id: string },
  fieldName: string,
  entity: { __typename?: string; id: string },
): void {
  const parentId = cache.identify(parent);
  if (!parentId) return;
  cache.modify({
    id: parentId,
    fields: {
      [fieldName]: (existing, { toReference }) => {
        const ref = toReference(entity);
        if (!ref) return existing;
        return [...((existing as readonly Reference[] | undefined) ?? []), ref];
      },
    },
  });
}

/**
 * Drop a deleted entity from the cache.
 *
 * Lists holding it do not need rewriting: Apollo filters dangling references
 * out when it reads an array, so the item disappears from every query that
 * had it without any of them being named here.
 *
 * `id` is widened to accept a number because the generated `Scalars['ID']`
 * input type is `string | number`, and the usual caller passes the mutation's
 * own variables straight through.
 */
export function evictEntity(cache: ApolloCache, __typename: string, id: string | number): void {
  const cacheId = cache.identify({ __typename, id: String(id) });
  if (!cacheId) return;
  cache.evict({ id: cacheId });
  cache.gc();
}
```

## Using them

```tsx
const [createTodo] = useMutation(CREATE_TODO, {
  update: (cache) => invalidate(cache, 'myTodos', ...DERIVED),
});

const [updateTodo] = useMutation(UPDATE_TODO, {
  // The mutation returns the Todo, so normalization patches every view of it.
  // Only the computed fields need dropping.
  update: (cache) => invalidate(cache, ...DERIVED),
});

const [deleteTodo] = useMutation(DELETE_TODO, {
  update: (cache, _result, { variables }) => {
    evictEntity(cache, 'Todo', variables!.id);
    invalidate(cache, 'myTodos', ...DERIVED);
  },
});

const [addNote] = useMutation(ADD_NOTE, {
  update: (cache, { data }) => {
    if (!data) return;
    appendToField(cache, { __typename: 'Project', id: projectId }, 'notes', data.myCreateProjectNote);
  },
});
```

The decision, in three lines:

| The mutation… | Do |
| --- | --- |
| updates an entity it returns | `invalidate(cache, ...DERIVED)` — or nothing, if there are none |
| creates or deletes a member of a **root** list | `invalidate(cache, '<thatField>', ...DERIVED)` |
| creates a member of a **nested** list | `appendToField(...)` |
| deletes anything | `evictEntity(...)`, plus the list field |

## Live updates from subscriptions

Mount **one** subscriber for the whole app, in the root layout, and translate
every event into the same `invalidate` / `evictEntity` vocabulary mutations use.
A change made in another tab, on another device, or by an API key then reaches
the cache by exactly the route a local mutation would.

```typescript
/**
 * What this replaced: each page ran its own `useSubscription`, enumerated the
 * entities it thought it cared about, and called its own `refetch()`. That had
 * three problems. The entity list was hand-written per page, so a page that
 * forgot `timeBlock` silently rendered a stale schedule. `refetch()` only
 * refreshes the one query that owns it, so a change reached the page you were
 * looking at and no other. And every page opened its own subscriptions —
 * roughly two dozen live operations for eight screens, each re-filtering the
 * same broadcast.
 */

/**
 * Which root fields each `dataChanged` entity invalidates.
 *
 * A `Record` keyed by `DataEntity` rather than a lookup with a default: adding
 * an entity to the SDL then fails to compile here until someone says what it
 * affects, which is the check the per-page entity lists never had.
 */
const DATA_FIELDS: Record<DataEntity, readonly RootField[]> = {
  activityType: ['myActivityTypes', ...DERIVED],
  habit: ['myHabits', ...DERIVED],
  project: ['myProjects', 'myProject'],
  timeBlock: ['myTimeBlocks', ...DERIVED],
};

/**
 * The subscription payloads carry the full entity, so Apollo has already
 * normalized it by the time these run — an `updated` event needs nothing but
 * the derived fields dropped. Only membership changes touch the list field.
 */
function fieldsFor(type: TodoEventType, listField: RootField): readonly RootField[] {
  return type === 'updated' ? DERIVED : [listField, ...DERIVED];
}

export function useLiveUpdates(): void {
  const { cache } = useApolloClient();

  useSubscription(TODOS_UPDATED, {
    onData: ({ data }) => {
      const event = data.data?.myTodosUpdated;
      if (!event) return;
      if (event.deletedId) evictEntity(cache, 'Todo', event.deletedId);
      invalidate(cache, ...fieldsFor(event.type, 'myTodos'));
    },
  });

  useSubscription(DATA_CHANGED, {
    onData: ({ data }) => {
      const event = data.data?.myDataChanged;
      if (!event) return;
      invalidate(cache, ...DATA_FIELDS[event.entity]);
    },
  });
}
```

The `Record<DataEntity, …>` is the important detail: it is *exhaustive*, so
adding an entity to the SDL breaks the build until someone declares what it
affects. A `Partial` or a lookup-with-default would let a new entity silently do
nothing.

## Test the tuple against the SDL

`ROOT_FIELDS` is a hand-maintained list of server field names — exactly the kind
of thing that rots. A test asserting the tuple against the printed schema catches
a renamed or dropped field at CI rather than at runtime. See the `ts-testing`
skill if it is available.
