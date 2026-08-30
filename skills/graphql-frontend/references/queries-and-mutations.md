# Queries and mutations

## Where operations live

| Operation | Lives in |
| --- | --- |
| query | the route / screen / page file that fetches |
| mutation | the component that triggers it (or the route, when a form is presentational) |
| fragment | the component that renders the fields |
| subscription | the component that subscribes |

There is **no `queries/` directory**. A document in a shared module is a
document nobody can safely change, because its consumers are only discoverable
by grep.

Operation names are unique app-wide (`GetPersonsForTeam`, not `GetPersons`
twice) — codegen puts them in one namespace and duplicates are a hard error.

## Queries

```tsx
const GET_PERSONS = graphql(`
  query GetPersons($teamId: ID!) {
    persons(teamId: $teamId) {
      id
      ...Person_List
    }
  }
`);

const { data, loading, error } = useQuery(GET_PERSONS, { variables: { teamId } });
```

Variables are typed from the document. For a query whose variables are not ready:

```tsx
const { data } = useQuery(GET_PERSON, { variables: { id: id! }, skip: !id });
```

Under a `cache-and-network` default, `loading` is `true` on every background
refetch while `data` is already populated. **Branch on `data` first, then
`loading`** — the other order flashes a skeleton over good content on every
revisit.

## Mutations must select the fragments the UI renders

This is the rule that keeps `complete` true downstream:

```tsx
const UPDATE_PERSON = graphql(`
  mutation UpdatePerson($id: ID!, $input: PersonInput!) {
    updatePerson(id: $id, input: $input) {
      id
      ...Person_Row
      ...Person_DetailHeader
    }
  }
`);
```

Apollo normalizes the result by `id` and patches every cached view of that
entity. If the mutation returns only `{ id, firstName }` but `Person_Row` names
`email` too, the cache entry is overwritten in place for the fields returned and
stays as-is for the rest — but a *newly created* entity ends up partial, and
every `useFragment` on it reports `complete: false` forever. Symptom: a row that
renders a spinner after a create and only fixes itself on refresh.

Select the fragments of every component that will render the mutated entity.

## Masked results, unmasked callbacks

With `dataMasking: true`:

```tsx
const [updatePerson] = useMutation(UPDATE_PERSON, {
  // `data` here is UNMASKED — full access to everything the selection set named.
  update: (cache, { data }) => {
    cache.modify({ /* … */ });
  },
  refetchQueries: ({ data }) => { /* also unmasked */ return ['GetPersons']; },
});

const { data } = await updatePerson({ variables: { id, input } });
// `data` here is MASKED — `data.updatePerson.email` is undefined.
```

The asymmetry is deliberate: cache-manipulation callbacks are infrastructure and
need the whole payload, while the call site is application code and is held to
the same boundary as everything else.

So: **do not read a fragment field off a mutation's return value.** Read the
`id`, and let the components re-render from the cache. If the call site
genuinely needs a field (a toast naming the person), add that field to the
mutation's own selection set at the top level — outside any fragment — and it
comes back unmasked because nothing is masking it.

## `MaybeMasked` and `Unmasked`

For helpers that must work with either:

```typescript
import type { MaybeMasked, Unmasked } from '@apollo/client';

// MaybeMasked<T> — T's masked form when T carries the masking marker, else T.
// Unmasked<T>    — T with masking stripped, i.e. the full selection set.

function personLabel(person: Unmasked<PersonRowFragment>): string {
  return `${person.firstName} ${person.lastName}`;
}
```

Reach for these only in generic utilities and cache helpers. In component code,
needing `Unmasked` is a sign that a component is reading fields it did not
declare — fix the fragment instead.

## Optimistic responses

`optimisticResponse` is written into the cache directly, so it must be
**unmasked and complete** for every fragment the UI will read:

```tsx
await createPerson({
  variables: { input },
  optimisticResponse: {
    createPerson: {
      __typename: 'Person',
      id: `temp:${crypto.randomUUID()}`,
      firstName: input.firstName,
      lastName: input.lastName,
      email: input.email,
      // …every field named by Person_Row and Person_DetailHeader
    },
  },
});
```

Miss a field and the optimistic entity is partial, so the row that appears
instantly renders its `!complete` branch — a spinner where the point was to
avoid one. `__typename` is mandatory; without it nothing normalizes.

Use a recognisable temporary id (`temp:` prefix). The real id from the server
replaces the entry, and any code that persists ids can reject the temporary
shape rather than storing it.

## Cache updates after a mutation

Normalization already patches every view of an entity the mutation returns.
Only two things need explicit help:

1. **A list gaining or losing a member** — nothing tells the cache that a new
   `Person` belongs in `persons`.
2. **A server-computed field going stale** — a count, an aggregate, a derived
   status.

Repos differ on the remedy: smaller ones use `refetchQueries`, larger ones evict
root fields by name in `update`. **Follow the repo; do not mix within one.** The
eviction approach exists because naming *queries* couples a mutation to whichever
pages existed when it was written, so a page added later silently shows stale
data. If a `simple-ts-frontend` skill is available it documents the eviction
helpers in full.

## Subscriptions

A subscription's payload is another view of the same entities, so it selects the
same fragments:

```graphql
subscription OnPersonChanged($teamId: ID!) {
  personChanged(teamId: $teamId) {
    id
    ...Person_Row
  }
}
```

Subscribe **once**, as high in the tree as the data is used, not per row. Many
rows each opening a socket subscription is the standard way to melt a server.
