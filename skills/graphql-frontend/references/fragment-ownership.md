# Fragment ownership

The rule: **the component that names a server field declares the fragment that
requests it.** Not its parent, not a shared `queries/` module, not a hook.

## A leaf component

```tsx
import { graphql, getFragmentData, type FragmentType } from '@/__generated__';

const PERSON_ROW = graphql(`
  fragment Person_Row on Person {
    id
    firstName
    lastName
    email
  }
`);

export function PersonRow({ person }: { person: FragmentType<typeof PERSON_ROW> }) {
  const { firstName, lastName, email } = getFragmentData(PERSON_ROW, person);

  return (
    <Card>
      <Text>{firstName} {lastName}</Text>
      <Text>{email}</Text>
    </Card>
  );
}
```

Four things are load-bearing:

1. **The fragment is a module-level `const` built by `graphql()` against a
   string literal.** No interpolation, no `${}`, no conditional assembly — the
   generated helper is an overload set keyed on the literals found in source, so
   an interpolated document falls off the end of it and types resolve to
   `DocumentNode` / `any`.
2. **It sits above the component in the same file.** Reading the component and
   reading its data requirement is one scroll.
3. **The prop type is `FragmentType<typeof PERSON_ROW>`, never `Person`.** The
   parent can hold it and pass it, and cannot read through it. That is the
   entire boundary.
4. **`id` is selected.** Without it the cache cannot normalize the entity, and
   the fragment cannot be re-read later.

## A composite component

It spreads its children's fragments and does not repeat their fields:

```tsx
const PERSON_LIST = graphql(`
  fragment Person_List on Person {
    id
    ...Person_Row
    ...Person_Badges
  }
`);

export function PersonList({ persons }: { persons: Array<FragmentType<typeof PERSON_LIST>> }) {
  const rows = getFragmentData(PERSON_LIST, persons);

  return (
    <View>
      {rows.map((person) => (
        <View key={person.id}>
          <PersonRow person={person} />
          <PersonBadges person={person} />
        </View>
      ))}
    </View>
  );
}
```

`getFragmentData` is overloaded for arrays, so one call unwraps the whole list.
`person` after unwrapping still carries the `$fragmentRefs` markers for
`Person_Row` and `Person_Badges` — which is precisely what makes it assignable
to those components' props. It is not readable as a `Person`.

**A composite must not read a child's fields.** If `PersonList` wants
`firstName` for a sort, it adds `firstName` to `Person_List` itself. Duplication
between a parent's fragment and a child's is fine and expected — the server
deduplicates the selection set, and each component's requirement stays honest.

## A container

The route, screen, or page that actually fetches:

```tsx
const GET_PERSONS = graphql(`
  query GetPersons {
    persons {
      id
      ...Person_List
    }
  }
`);

export function PersonsScreen() {
  const { data, loading, error } = useQuery(GET_PERSONS);

  if (!data) return loading ? <PersonListSkeleton /> : <ErrorState error={error} />;
  return <PersonList persons={data.persons} />;
}
```

The container sees `id` and an opaque reference. It could not render a name if
it wanted to — and that is the point: the query never drifts from what the tree
below it actually reads.

## What goes in a fragment

**Yes:** every field the component reads, `id` (or whatever `keyFields` names),
`__typename` where the component branches on type, spreads of the fragments of
components it renders.

**No:**

- Fields a *sibling* needs. That sibling declares them.
- Fields only a *callback* passes along. If the row's delete button needs
  `person.id` for the mutation, `id` is already there; it does not need `email`
  because the toast mentions it — the toast's component asks for `email`.
- Root-level arguments or pagination cursors. Those belong to the query.
- Anything "we might need later."

## Presentational components take props

```tsx
// Right — no fragment, reusable, trivially testable.
function Badge({ label, color }: { label: string; color: string }) { … }

// Wrong — couples a generic UI primitive to a schema type.
function Badge({ label }: { label: FragmentType<typeof LABEL_BADGE> }) { … }
```

Design-system primitives never get fragments. The domain component that renders
a `Badge` owns the fragment and maps fields onto its props.

## When a fragment is the wrong tool

A component rendered from data that was *never fetched by a GraphQL query* —
form state, a local draft, an optimistic row built client-side — takes plain
props. Do not manufacture a fragment reference for it. If you need to render a
fragment-typed component from plain data (a Storybook story, a test, a fixture):

```tsx
import { makeFragmentData } from '@/__generated__';

const person = makeFragmentData(
  { __typename: 'Person', id: '1', firstName: 'Ada', lastName: 'Lovelace', email: 'ada@example.com' },
  PERSON_ROW,
);

render(<PersonRow person={person} />);
```

`makeFragmentData` type-checks the object against the fragment, so a fixture
cannot drift from the selection set.

## Mistakes that quietly undo the boundary

| Mistake | What it costs |
| --- | --- |
| Prop typed as the entity (`person: Person`) instead of `FragmentType<…>` | the parent can read everything; masking becomes decorative |
| `getFragmentData` called in the parent and the *result* passed down | same — the child no longer states its own requirement |
| Fields listed in the query instead of spread from a fragment | the query drifts from the tree; deleting a component leaves dead fields |
| One shared "kitchen sink" fragment per type | every screen over-fetches, and nothing can be removed safely |
| Fragment defined in a `fragments.ts` next to the component | the requirement is one file away from the code that depends on it |
| Two fragments on one component | it is two components |

## One-fragment-per-component, and the exception

The exception is a component with genuinely distinct modes rendered from
different parents — a `PersonCard` used compactly in a list and fully on a
detail page. Prefer splitting into `PersonCardCompact` and `PersonCardFull`,
each owning a fragment. Take the two-fragment route only when the render logic
is truly shared, and then name them `Person_CardCompact` / `Person_CardFull` and
pass `fragmentName` where any API needs to disambiguate.
