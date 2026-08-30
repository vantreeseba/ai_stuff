# Data fetching

## Always the generated `graphql()` helper

```typescript
import { graphql } from '@/__generated__/gql';

const GET_PERSONS = graphql(`
  query GetPersons {
    persons {
      id
      ...Person_List
    }
  }
`);
```

**Never `gql` from `@apollo/client`, never a plain string.** The generated helper
is an overloaded function mapping each document *string literal* to its exact
generated type, so `useQuery(GET_PERSONS)` gives `data` a precise shape and
`variables` a checked one. `gql` gives you `any`.

This is also why the document must be a **literal** — no interpolation, no
`${}`, no conditional string building. The helper's overload set is generated
from the literals found in the source; an interpolated one is not in it.

Operation names are unique across the app (`GetPersons`, not `Get`), because
codegen puts them all in one namespace.

## Operations are colocated

A query lives in the route file that uses it. A fragment lives in the component
that reads it. There is no `queries/` directory.

```
routes/persons/index.tsx        query GetPersons, mutation CreatePerson
components/domain/person/list.tsx   fragment Person_List
components/domain/person/form.tsx   (no fragment — it takes props)
```

## Fragment colocation with `useFragment`

The parent query fetches `id` and spreads the fragment; the row reads its own
fields from the cache. With `dataMasking: true` this is enforced — the parent
literally cannot see the fields inside the fragment.

```tsx
const PERSON_LIST = graphql(`
  fragment Person_List on Person {
    id
    firstName
    lastName
    email
    labels { id label color }
  }
`);

function PersonRow({ person: from }: { person: FragmentType<typeof PERSON_LIST> }) {
  const { data: person, complete } = useFragment({ fragment: PERSON_LIST, from });

  if (!complete) return <Spinner />;

  return <Card>{person.firstName} {person.lastName}</Card>;
}
```

Points that matter:

- **Name fragments `<Type>_<Consumer>`** — `Person_List`, `TodoList_TodoListList`.
  Codegen requires globally unique fragment names, and this scheme makes
  collisions structurally impossible while saying where it is read.
- **The prop type is `FragmentType<typeof FRAGMENT>`**, not the entity type. It
  is opaque: the parent can pass it along but cannot read through it.
- **`complete` must be handled.** It is `false` when the cache holds a partial
  object — for example the row was created by a mutation that returned fewer
  fields than the fragment names. Rendering an incomplete object is where
  `undefined` field crashes come from.
- **Adding a field is a one-file change.** The fragment gains it, and every
  parent query picks it up automatically because they spread the fragment.

## Hooks

```tsx
const { data, loading, error } = useQuery(GET_PERSONS);

const [createPerson, { loading: creating }] = useMutation(CREATE_PERSON, {
  update: (cache) => invalidate(cache, 'persons'),
});
```

Variables are typed from the document, so `useQuery(GET_PERSON, { variables: { id } })`
checks `id` against the operation's declared type.

For a query whose variables are not ready yet, `skip`:

```tsx
const { data } = useQuery(GET_PERSON, { variables: { id: id! }, skip: !id });
```

## Loading and error states

One consistent shape, so pages do not each invent their own:

| State | Render |
| --- | --- |
| first load, no cached data | `<Skeleton />` matching the final layout |
| refetching with cached data | render the data; no spinner |
| inline/action pending | `<Spinner />` inside the button, button disabled |
| error | an inline error region with `role="alert"` |
| empty result | an empty state with the primary action, never a blank page |

`cache-and-network` means `loading` is `true` on a background refetch while
`data` is already populated. **Branch on `data` first, then `loading`** — the
other order flashes a skeleton over good content on every revisit:

```tsx
if (!data) {
  return loading ? <PersonListSkeleton /> : <ErrorState error={error} />;
}
return <PersonList persons={data.persons} />;
```

Extract that into a `QueryState` wrapper once three pages need it.

## Errors

The client's global `ErrorLink` handles `UNAUTHENTICATED` / `FORBIDDEN` by
clearing the token and redirecting. Everything else is the component's problem:

```tsx
try {
  await createPerson({ variables: { input } });
} catch (err) {
  setFormError(err instanceof Error ? err.message : 'An unexpected error occurred.');
}
```

Never render a raw `error` object. Never `console.error` and show nothing.

Branch on `extensions.code`, never on message text — the server's codes
(`NOT_FOUND`, `BAD_USER_INPUT`, `FORBIDDEN`) are the stable contract; the
messages are not.

## The `@0no-co/graphqlsp` TS plugin

Add it to `tsconfig.json` and the editor validates GraphQL documents against the
schema *as you type* — unknown fields, wrong argument types, and missing
variables become squiggles rather than codegen failures:

```json
{
  "compilerOptions": {
    "plugins": [
      {
        "name": "@0no-co/graphqlsp",
        "schema": "../schema.graphql",
        "tadaOutputLocation": "./src/__generated__/graphql-env.d.ts"
      }
    ]
  }
}
```

It requires the workspace TypeScript version, not the editor's bundled one.

## Codegen

```bash
npm run codegen
```

After any change to a query, a fragment, or the server schema. If `typecheck`
reports errors in `__generated__/` or in files you did not touch, the answer is
almost always a stale codegen run. See the `graphql-codegen` skill if available.
