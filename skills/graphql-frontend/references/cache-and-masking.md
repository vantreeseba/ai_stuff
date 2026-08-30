# Cache and masking

Masking does not create a second store. There is one normalized cache; masking
controls **what a given consumer is allowed to see of it**.

## Normalization is the substrate

Apollo splits every result into entities keyed `__typename:id` and stores fields
against those keys. Two queries that both fetched person `7` share one cache
entry, so a mutation returning person `7` updates both.

This is why `id` is non-negotiable in every fragment. An object with no key is
stored inline under its parent, cannot be shared, cannot be re-read by
`useFragment`, and is invisible to `cache.modify`.

For a type keyed by something else, or one that must **not** be normalized:

```typescript
new InMemoryCache({
  typePolicies: {
    Person: { keyFields: ['id'] },              // default; stated for clarity
    Setting: { keyFields: ['namespace', 'key'] },
    // A computed view with no stable identity — normalizing it makes two
    // different computations collide on one cache entry.
    ScheduledItem: { keyFields: false },
  },
});
```

`keyFields: false` is the right answer for server-computed projections that have
no identity of their own. Getting this wrong produces the confusing failure mode
where changing one row's data changes another's.

## Live reads with `useFragment`

```tsx
function PersonRow({ person: from }: { person: FragmentType<typeof PERSON_ROW> }) {
  const { data: person, complete } = useFragment({ fragment: PERSON_ROW, from });

  if (!complete) return <Spinner />;
  return <Card>{person.firstName} — {person.email}</Card>;
}
```

This subscribes the row to *its own entity's* fields. A mutation touching person
`7` re-renders only person `7`'s row; the query above is not re-run and sibling
rows do not re-render. On a long list that is the difference between a smooth
update and a full re-render.

### `useFragment` or `getFragmentData`?

| Use | When |
| --- | --- |
| `getFragmentData(FRAG, prop)` | the parent re-rendering is the right trigger — static lists, detail panes, anything already re-rendered by its query |
| `useFragment({ fragment, from })` | the component must react to cache changes independently — long lists, rows mutated in place, anything a subscription touches |

Start with `getFragmentData`. It is free, it has no `complete` state to handle,
and it never desynchronises. Move a component to `useFragment` when profiling or
an actual stale-row bug says to — not preemptively.

`from` also accepts an identity object, for reading an entity you have only the
id of:

```tsx
const { data, complete } = useFragment({
  fragment: PERSON_ROW,
  from: { __typename: 'Person', id },
});
```

## `complete` and `missing`

`complete: false` means the cache holds this entity but not every field the
fragment names. `missing` describes which. It happens when:

- a mutation returned a **narrower selection set** than the fragment (the common
  cause — see `queries-and-mutations.md`);
- an `optimisticResponse` omitted fields;
- the entity was written by a different query that selected less;
- a field was `evict`ed.

**Always handle it.** Rendering `data` when `complete` is `false` is where
`undefined` field crashes come from. Options, in order of preference: render a
skeleton for that row, render the partial data if the missing fields are
genuinely optional, or refetch. Never `data!`.

If `complete` is false and stays false, the fix is upstream — widen the
selection set that wrote the entity. It is not a rendering problem.

## `@unmask` — the escape hatch

```graphql
query GetPersons {
  persons {
    id
    ...Person_Row @unmask
  }
}
```

The parent can now read `Person_Row`'s fields. Legitimate uses are narrow:

- **Migration**, with `@unmask(mode: "migrate")` — see `adoption.md`.
- **A boundary that must serialize the whole object** — writing to local
  storage, posting to an analytics sink, handing data to a non-GraphQL library.
- **Test setup** that asserts on a full payload.

Not legitimate: making a type error go away. That error is the boundary doing
its job, and the fix is for the consuming component to declare the field.

With the client preset, `@unmask` needs no extra config. On the
`typescript-operations` path it requires `customDirectives: { apolloUnmask: true }`.

## The fragment registry

Apollo must be able to resolve a fragment by name when a document references one
it does not itself contain — some cache operations and `useFragment` calls in
generic helpers hit this. Register them centrally:

```typescript
import { InMemoryCache } from '@apollo/client';
import { createFragmentRegistry } from '@apollo/client/cache';

new InMemoryCache({
  fragments: createFragmentRegistry(PERSON_ROW, LABEL_CHIP),
});
```

Most apps never need it, because the client preset inlines fragment definitions
into every document that spreads them. Reach for it only when you hit a
"fragment X not found" error, and register the specific fragment — a registry
listing every fragment in the app is a shared-mutable-namespace waiting to
collide.

## Cache helpers worth having

```typescript
// Drop a root query field so the next read refetches it.
cache.evict({ id: 'ROOT_QUERY', fieldName: 'persons' });
cache.gc();

// Append to a list field without refetching.
cache.modify({
  fields: {
    persons: (existing = [], { toReference }) => [...existing, toReference(newPerson)],
  },
});

// Remove an entity entirely after a delete.
cache.evict({ id: cache.identify({ __typename: 'Person', id }) });
cache.gc();
```

`cache.gc()` after an evict matters — evicting leaves dangling references until
it runs, and a dangling reference reads as `complete: false`.

## Debugging

| Symptom | Cause |
| --- | --- |
| Field is `undefined` but type-checks | `apollo-client.d.ts` bridge missing or outside `tsconfig` include |
| Field is `undefined` and errors correctly | the component did not declare it — add it to the fragment |
| `complete: false` forever after a create | mutation's selection set is narrower than the fragment |
| Row shows stale data after a sibling mutation | entity not normalized — missing `id`, or wrong `keyFields` |
| Two rows show each other's data | a type with `keyFields` colliding; likely wants `keyFields: false` |
| "Fragment X not found" | fragment not inlined and not in the registry |
| Unions never narrow | `__typename` not selected, or `possibleTypes` missing |
| Everything re-renders on any mutation | `getFragmentData` where `useFragment` belongs, in a long list |
