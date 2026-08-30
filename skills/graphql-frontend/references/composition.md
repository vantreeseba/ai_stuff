# Composing fragments

Composition is always **spread upward**: a component's fragment spreads the
fragments of the components it renders, and the chain terminates at a query.

```
GetPersons (query, screen)
  └ Person_List (list)
      ├ Person_Row (row)
      │   └ Label_Chip (chip)
      └ Person_Badges (badges)
```

Every level names only its own fields plus spreads. Nobody reaches past a child.

## Lists

The list owns the fragment for the collection element, not for the connection:

```tsx
const PERSON_LIST = graphql(`
  fragment Person_List on Person {
    id
    ...Person_Row
  }
`);

function PersonList({ persons }: { persons: Array<FragmentType<typeof PERSON_LIST>> }) {
  const items = getFragmentData(PERSON_LIST, persons);
  return items.map((p) => <PersonRow key={p.id} person={p} />);
}
```

The container spreads it inside the connection shape it knows about:

```graphql
query GetPersons($after: String) {
  persons(first: 20, after: $after) {
    pageInfo { hasNextPage endCursor }
    edges {
      cursor
      node { id ...Person_List }
    }
  }
}
```

**Pagination belongs to the container.** `pageInfo`, `cursor`, `first`, `after`,
and the `fetchMore` call are all the fetching component's business; the list
component receives an array and knows nothing about how it was assembled. That
is what lets the same list render a paginated query, a search result, and a
cached subset.

## Interfaces and unions

One fragment per concrete type, and the composing fragment uses inline spreads
to route:

```tsx
const NOTIFICATION_ITEM = graphql(`
  fragment Notification_Item on Notification {
    __typename
    id
    createdAt
    ... on MentionNotification { ...Mention_Item }
    ... on InviteNotification { ...Invite_Item }
  }
`);

function NotificationItem({ notification }: { notification: FragmentType<typeof NOTIFICATION_ITEM> }) {
  const n = getFragmentData(NOTIFICATION_ITEM, notification);

  switch (n.__typename) {
    case 'MentionNotification':
      return <MentionItem notification={n} />;
    case 'InviteNotification':
      return <InviteItem notification={n} />;
    default:
      return null;
  }
}
```

Two rules:

- **Select `__typename` explicitly** wherever you branch on it. Apollo adds it
  automatically to the network document, but the *generated type* only narrows
  the union when the selection set names it.
- **Always have a `default`.** A schema can add a member to a union at any time,
  and a client compiled before that must not crash on it.

Interfaces need `possibleTypes` in the cache config for fragment matching to
work at all — generate it (`fragment-matcher` plugin or the client preset's
`possibleTypes` output) rather than hand-maintaining it.

## Conditional spreads

```graphql
query GetPerson($id: ID!, $withHistory: Boolean! = false) {
  person(id: $id) {
    id
    ...Person_Detail
    ...Person_History @include(if: $withHistory)
  }
}
```

The generated type makes the conditional fragment's reference optional, so the
consuming component's prop must accept `undefined` and render nothing for it.
Do not paper over that with `!`.

## Fragments cannot take arguments

Apollo Client has **no** `@arguments` / `@argumentDefinitions` — those are Relay
features. A fragment that needs a value reads an **operation variable**:

```graphql
fragment Person_Avatar on Person {
  id
  avatarUrl(size: $avatarSize)
}
```

Every query that spreads `Person_Avatar`, at any depth, must then declare
`$avatarSize`. Codegen enforces this and the error names the missing variable.

This plumbing is the real cost, and it is a design signal: a fragment needing a
variable from three levels up usually wants the value passed as a **prop** with
the field fetched unparameterised, or the parameterisation lifted into the
query's own selection. Reserve variable-consuming fragments for cases where the
argument genuinely changes what the server must do.

## `@defer` and `isFragmentReady`

For an expensive section that should not hold up first paint:

```graphql
query GetPerson($id: ID!) {
  person(id: $id) {
    id
    ...Person_Header
    ...Person_ActivityFeed @defer
  }
}
```

```tsx
const person = data.person;

{isFragmentReady(GET_PERSON, PERSON_ACTIVITY_FEED, person)
  ? <PersonActivityFeed person={person} />
  : <ActivitySkeleton />}
```

`isFragmentReady` is emitted by the client preset. It exists because a deferred
fragment's reference is present in the type but its data has not arrived yet —
a plain truthiness check on the reference is always `true` and renders a
component over missing fields.

Requires server support for incremental delivery. Without it, `@defer` is either
a schema error or silently ignored, depending on the server.

## Depth

Nothing enforces a limit, but a chain deeper than about four spreads usually
means intermediate components exist only to pass data through. Collapse those:
if a component's entire fragment is a single spread and its render is a single
child, it is not earning the indirection.
