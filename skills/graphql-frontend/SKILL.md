---
name: graphql-frontend
description: >
  Structure a GraphQL client around component-owned fragments — Apollo Client
  with `dataMasking`, GraphQL Code Generator's client preset with fragment
  masking, fragments declared by the domain component that renders them, and
  composed upward by whatever assembles those components. Use when setting up a
  GraphQL client, adding or changing a query, deciding where a fragment lives,
  or debugging a masked/undefined field.
version: 0.0.1
license: MIT
---

# GraphQL Frontend

Framework-agnostic: this applies equally to a Vite/React web client and an Expo
client. If a `simple-ts-frontend` or `expo-frontend` skill is available, read it
for the surrounding stack (routing, styling, forms) and this one for the data
layer. If a `graphql-codegen` skill is available, read it for the codegen
pipeline as a whole; this skill covers only the client-side configuration.

## The thesis

**A component owns the definition of the data it renders.** If a component reads
`person.email`, that component declares a fragment naming `email`. Nothing above
it in the tree needs to know that.

Everything else in this skill follows from that one rule:

- A component that *renders* fields declares a **fragment**.
- A component that *composes* other components spreads **their** fragments — it
  does not re-list their fields.
- A component that *fetches* (a route, a screen, a page) writes the **query**,
  spreading the fragments of the components it renders.

The payoff: adding a field is a one-file change. The fragment gains it, and
every query that spreads it — directly or transitively — picks it up. Removing
a component removes its data requirement with it, so queries never accumulate
fields nothing reads any more.

Masking is what turns that from a convention into a boundary the compiler and
the runtime both enforce.

## The two maskings — do not conflate them

Two independent features share the name "fragment masking" and even export two
different functions called `useFragment`. Getting these mixed up is the single
most common failure here.

| | codegen `fragmentMasking` | Apollo `dataMasking` |
| --- | --- | --- |
| Where | `codegen.ts`, client preset | `new ApolloClient({ dataMasking: true })` |
| Level | Types only | Runtime — fields are actually absent |
| Prop type | `FragmentType<typeof FRAG>` | — |
| Unwrap with | `useFragment(FRAG, data)` — **positional, not a hook** | `useFragment({ fragment, from })` — **a real hook** |
| Returns | the data, narrowed | `{ data, complete, missing }` |
| Default | **on** with the `client` preset | off |

Both on is the recommended setup, and then the name collision is real: rename
the generated one to `getFragmentData` via `presetConfig` so `getFragmentData()`
(pure type narrowing) and `useFragment()` (a cache subscription) never get
confused, and so React's hook lint rules stop firing on the former.

→ **[`references/codegen-setup.md`](references/codegen-setup.md)** — the client
preset config, `unmaskFunctionName`, the `apollo-client.d.ts` declaration merge
that teaches Apollo about codegen's masked types, the non-client-preset
alternative, and version requirements.

## Component roles

| Role | Declares | Prop type | Reads with |
| --- | --- | --- | --- |
| **Leaf** — renders fields | a fragment | `FragmentType<typeof FRAG>` | `getFragmentData` |
| **Composite** — renders leaves | a fragment spreading theirs | `FragmentType<typeof FRAG>` | `getFragmentData`, then passes through |
| **Container** — fetches | a query spreading fragments | none (route params) | `useQuery` |
| **Presentational** — no server data | nothing | plain values | — |

A component that takes `label: string` and `onPress: () => void` is
presentational and must **not** get a fragment. Fragments are for components
that name server fields.

→ **[`references/fragment-ownership.md`](references/fragment-ownership.md)** —
the rules with worked examples, what belongs in a fragment and what does not,
`makeFragmentData` for tests, and the mistakes that undo the boundary.

## Naming

`<Type>_<Consumer>` — `Person_List`, `Label_Row`, `Person_DetailHeader`. Fragment
names are global in codegen's namespace, so this makes collisions structurally
impossible while stating where the fragment is read. One fragment per component;
if a component needs two, it is two components.

Files: the fragment lives in the same file as the component, above it, as a
module-level `const` built by the generated `graphql()` helper against a
**string literal**.

## Composition

Spread, never re-list. A list spreads its row's fragment; a screen spreads the
list's. Interfaces and unions get a fragment per concrete type plus inline
`... on Type` in the composing fragment.

Apollo has **no fragment arguments** (`@argumentDefinitions` is Relay-only) — a
fragment that needs a value reads it from an operation variable, which every
query spreading that fragment must then declare.

→ **[`references/composition.md`](references/composition.md)** — lists,
interfaces and unions, conditional spreads, `@defer` with `isFragmentReady`, and
the variable-plumbing rule.

## Queries and mutations

The query lives with the thing that fetches. A mutation's selection set must
spread the same fragments the UI renders, or the cache writes a partial entity
and `complete` goes `false` downstream.

The one gotcha worth memorizing: with `dataMasking`, a mutation's returned
`data` is **masked**, but the `update`, `refetchQueries`, and `updateQueries`
callbacks receive **unmasked** data.

→ **[`references/queries-and-mutations.md`](references/queries-and-mutations.md)**
— where operations live, the mutation selection-set rule, masked-vs-unmasked
callbacks, optimistic responses, and `MaybeMasked` / `Unmasked`.

## Cache and live reads

Masking is a view over the normalized cache, not a second store. Apollo's
`useFragment` subscribes a component to just its own fragment's fields, so a
row re-renders when *its* entity changes and not when a sibling does.

`complete` must be handled — it is `false` when the cache holds the entity but
not every field the fragment names, which is exactly what a too-narrow mutation
selection set produces.

→ **[`references/cache-and-masking.md`](references/cache-and-masking.md)** —
normalization and `keyFields`, live reads with `useFragment`, `complete` and
`missing`, when `@unmask` is legitimate, and the fragment registry.

## Adoption

Turning masking on in an existing app is a type-error avalanche if done in one
commit. Do it directive-first with `@unmask(mode: "migrate")`, which keeps the
fields present at runtime and logs on access, so the work is a list of log lines
rather than a broken build.

→ **[`references/adoption.md`](references/adoption.md)** — the migration order,
what to do when the repo already has masking off (follow the repo), and the
anti-pattern list.

## After changing any document

```bash
npm run codegen && npm run check && npm test
```

Codegen first, always. A fragment edit without a regenerate makes `typecheck`
report errors in files you did not touch.
