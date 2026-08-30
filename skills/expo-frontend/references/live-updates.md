# Live updates

One subscriber for the whole app, mounted in `app/(app)/_layout.tsx`, translating
every server event into the same cache vocabulary local mutations use.

```tsx
export default function AppLayout() {
  // One subscriber for the whole app; pages read the cache it keeps current.
  useLiveUpdates();
  ...
}
```

## Why one

```typescript
/**
 * The app's single subscriber to the server's change streams.
 *
 * Mounted once, in `app/(app)/_layout.tsx`. Every event is translated into the
 * same `lib/cache.ts` vocabulary mutations use, so a change made in another
 * tab, on another device, or by an API key reaches the cache by exactly the
 * route a local mutation would.
 *
 * What this replaced: each page ran its own `useSubscription`, enumerated the
 * entities it thought it cared about, and called its own `refetch()`. That had
 * three problems. The entity list was hand-written per page, so a page that
 * forgot `timeBlock` silently rendered a stale schedule. `refetch()` only
 * refreshes the one query that owns it, so a change reached the page you were
 * looking at and no other. And every page opened its own subscriptions —
 * roughly two dozen live operations for eight screens, each one re-filtering
 * the same broadcast.
 *
 * Invalidating a root field instead reaches every mounted consumer of that
 * field at once, which is why the mapping below can live in one place and be
 * checked once.
 */
```

Three failure modes, all fixed by centralizing: per-page entity lists rot;
`refetch()` only reaches one query; and N pages open N× the sockets.

## The hook

```typescript
import type { DataEntity, TodoEventType } from '@/__generated__/graphql';
import { graphql } from '@/__generated__';
import { DERIVED, type RootField, evictEntity, invalidate } from '@/lib/cache';
import { useApolloClient, useSubscription } from '@apollo/client/react';

const TODOS_UPDATED = graphql(`
  subscription TodosUpdated {
    myTodosUpdated {
      type
      deletedId
      todo { ...Todo_TodoList }
    }
  }
`);

const DATA_CHANGED = graphql(`
  subscription DataChanged {
    myDataChanged { entity ids }
  }
`);

/**
 * Which root fields each `dataChanged` entity invalidates.
 *
 * A `Record` keyed by `DataEntity` rather than a lookup with a default: adding
 * an entity to the SDL then fails to compile here until someone says what it
 * affects, which is the check the per-page entity lists never had.
 *
 * `project` alone does not carry `DERIVED` — creating or archiving a project
 * publishes an `activityType` event too, and that one does.
 */
const DATA_FIELDS: Record<DataEntity, readonly RootField[]> = {
  activityType: ['myActivityTypes', ...DERIVED],
  habit: ['myHabits', ...DERIVED],
  manualEvent: ['myManualEvents', ...DERIVED],
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

## The two details that make it hold

**`Record<DataEntity, …>` is exhaustive.** Adding an entity to the server's SDL
breaks the build here until someone declares what it invalidates. A `Partial<>`
or a lookup with a `?? []` default lets a new entity silently do nothing — which
is exactly the class of bug the per-page lists had.

**Payload shape decides the work.** A subscription that carries the full entity
means Apollo has already normalized it by the time `onData` runs, so an
`updated` event needs nothing but the derived fields dropped. Only a
create/delete touches the list field. `fieldsFor` encodes that once.

## Server side

Two shapes of event:

**Typed, payload-carrying** — for entities where the client benefits from the
object arriving with the event:

```graphql
enum TodoEventType { created updated deleted }

type TodoEvent {
  type: TodoEventType!
  todo: Todo
  deletedId: ID
}
```

**Untyped notification** — for everything else:

```graphql
# Entities without a typed, payload-carrying event stream. The client maps
# each one to the root fields it invalidates (see useLiveUpdates) — the ids
# are informational, letting a listener narrow its response if it wants.
enum DataEntity { habit activityType timeBlock project manualEvent }

type DataChangedEvent {
  entity: DataEntity!
  ids: [ID!]!
}
```

Adding a `DataEntity` value costs one enum entry on the server and one required
map entry on the client. That is the whole extension path, and it is
compiler-checked at both ends.

Mutations publish after the write succeeds:

```typescript
publishTodoEvent(userId, { type: 'created', entity: todo });
```

Events are **per-user** — the publisher takes the userId and the subscription
resolver filters on the authenticated caller. A broadcast that isn't scoped
leaks other tenants' ids.

## Transport

Subscriptions go over `graphql-ws` via a split link. Two things must be right:

```typescript
connectionParams: () => {
  const token = storage.getItem('auth_token');
  return token ? { authorization: `Bearer ${token}` } : {};
},
```

**A function, not an object.** An object is evaluated once at client
construction, so the socket keeps whatever token existed at page load and every
reconnect after a login carries a stale one.

And the server must normalize `Bearer <token>` on the WS path exactly as it does
on HTTP. Passing the raw header value through makes every subscription fail auth
— and clients then reconnect in a tight loop, which shows up as idle CPU burn
rather than as an error.
