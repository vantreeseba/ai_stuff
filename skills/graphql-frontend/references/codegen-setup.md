# Codegen and client setup

Three things have to agree: the codegen config, the Apollo client, and one
declaration-merge file that tells Apollo that codegen's masked types are the
masked types it should reason about.

## 1. Codegen — the client preset

```typescript
// codegen.ts
import type { CodegenConfig } from '@graphql-codegen/cli';

const config: CodegenConfig = {
  schema: '../schema.graphql',
  documents: ['src/**/*.{ts,tsx}', '!src/__generated__/**'],
  generates: {
    // Trailing slash is required — the client preset emits a directory.
    './src/__generated__/': {
      preset: 'client',
      presetConfig: {
        gqlTagName: 'graphql',
        // Masking is ON by default with this preset. Renaming the unwrap
        // function keeps it from colliding with Apollo's own `useFragment`
        // and stops react-hooks lint rules firing on a non-hook.
        fragmentMasking: { unmaskFunctionName: 'getFragmentData' },
      },
      config: {
        scalars: { UUID: 'string', DateTime: 'Date' },
        avoidOptionals: { field: true },
        useTypeImports: true,
      },
    },
  },
};

export default config;
```

`documents` must cover **every** file that can hold a fragment. In an Expo
project that includes the `app/` route directory, not only `src/`.

### What the preset emits

| File | Contents |
| --- | --- |
| `gql.ts` | the `graphql()` helper — an overload per document literal found |
| `graphql.ts` | operation and fragment types |
| `fragment-masking.ts` | `FragmentType`, the unwrap function, `makeFragmentData`, `isFragmentReady` |
| `index.ts` | re-exports the above |

Import from the directory, not the individual files:

```typescript
import { graphql, getFragmentData, type FragmentType } from '@/__generated__';
```

The directory is generated. It is gitignored and never edited by hand.

## 2. Apollo — `dataMasking`

```typescript
import { ApolloClient, InMemoryCache, HttpLink } from '@apollo/client';

export const client = new ApolloClient({
  link: new HttpLink({ uri: '/graphql' }),
  cache: new InMemoryCache(),
  dataMasking: true,
});
```

Requires Apollo Client **3.12+**; in 4.x it is the same option. With it on, a
query result genuinely omits the fields that live inside a spread fragment —
`data.persons[0].email` is `undefined` at runtime, not merely untyped.

Turning this on without codegen masking gives you runtime holes with no type
errors pointing at them, which is the worst of the three combinations. Either
both, or neither.

## 3. The bridge — `apollo-client.d.ts`

Apollo needs to recognise codegen's `FragmentType`/`$fragmentRefs` markers as
its own masking markers. One file, anywhere in the type roots:

```typescript
// src/apollo-client.d.ts

// This import is necessary to ensure all Apollo Client imports
// are still available to the rest of the application.
import '@apollo/client';
import type { GraphQLCodegenDataMasking } from '@apollo/client/masking';

declare module '@apollo/client' {
  interface TypeOverrides extends GraphQLCodegenDataMasking.TypeOverrides {}
}
```

Without it, `useQuery` keeps reporting the **unmasked** type while the runtime
returns masked data — every masked field type-checks and is `undefined`. If you
see that symptom, this file is missing or outside `include` in `tsconfig.json`.

## The generated masking API

```typescript
// Opaque prop type. Holds a phantom reference to the fragment; nothing readable.
type FragmentType<TDocumentType> = /* … */;

// Pure type narrowing. NOT a hook — no cache subscription, no re-render.
// Overloaded for a single value, an array, and nullable variants.
function getFragmentData<TType>(
  documentNode: DocumentNode,
  fragmentType: FragmentType<...>,
): TType;

// Wraps plain data as a fragment reference. For tests, Storybook, fixtures.
function makeFragmentData<F, FT>(data: FT, fragment: F): FragmentType<F>;

// True once a `@defer`red fragment has arrived. See composition.md.
function isFragmentReady(query, fragment, data): boolean;
```

`getFragmentData` compiles away to an identity function. Calling it costs
nothing and can be done anywhere — inside a `map`, at the top of a component,
in a plain helper.

## Apollo's `useFragment` — a different thing

```typescript
const { data, complete, missing } = useFragment({
  fragment: PERSON_ROW,
  fragmentName: 'Person_Row', // only when the document holds several
  from: personRef,            // a FragmentType, or { __typename, id }
});
```

Object argument, real hook, subscribes to the cache. Use it when a component
should re-render on cache changes to *its* entity independently of the query
that fetched it. Use `getFragmentData` when the data arrives as a prop and a
re-render of the parent is the right trigger. Details in
`cache-and-masking.md`.

## Alternative: without the client preset

A repo on the older `typescript` + `typescript-operations` + a hooks plugin
setup gets masking from plugin config rather than a preset:

```typescript
config: {
  inlineFragmentTypes: 'mask',
  customDirectives: { apolloUnmask: true },
}
```

`inlineFragmentTypes: 'mask'` produces the `$fragmentRefs` markers; the
`customDirectives` entry makes codegen understand `@unmask`. There is no
`FragmentType`/`getFragmentData` here — components take the generated
`Person_RowFragment` type directly and get their live data through Apollo's
`useFragment`. That is a coherent setup and several real codebases use it.

**Prefer the client preset for new work.** It is smaller output, it enforces the
boundary at the prop type rather than by convention, and it is where upstream
effort goes.

## Editor feedback before codegen runs

```json
{
  "compilerOptions": {
    "plugins": [
      { "name": "@0no-co/graphqlsp", "schema": "../schema.graphql" }
    ]
  }
}
```

Validates documents against the schema as you type — unknown fields and missing
variables become squiggles instead of codegen failures. Requires the workspace
TypeScript version, not the editor's bundled one.
