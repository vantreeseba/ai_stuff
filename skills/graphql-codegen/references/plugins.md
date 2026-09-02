# Plugins, wiring, and debugging

## Which binary

| Config | Binary |
| --- | --- |
| `codegen.server.ts` | `graphql-codegen-esm` |
| `codegen.ts` (client) | `graphql-codegen` |

`graphql-codegen-esm` is what loads a `"type": "module"` config and emits ESM.
The plain binary works for the client preset, which emits ESM regardless.

## Root scripts

```json
{
  "generate:schema": "node --experimental-strip-types server/generate_schema.ts",
  "codegen:server": "graphql-codegen-esm --config codegen.server.ts",
  "codegen:client": "graphql-codegen --config codegen.ts",
  "codegen": "npm run generate:schema && npm run codegen:server && npm run codegen:client"
}
```

In a repo where each workspace owns its own config, the root delegates instead:

```json
{
  "codegen": "npm run codegen:server && npm run codegen:app",
  "codegen:app": "npm run codegen -w app",
  "codegen:server": "npm run codegen -w server"
}
```

Either way the **order is fixed** — schema, then server, then client — because
each step reads the previous step's *file*.

## Making codegen unskippable

`__generated__/` is gitignored, so nothing downstream can assume it exists.

```json
{
  "pretypecheck": "npm run codegen",
  "pretest": "npm run codegen",
  "prebuild": "npm run codegen"
}
```

- A package whose whole purpose is generated output gets a `prepare` script, so
  `npm install` produces it and the answer to "do I need to run codegen?" is
  normally no.
- The Dockerfile needs an explicit `RUN npm run codegen` before the build —
  the generated tree is not in the build context.
- `dev` and `build` at the root run it first (`npm run codegen && …`).

A stale `__generated__/` reports type errors that do not exist and hides ones
that do. This is the single most common way to lose an hour in this stack.

## The additional generators

| Plugin | Emits | Consumed by |
| --- | --- | --- |
| `@vantreeseba/graphql-casl-codegen` | `permissions.ts` — `Subject`, `typed`, `ability`, `AppSubjectMap` | the CASL permissions middleware |
| `@vantreeseba/graphql-mocks-codegen` | `schema-type-map.ts` — `SchemaTypeMap` | `buildMocks<SchemaTypeMap>` in tests |
| `@cubicecho/graphql-codegen-field-descriptions` | SDL field descriptions as a runtime map | MCP tool descriptions, runtime docs |
| `@homebound/graphql-typescript-scalar-type-policies` | Apollo scalar type policies | the client cache |

Both `@vantreeseba` plugins validate that every config value they receive is a
string, and `graphql-codegen-esm` injects a boolean `emitLegacyCommonJSImports`.
Pass `{ emitLegacyCommonJSImports: undefined }` to each — they skip undefined
values.

## Plugin combinations that fight each other

- **`typescript` + `typescript-operations` in a client SDK.** The `typescript`
  plugin emits the *whole* schema — every filter and order-by drizzle-graphql
  generates, none of which a client imports — and it re-declares the input types
  `typescript-operations` already emits for operation variables. A duplicate
  `PingInput` is a compile error. It also collides on enums:
  `typescript-operations` re-declares any enum an operation selects unless the
  schema types come from another file.
- **`typescript-generic-sdk` with `documentMode: 'string'`** emits
  `new TypedDocumentString(...)` but leaves the definition to the client-preset
  runtime. If you are not using that preset, supply a minimal shim via the `add`
  plugin:

  ```typescript
  {
    add: {
      content: [
        'class DocumentString extends String {}',
        'const TypedDocumentString = DocumentString as unknown as new (value: string) => string;',
      ].join('\n'),
    },
  }
  ```

  `documentMode: 'string'` is worth it where the `graphql` package must stay out
  of the runtime deps — a browser bundle, or an agent running from TS source.

## Editor support

`@0no-co/graphqlsp` as a `tsserver` plugin gives red squiggles inside
`graphql()` literals for unknown fields and wrong variable types, before codegen
runs:

```json
{
  "compilerOptions": {
    "plugins": [
      {
        "name": "@0no-co/graphqlsp",
        "schema": "./server/src/__generated__/schema.graphql",
        "disableTypegen": true
      }
    ]
  }
}
```

`disableTypegen: true` — codegen owns type generation; the plugin is only there
for diagnostics.

## Committing the schema

Two positions, both defensible — follow the repo:

- **Gitignore everything generated.** Simpler; nothing can go stale in git.
  Requires codegen in every CI and Docker path.
- **Commit `schema.graphql`, gitignore what is generated from it.** An API
  change then shows up in the diff a reviewer reads, and no consumer needs a
  running server to generate against.

Under either, a schema change that breaks a consumer **fails `typecheck` in that
consumer's package** rather than at runtime — including the server, whose
resolvers stop compiling when a field's arguments change. Keep each consumer's
operations somewhere codegen validates (one `operations.graphql`, or colocated
documents in the `documents` glob), so a query for a dropped field fails the
build rather than the request.

## Debugging

| Symptom | Cause |
| --- | --- |
| Operation types are `unknown` / `any` | raw `gql` instead of `graphql()`, an interpolated document string, or the file's directory is not in `documents` |
| "Cannot find module `__generated__/…`" | codegen has not run; check the `pre*` hook |
| Resolver "not assignable" after a schema change | stale `resolvers.ts` — regenerate |
| Mapper type collides with the SDL type | missing ` as XRow` alias |
| Duplicate `XInput` / duplicate enum | `typescript` and `typescript-operations` in the same output file |
| Codegen hangs, or asks for a DB | `generate_schema.ts` is importing the runtime `db` singleton instead of constructing its own |
| Circular import at codegen time | the schema builder imports its own generated output — generate from the base builder |
| Plugin throws on `emitLegacyCommonJSImports` | pass `{ emitLegacyCommonJSImports: undefined }` to that plugin |
| Client preset emits one file, not a directory | missing trailing `/` on the `generates` key |
